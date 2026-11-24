import SwiftUI
import WidgetKit

@main
struct NexusWidgets: WidgetBundle {
    var body: some Widget {
        MarketWidget()
        SkillsWidget()
        PlanetsWidget()
        IndustryOverviewWidget()
        IndustryListWidget()
    }
}

private struct MarketWidget: NexusWidget {
    static let kind = NexusWidgetKind.market
}

private struct SkillsWidget: NexusWidget {
    static let kind = NexusWidgetKind.skills
}

private struct PlanetsWidget: NexusWidget {
    static let kind = NexusWidgetKind.planets
}

private struct IndustryOverviewWidget: NexusWidget {
    static let kind = NexusWidgetKind.industryOverview
}

private struct IndustryListWidget: NexusWidget {
    static let kind = NexusWidgetKind.industryList
}

private protocol NexusWidget: Widget {
    static var kind: NexusWidgetKind { get }
}

private extension NexusWidget {
    var kind: NexusWidgetKind { Self.kind }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind.rawValue, provider: NexusWidgetProvider(kind: kind)) { entry in
            NexusWidgetView(kind: kind, entry: entry)
                .environment(\.locale, WidgetLocalization.locale)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName(kind.title)
        .description(description)
        .supportedFamilies(kind.supportedFamilies)
    }

    private var description: String {
        switch kind {
        case .market: String(localized: "Widget_Market_Description", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .skills: String(localized: "Widget_Skills_Description", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .planets: String(localized: "Widget_Planets_Description", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .industryOverview: String(localized: "Widget_Overview_Description", table: "Widgets", bundle: WidgetLocalization.bundle)
        case .industryList: String(localized: "Widget_Industry_List_Description", table: "Widgets", bundle: WidgetLocalization.bundle)
        }
    }
}

struct NexusWidgetProvider: TimelineProvider {
    let kind: NexusWidgetKind

    func placeholder(in context: Context) -> NexusWidgetEntry {
        let now = Date()
        return NexusWidgetEntry(date: now, snapshot: .preview(at: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (NexusWidgetEntry) -> Void) {
        let now = Date()
        let snapshot = context.isPreview ? WidgetSnapshot.preview(at: now) : selectedSnapshot(in: context)
        completion(NexusWidgetEntry(
            date: now, snapshot: snapshot, marketTrendColors: kind == .market ? .current : .defaultStyle
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NexusWidgetEntry>) -> Void) {
        let rowLimit = context.family.nexusRowLimit
        Task {
            await WidgetRepository.shared.refresh(kind: kind, rowLimit: rowLimit)
            let now = Date()
            let snapshot = WidgetPresentation.load(kind: kind, rowLimit: rowLimit)
            let entries = WidgetTimelinePlan.dates(in: snapshot, kind: kind, rowLimit: rowLimit, at: now).map {
                NexusWidgetEntry(
                    date: $0, snapshot: snapshot,
                    marketTrendColors: kind == .market ? .current : .defaultStyle
                )
            }
            let reload = WidgetTimelinePlan.reloadDate(in: snapshot, kind: kind, rowLimit: rowLimit, at: now)
            completion(Timeline(entries: entries, policy: .after(reload)))
        }
    }

    private func selectedSnapshot(in context: Context) -> WidgetSnapshot? {
        WidgetPresentation.load(kind: kind, rowLimit: context.family.nexusRowLimit)
    }
}

private extension WidgetSnapshot {
    static func preview(at date: Date) -> Self {
        let syncDate = date.addingTimeInterval(-8 * 60)
        let prices = [6_720_000.0, 905_000_000, 456_000_000, 520_000_000, 62_000_000, 4.75, 12.8, 53, 259]
        let market = zip(WidgetChoice.defaultMarket, prices).enumerated().map { index, item in
            let (choice, price) = item
            let history = (0..<90).map { day in
                let position = Double(day) / 89
                let direction = index.isMultiple(of: 3) ? -1.0 : 1.0
                let wave = sin(Double(day) * 0.28 + Double(index)) * 0.026
                    + sin(Double(day) * 0.79 + Double(index)) * 0.009
                return WidgetMarketPoint(
                    date: date.addingTimeInterval(Double(day - 90) * 86_400),
                    average: price * (0.94 + direction * position * 0.14 + wave)
                )
            }
            return WidgetMarketItem(id: choice.id, name: choice.name, price: price, quotedAt: syncDate, history: history)
        }

        let rows = [
            ("Tess Ardan", 3449, 16227),
            ("Niko Vale", 3380, 621),
            ("Hana Sato", 3406, 24699),
            ("Mira Vos", 3327, 620),
            ("Sera Torin", 3436, 32880),
            ("Ren Ada", 3412, 691),
            ("Idris Sol", 3402, 583),
            ("Ava Renn", 3411, 16238),
            ("Juno Kel", 3300, 11994),
        ]
        let planetNameFormat = String(localized: "Widget_Preview_Planet_Format", table: "Widgets", bundle: WidgetLocalization.bundle)
        let characters = rows.enumerated().map { index, row in
            let (characterName, skillID, blueprintID) = row
            let start = date.addingTimeInterval(-4 * 3600)
            let finish = date.addingTimeInterval(Double(index + 1) * 3600)
            let skill = WidgetSkill(
                typeID: skillID, name: WidgetLocalization.previewTypeName(skillID), level: 4,
                start: index == 1 ? nil : start, finish: index == 1 ? nil : finish,
                trainingStartSP: 250, levelStartSP: 0, levelEndSP: 1000
            )
            let previewPlanetTypes = ["temperate", "barren", "oceanic", "gas", "ice", "lava"]
            let planets = (0..<6 - index % 3).map { planetIndex in
                WidgetPlanet(
                    id: planetIndex, name: String(format: planetNameFormat, planetIndex + 1),
                    planetType: previewPlanetTypes[(index + planetIndex) % previewPlanetTypes.count],
                    hasExtractor: planetIndex != 1,
                    cycles: planetIndex == 1 ? [] : [DateInterval(
                        start: start, end: date.addingTimeInterval(Double(planetIndex + 1) * 1800)
                    )]
                )
            }
            let activity: WidgetIndustryActivity = index.isMultiple(of: 3) ? .materialResearch
                : (index.isMultiple(of: 2) ? .reaction : .manufacturing)
            let job = WidgetIndustryJob(
                id: index, typeID: blueprintID, name: WidgetLocalization.previewTypeName(blueprintID), activity: activity,
                status: index < 2 ? .ready : .active, end: finish,
                start: start, duration: finish.timeIntervalSince(start), runs: index + 1
            )
            return WidgetCharacter(
                id: index, name: characterName, skills: [skill], planets: planets, jobs: [job],
                skillsAt: syncDate, planetsAt: syncDate, jobsAt: syncDate
            )
        }
        return WidgetSnapshot(market: market, characters: characters)
    }
}
