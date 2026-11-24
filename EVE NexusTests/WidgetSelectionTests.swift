import BackgroundTasks
import Foundation
import WidgetKit
import XCTest
@testable import EVE_Nexus

final class WidgetSelectionTests: XCTestCase {
    func testWidgetSizesAndRowLimits() {
        XCTAssertEqual(NexusWidgetKind.industryOverview.supportedFamilies, [.systemMedium])
        for kind in NexusWidgetKind.allCases where kind != .industryOverview {
            if #available(iOS 27, macOS 27, *) {
                XCTAssertEqual(kind.supportedFamilies, [.systemMedium, .systemLarge, .systemExtraLargePortrait])
            } else {
                XCTAssertEqual(kind.supportedFamilies, [.systemMedium, .systemLarge])
            }
        }
        XCTAssertEqual(WidgetFamily.systemMedium.nexusRowLimit, 3)
        XCTAssertEqual(WidgetFamily.systemLarge.nexusRowLimit, 6)
        if #available(iOS 27, macOS 27, *) {
            XCTAssertEqual(WidgetFamily.systemExtraLargePortrait.nexusRowLimit, 9)
        }
    }

    func testMarketUsesLabWatchlistOrderAndShowsPendingItems() {
        let watchlist = [
            WidgetChoice(id: 35, name: "Pyerite"),
            WidgetChoice(id: 999, name: "New item"),
            WidgetChoice(id: 34, name: "Tritanium"),
        ]
        let snapshot = WidgetSnapshot(market: [
            WidgetMarketItem(id: 34, name: "Tritanium", price: 4.2),
            WidgetMarketItem(id: 35, name: "Pyerite", price: 15),
        ])

        let displayed = snapshot.selection(
            for: .market, rowLimit: 2, marketWatchlist: watchlist, characterIDs: nil
        )

        XCTAssertEqual(displayed.market.map(\.id), [35, 999])
        XCTAssertEqual(displayed.market.first?.price, 15)
        XCTAssertEqual(displayed.market.last?.name, "New item")
        XCTAssertNil(displayed.market.last?.price)
    }

    func testSavedEmptyWatchlistAndRemovedItemsStayOutOfWidget() throws {
        let empty = try JSONEncoder().encode([WidgetChoice]())
        XCTAssertTrue(WidgetMarketWatchlist.decode(empty).isEmpty)
        XCTAssertEqual(WidgetMarketWatchlist.decode(nil), WidgetChoice.defaultMarket)

        let snapshot = WidgetSnapshot(market: [WidgetMarketItem(id: 34, name: "Tritanium", price: 4.2)])
        XCTAssertTrue(snapshot.selection(
            for: .market, rowLimit: 3, marketWatchlist: [], characterIDs: nil
        ).market.isEmpty)
    }

    func testMarketWatchlistKeepsFirstNineDistinctItems() throws {
        let items = (1...12).map { WidgetChoice(id: $0, name: "Item \($0)") }
        let saved = [items[0]] + items
        XCTAssertEqual(WidgetMarketWatchlist.decode(try JSONEncoder().encode(saved)), Array(items.prefix(9)))
        XCTAssertEqual(WidgetMarketWatchlist.limited(items).count, WidgetMarketWatchlist.maximumItems)
    }

    func testIndustryWidgetsShareSelectionKey() {
        let sharedKey = WidgetCharacterPreferences.settingsKey(for: .industryOverview)
        XCTAssertEqual(WidgetCharacterPreferences.settingsKey(for: .industryList), sharedKey)
        let selections = [sharedKey: [1, 4]]
        XCTAssertEqual(WidgetCharacterPreferences.selectedIDs(for: .industryOverview, in: selections), [1, 4])
        XCTAssertEqual(WidgetCharacterPreferences.selectedIDs(for: .industryList, in: selections), [1, 4])
        XCTAssertEqual(WidgetCharacterPreferences.selectedIDs(for: .industryList, in: [sharedKey: []]), [])
    }

    func testIndustrySlotCountsUseTrainedLevelsAndGroupResearchActivities() {
        let skill = CharacterSkill(active_skill_level: 2, skill_id: 42, skillpoints_in_skill: 0, trained_skill_level: 5)
        let bonuses = [42: IndustrySlotCounts(manufacturing: 2, research: 1)]
        XCTAssertEqual(
            IndustrySlotCounts.capacity(for: [42: skill], bonuses: bonuses),
            IndustrySlotCounts(manufacturing: 11, research: 6, reaction: 1)
        )
        XCTAssertEqual(
            IndustrySlotCounts.used(by: [1, 3, 4, 5, 8, 9, 19]),
            IndustrySlotCounts(manufacturing: 1, research: 4, reaction: 1)
        )
    }

    func testCharacterSelectionDefaultsToAllAndRespectsEmptySelection() {
        let snapshot = WidgetSnapshot(
            characters: [WidgetCharacter(id: 1, name: "One"), WidgetCharacter(id: 2, name: "Two")]
        )

        XCTAssertEqual(snapshot.selection(
            for: .skills, rowLimit: 3, marketWatchlist: [], characterIDs: nil
        ).characters.map(\.id), [1, 2])
        XCTAssertEqual(snapshot.selection(
            for: .planets, rowLimit: 3, marketWatchlist: [], characterIDs: [2, 3]
        ).characters.map(\.id), [2])
        XCTAssertTrue(snapshot.selection(
            for: .industryOverview, rowLimit: 3, marketWatchlist: [], characterIDs: []
        ).characters.isEmpty)
    }

    func testEveryWidgetSettingsURLRoutesBackToItsOwnType() {
        for kind in NexusWidgetKind.allCases {
            XCTAssertEqual(NexusWidgetKind(settingsURL: kind.settingsURL), kind)
        }
        XCTAssertNil(NexusWidgetKind(settingsURL: WidgetSnapshot.settingsURL))
    }

    func testPlanetRowsKeepStableOrderSoMissingRowsCanBeRefreshed() {
        let planet = WidgetPlanet(id: 1, name: "Colony", planetType: "temperate", hasExtractor: false, cycles: [])
        let snapshot = WidgetSnapshot(characters: [
            .init(id: 1, name: "Waiting"),
            .init(id: 2, name: "Cached", planets: [planet]),
            .init(id: 3, name: "No colonies", planets: []),
        ])
        XCTAssertEqual(snapshot.planetRows.map(\.id), [1, 2, 3])
        XCTAssertNil(snapshot.planetRows[0].planets)
        XCTAssertEqual(snapshot.planetRows[2].planets, [])
    }

    func testWidgetBackgroundRefreshPreservesEarlierAndSupportsReplace() {
        let now = Date(timeIntervalSince1970: 10_000)
        let pending = BGAppRefreshTaskRequest(identifier: WidgetBackgroundRefresh.identifier)
        XCTAssertTrue(WidgetBackgroundRefresh.shouldSubmit(earliest: now, pending: nil))
        XCTAssertFalse(WidgetBackgroundRefresh.shouldSubmit(earliest: now, pending: pending))

        pending.earliestBeginDate = now.addingTimeInterval(60)
        XCTAssertTrue(WidgetBackgroundRefresh.shouldSubmit(earliest: now, pending: pending))
        XCTAssertFalse(WidgetBackgroundRefresh.shouldSubmit(earliest: now.addingTimeInterval(60), pending: pending))
        XCTAssertFalse(WidgetBackgroundRefresh.shouldSubmit(earliest: now.addingTimeInterval(900), pending: pending))
        XCTAssertTrue(WidgetBackgroundRefresh.shouldSubmit(earliest: now.addingTimeInterval(1_800), pending: pending, replaceExisting: true))
        XCTAssertFalse(WidgetBackgroundRefresh.shouldSubmit(earliest: now.addingTimeInterval(90), pending: pending, replaceExisting: true))
    }

    func testWidgetRefreshIntervalsAreSharedByAllEntryPoints() {
        XCTAssertEqual(WidgetSyncSource.quotes.interval, 1800)
        XCTAssertEqual(WidgetSyncSource.history.interval, 14400)
        XCTAssertEqual(WidgetSyncSource.skills.interval, 1800)
        XCTAssertEqual(WidgetSyncSource.industry.interval, 1800)
        XCTAssertEqual(WidgetSyncSource.planets.interval, 3600)
    }

    func testWidgetImageStoreWritesReadsAndPrunesByKind() {
        let portraitID1 = 990_001
        let portraitID2 = 990_002
        let typeID = 990_003
        defer {
            WidgetImageStore.prune(.portrait, keeping: [])
            WidgetImageStore.prune(.type, keeping: [])
        }

        let portraitData = Data([0x01, 0x02, 0x03])
        let typeData = Data([0x04, 0x05])
        WidgetImageStore.write(portraitData, kind: .portrait, id: portraitID1)
        WidgetImageStore.write(portraitData, kind: .portrait, id: portraitID2)
        WidgetImageStore.write(typeData, kind: .type, id: typeID)

        XCTAssertTrue(WidgetImageStore.exists(.portrait, id: portraitID1))
        XCTAssertEqual(WidgetImageStore.read(.portrait, id: portraitID1), portraitData)
        XCTAssertEqual(WidgetImageStore.read(.type, id: typeID), typeData)

        WidgetImageStore.prune(.portrait, keeping: [portraitID1])
        XCTAssertTrue(WidgetImageStore.exists(.portrait, id: portraitID1))
        XCTAssertFalse(WidgetImageStore.exists(.portrait, id: portraitID2))
        XCTAssertTrue(WidgetImageStore.exists(.type, id: typeID))
    }

    func testSkillProgressIntervalRejectsExtremeDurations() {
        let start = Date(timeIntervalSince1970: 200_000)
        let normal = WidgetSkill(
            typeID: 3449, name: "Navigation", level: 4,
            start: start, finish: start.addingTimeInterval(3_600),
            trainingStartSP: 250, levelStartSP: 0, levelEndSP: 1_000
        )
        XCTAssertEqual(normal.progressInterval, start.addingTimeInterval(-1_200)...start.addingTimeInterval(3_600))

        let nearComplete = WidgetSkill(
            typeID: 3449, name: "Navigation", level: 5,
            start: start, finish: start.addingTimeInterval(3_600),
            trainingStartSP: 999_999_999, levelStartSP: 0, levelEndSP: 1_000_000_000
        )
        XCTAssertNil(nearComplete.progressInterval)
    }

    func testContentLinksKeepRowContextAndDoNotMatchSettings() throws {
        let routes: [WidgetContentRoute] = [.market(44992), .skills(100), .planets(200), .industry(300), .industry(nil)]
        for route in routes {
            XCTAssertEqual(WidgetContentRoute(url: route.url), route)
            XCTAssertNil(NexusWidgetKind(settingsURL: route.url))
        }
        XCTAssertNil(WidgetContentRoute(url: NexusWidgetKind.skills.settingsURL))
        XCTAssertNil(WidgetContentRoute(url: try XCTUnwrap(URL(string: "evenexus://widgets/open/unknown/100"))))
    }

    func testSyncTimeUsesEachWidgetsSelectedData() {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = old.addingTimeInterval(60)
        let snapshot = WidgetSnapshot(
            market: [.init(id: 34, name: "Tritanium", quotedAt: old, historyAt: recent)],
            characters: [
                .init(id: 1, name: "One", skillsAt: old, jobsAt: recent),
                .init(id: 2, name: "Two", skillsAt: recent, planetsAt: old),
            ]
        )
        XCTAssertEqual(snapshot.lastSync(for: .market, rowLimit: 1), old)
        XCTAssertEqual(snapshot.lastSync(for: .skills, rowLimit: 1), old)
        XCTAssertEqual(snapshot.lastSync(for: .industryOverview, rowLimit: 3), recent)
        let selected = snapshot.selection(for: .industryList, rowLimit: 3, marketWatchlist: [], characterIDs: [2])
        XCTAssertNil(selected.lastSync(for: .industryList, rowLimit: 3))
    }

    func testSkillQueueRefreshesAtCompletionAndThenUsesTheNewSyncTime() {
        let syncedAt = Date(timeIntervalSince1970: 1_000)
        let finish = syncedAt.addingTimeInterval(120)
        let skill = SkillQueueItem(
            queue_position: 0, skill_id: 1, finished_level: 3,
            training_start_sp: nil, level_end_sp: nil, level_start_sp: nil,
            start_date: syncedAt, finish_date: finish
        )
        let sample = CharacterSkillQueueSample(queue: [skill], fetchedAt: syncedAt, names: [:])
        let interval = WidgetSyncSource.skills.interval
        XCTAssertFalse(sample.needsRefresh(at: finish.addingTimeInterval(-1), maxAge: interval, afterSkillFinishes: true))
        XCTAssertTrue(sample.needsRefresh(at: finish, maxAge: interval, afterSkillFinishes: true))
        XCTAssertFalse(sample.needsRefresh(at: finish, maxAge: interval))

        let refreshed = CharacterSkillQueueSample(queue: [skill], fetchedAt: finish, names: [:])
        XCTAssertFalse(refreshed.needsRefresh(at: finish, maxAge: interval, afterSkillFinishes: true))
        XCTAssertTrue(refreshed.needsRefresh(at: finish.addingTimeInterval(interval), maxAge: interval))
    }

    func testTrainingProgressContinuesFromSkillPointsAtStart() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let finish = start.addingTimeInterval(150)
        let skill = WidgetSkill(
            typeID: 1, name: nil, level: 3, start: start, finish: finish,
            trainingStartSP: 50, levelStartSP: 25, levelEndSP: 125
        )
        XCTAssertEqual(skill.initialProgress, 0.25)
        let interval = try XCTUnwrap(skill.progressInterval)
        XCTAssertEqual(interval.lowerBound, start.addingTimeInterval(-50))
        XCTAssertEqual(interval.upperBound, finish)
        XCTAssertEqual(skill.progress(at: start), 0.25)
        XCTAssertEqual(skill.progress(at: start.addingTimeInterval(50)), 0.5)
    }

    func testPausedIndustryProgressDoesNotAdvanceWithTimeline() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(3_600)
        let pause = start.addingTimeInterval(900)
        let job = WidgetIndustryJob(
            id: 1, typeID: 2, name: nil, activity: .manufacturing, status: .paused,
            end: end, start: start, duration: 3_600, pausedAt: pause
        )
        XCTAssertNil(job.activeProgressInterval)
        XCTAssertEqual(job.progress(at: pause), 0.25)
        XCTAssertEqual(job.progress(at: end), 0.25)
    }

    func testActiveIndustryProgressUsesCachedDatesWithoutDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(3_600)
        let job = WidgetIndustryJob(id: 1, typeID: 2, activity: .copying, status: .active, end: end, start: start)

        XCTAssertEqual(job.activeProgressInterval, start...end)
        XCTAssertEqual(job.progress(at: start.addingTimeInterval(1_800)), 0.5)
        XCTAssertFalse(job.isReady(at: end.addingTimeInterval(-1)))
        XCTAssertTrue(job.isReady(at: end))
        XCTAssertEqual(job.progress(at: end), 1)
    }

    func testPlanetCyclePrioritizesExpiredExtractorOverStillRunningExtractor() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let expired = DateInterval(start: now.addingTimeInterval(-7_200), end: now.addingTimeInterval(-600))
        let running = DateInterval(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(3_600))
        let planet = WidgetPlanet(
            id: 1, name: "Planet", planetType: "temperate",
            hasExtractor: true, cycles: [expired, running]
        )

        let chosen = try XCTUnwrap(planet.cycle(at: now))
        XCTAssertEqual(chosen, expired)
        XCTAssertGreaterThanOrEqual(now, chosen.end)
        XCTAssertEqual(planet.iconAsset, "Planet_temperate")
    }

    func testWidgetStringsAndUnitsFollowTheSelectedInterfaceLanguage() throws {
        let defaults = try XCTUnwrap(WidgetMarketWatchlist.defaults)
        let key = WidgetLocalization.languageKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }

        for (language, navigationName) in [
            ("en", "Navigation"), ("zh-Hans", "导航学"), ("ru", "Основы пилотажа")
        ] {
            defaults.set(language, forKey: key)
            XCTAssertEqual(WidgetLocalization.locale.identifier, language)
            XCTAssertEqual(WidgetLocalization.bundle.bundleURL.lastPathComponent, "\(language).lproj")
            XCTAssertNotEqual(NexusWidgetKind.skills.title, "Widget_Skills")
            XCTAssertEqual(WidgetLocalization.previewTypeName(3449), navigationName)
            XCTAssertFalse(CompactDuration.format(70).contains("Time_Compact"))
            if language == "zh-Hans" {
                XCTAssertEqual(CompactDuration.format(70), "1分10秒")
            }
            XCTAssertFalse(IndustryJobQuantity.description(runs: 2, isCopying: true, licensedRuns: 3)
                .contains("Industry_Runs"))
        }
    }

    func testVersion115StringsArePresentInEverySupportedLanguage() throws {
        let keys = [
            "Assets_Filter_Active_Systems_Format", "Assets_Filter_Systems",
            "Assets_Group_By_Region", "Assets_Group_By_Region_Description",
            "Item_Attribute_Description_Format", "Main_Attribute_Compare_Layout",
            "Main_Attribute_Compare_Layout_Horizontal", "Main_Attribute_Compare_Layout_Tiled",
            "Main_Attribute_Compare_Layout_Vertical", "Main_Market_History_Load_Failed",
            "Main_Skills_Plan_Calculation_Unavailable", "Main_Skills_Plan_Name_Duplicate",
            "Main_Skills_Plan_Name_Required", "%@%@, %@: %@",
            "Assets_Filter_Active_Item_Count_Format", "Assets_Filter_Title", "Assets_Pin", "Assets_Unknown_Region",
            "Fitting_All_Skills_Count", "Main_Attribute_Compare", "Main_Database_Loading", "Main_Market_Avg_Price",
            "Main_Market_Insufficient_Stock", "Main_Market_Jita_Price_Label", "Main_Market_No_Orders",
            "Main_Market_Total_Price", "Main_Market_Transactions_Buy", "Main_Market_Transactions_Sell",
            "Main_Market_Watch_List_Quantity_Field_Placeholder", "Main_Skills_Plan_Name", "Mastery_Plan_Skills_Count",
            "Misc_Done", "MultiCharacter_Select_All", "Ore_Refinery_Result_Avg_Price",
            "Security_HighSec", "Security_LowSec", "Security_NullSec",
        ]
        for language in ["en", "zh-Hans", "ru"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
            let bundle = try XCTUnwrap(Bundle(url: url))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: "Localizable")
                XCTAssertNotEqual(value, "MISSING", "\(language): \(key)")
                XCTAssertFalse(value.isEmpty, "\(language): \(key)")
            }
            for key in ["Industry_Runs_Format", "Industry_Runs_With_Copies_Format"] {
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: "IndustryJobQuantity")
                XCTAssertNotEqual(value, "MISSING", "\(language): \(key)")
            }
        }
    }

    func testCurrencyUnitStyleFormatsThePreviewAndAmounts() {
        let chinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(CurrencyUnitStyle.localized.format(150_000_000, locale: chinese), "1.5亿")
        XCTAssertEqual(CurrencyUnitStyle.english.format(150_000_000, locale: chinese), "150M")
        XCTAssertEqual(CurrencyUnitStyle.english.format(-1_500_000_000, locale: chinese), "-1.5B")
    }

    func testIndustryJobQuantityEnglishCopyingOrderAndNoDanglingMultiplier() throws {
        let defaults = try XCTUnwrap(WidgetMarketWatchlist.defaults)
        let key = WidgetLocalization.languageKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }

        defaults.set("en", forKey: key)
        XCTAssertEqual(IndustryJobQuantity.description(runs: 5, isCopying: false, licensedRuns: nil), "5 runs")
        XCTAssertEqual(IndustryJobQuantity.description(runs: 2, isCopying: true, licensedRuns: 10), "2 copies × 10 runs")

        defaults.set("zh-Hans", forKey: key)
        XCTAssertEqual(IndustryJobQuantity.description(runs: 5, isCopying: false, licensedRuns: nil), "5流程")
        XCTAssertEqual(IndustryJobQuantity.description(runs: 2, isCopying: true, licensedRuns: 10), "2张 × 10 流程/张")
    }

}
