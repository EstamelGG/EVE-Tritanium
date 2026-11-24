@testable import EVE_Nexus
import Foundation
import Security
import SwiftUI
import WidgetKit
import XCTest

final class WidgetRefreshDesignTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testExtractorProgressAndWarningBoundaries() throws {
        let cycle = DateInterval(start: now, duration: 1000)
        let planet = WidgetPlanet(id: 1, hasExtractor: true, cycles: [cycle])
        XCTAssertEqual(planet.extractorProgress(at: now.addingTimeInterval(-1)), 0)
        XCTAssertEqual(planet.extractorProgress(at: now.addingTimeInterval(900)), 0.9)
        XCTAssertEqual(planet.extractorProgress(at: cycle.end), 1)
        XCTAssertEqual(planet.extractorProgress(at: cycle.end.addingTimeInterval(10)), 1)
        XCTAssertEqual(WidgetPlanet(id: 2, hasExtractor: true, cycles: []).extractorProgress(at: now), 1)
        XCTAssertNil(WidgetPlanet(id: 3, hasExtractor: false, cycles: []).extractorProgress(at: now))
        XCTAssertEqual(PlanetaryExtractorProgressColors.fill(isExpired: false, remainingFraction: 0.11),
                       PlanetaryExtractorProgressColors.fill(isExpired: false))
        XCTAssertEqual(PlanetaryExtractorProgressColors.fill(isExpired: false, remainingFraction: 0.1), .orange)
        XCTAssertEqual(PlanetaryExtractorProgressColors.fill(isExpired: true, remainingFraction: 0), .red)
    }

    func testPlanetTimelineIncludesWarningAndStopWithoutWaitingForNetwork() {
        let cycle = DateInterval(start: now, duration: 608)
        let planet = WidgetPlanet(id: 1, hasExtractor: true, cycles: [cycle])
        let snapshot = WidgetSnapshot(characters: [.init(id: 1, name: "Fixture", planets: [planet], planetsAt: now)])
        let dates = WidgetTimelinePlan.dates(in: snapshot, kind: .planets, rowLimit: 3, at: now)
        XCTAssertTrue(dates.contains(now.addingTimeInterval(300)))
        XCTAssertTrue(dates.contains(cycle.start.addingTimeInterval(cycle.duration * 0.9)))
        XCTAssertTrue(dates.contains(cycle.end))
        XCTAssertEqual(dates.last, cycle.end)
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
    }

    func testCompactWidgetCountdownUsesAtMostTwoUnitsWithoutSeconds() {
        let chinese = Locale(identifier: "zh-Hans")
        let cases: [(TimeInterval, String)] = [
            (-1, "0分"), (0, "0分"), (1, "1分"), (60, "1分"),
            (61, "2分"), (5400, "1时30分"), (183_600, "2天3时"),
            (86399, "1天0时"), (.infinity, "0分"),
        ]
        for (seconds, expected) in cases {
            XCTAssertEqual(
                CompactDuration.format(seconds, rounding: .ceil, showsSeconds: false, locale: chinese),
                expected
            )
        }
        XCTAssertEqual(CompactDuration.format(5400, showsSeconds: false, locale: Locale(identifier: "en")), "1h 30m")
        XCTAssertEqual(CompactDuration.format(183_600, showsSeconds: false, locale: Locale(identifier: "ru")), "2д 3ч")
        XCTAssertEqual(CompactDuration.format(70, locale: chinese), "1分10秒")
    }

    func testLocalTimelineAdvancesCountdownAndProgressAndIsBounded() throws {
        let end = now.addingTimeInterval(5400)
        let job = WidgetIndustryJob(
            id: 1,
            typeID: 2,
            activity: .manufacturing,
            status: .active,
            end: end,
            start: now.addingTimeInterval(-5400)
        )
        let snapshot = WidgetSnapshot(characters: [.init(id: 1, name: "Preview", jobs: [job], jobsAt: now)])
        let dates = WidgetTimelinePlan.dates(in: snapshot, kind: .industryList, rowLimit: 3, at: now)
        XCTAssertEqual(dates.count, WidgetTimelinePlan.maximumEntries)
        XCTAssertEqual(dates[1], now.addingTimeInterval(60))
        XCTAssertGreaterThan(job.progress(at: dates[1]), job.progress(at: dates[0]))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
        XCTAssertLessThan(
            WidgetTimelinePlan.reloadDate(in: snapshot, kind: .industryList, rowLimit: 3, at: now),
            try XCTUnwrap(dates.last)
        )
    }

    private func store() throws -> WidgetStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return WidgetStore(directory: directory)
    }

    func testTimelineMovesFromSoonToReadyWithoutNetworkAndNeverEarly() throws {
        let end = now.addingTimeInterval(8 * 3600 + 71)
        let job = WidgetIndustryJob(id: 1, typeID: 2, activity: .manufacturing, status: .active, end: end)
        let snapshot = WidgetSnapshot(characters: [.init(id: 1, name: "Preview", jobs: [job], jobsAt: now)])
        let dates = WidgetTimelinePlan.dates(in: snapshot, kind: .industryOverview, rowLimit: 3, at: now)
        XCTAssertEqual(dates.first, now)
        let soon = try XCTUnwrap(dates.first { job.isSoon(at: $0) })
        let ready = try XCTUnwrap(dates.first { job.isReady(at: $0) })
        XCTAssertGreaterThanOrEqual(soon, end.addingTimeInterval(-WidgetIndustryJob.soonInterval))
        XCTAssertGreaterThanOrEqual(ready, end)
        XCTAssertLessThan(ready.timeIntervalSince(end), 300)
        XCTAssertTrue(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 300 })
    }

    func testTimelineIsBoundedAndSchedulesAnotherCheckEvenWithNoEvents() throws {
        let jobs = (0 ..< 200).map {
            WidgetIndustryJob(
                id: $0,
                typeID: 2,
                activity: .manufacturing,
                status: .active,
                end: now.addingTimeInterval(Double($0 + 1) * 600)
            )
        }
        let snapshot = WidgetSnapshot(characters: [.init(id: 1, name: "Preview", jobs: jobs, jobsAt: now)])
        let dates = WidgetTimelinePlan.dates(in: snapshot, kind: .industryOverview, rowLimit: 3, at: now)
        XCTAssertLessThanOrEqual(dates.count, WidgetTimelinePlan.maximumEntries)
        XCTAssertLessThanOrEqual(try XCTUnwrap(dates.last), now.addingTimeInterval(24 * 3600))
        let reload = WidgetTimelinePlan.reloadDate(in: WidgetSnapshot(), kind: .market, rowLimit: 3, at: now)
        XCTAssertGreaterThan(reload, now)
        XCTAssertLessThanOrEqual(reload, now.addingTimeInterval(3600))
    }

    func testResourceStoreRejectsOlderWritesAndDoesNotResurrectRemovedAccounts() async throws {
        let store = try store()
        try store.saveCatalog(.init(accounts: [.init(id: 1, name: "Local name", needsLogin: false)]))
        let first = try await store.accept(.industry([]), id: 1, at: now)
        let old = try await store.accept(.industry([]), id: 1, at: now.addingTimeInterval(-60))
        XCTAssertTrue(first)
        XCTAssertFalse(old)
        XCTAssertEqual(store.snapshot().characters[0].jobsAt, now)
        XCTAssertEqual(store.snapshot().characters[0].name, "Local name")
        try store.saveCatalog(.init())
        XCTAssertTrue(store.snapshot().characters.isEmpty)
        let afterRemoval = try await store.accept(.industry([]), id: 1, at: now.addingTimeInterval(60))
        XCTAssertFalse(afterRemoval, "A response that outlives logout must not repopulate the resource")
    }

    func testIndependentResourcesShareOneStoreWithoutOverwritingEachOther() async throws {
        let store = try store()
        try store.saveCatalog(.init(
            accounts: [.init(id: 1, name: "Fixture", needsLogin: false)],
            typeNames: [3449: "导航学"]
        ))
        let queue = CharacterSkillQueueSample(
            queue: [.init(
                queue_position: 0,
                skill_id: 3449,
                finished_level: 4,
                training_start_sp: nil,
                level_end_sp: nil,
                level_start_sp: nil,
                start_date: now,
                finish_date: now.addingTimeInterval(600)
            )],
            fetchedAt: now,
            names: [3449: "Navigation"]
        )
        async let skills = store.accept(.skills(queue), id: 1, at: now)
        async let industry = store.accept(.industry([]), id: 1, at: now)
        _ = try await (skills, industry)
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.characters[0].skills?.first?.name, "导航学")
        XCTAssertEqual(snapshot.characters[0].jobs, [])
        XCTAssertEqual(store.skillQueue(for: 1), queue)
        let limited = store.snapshot(kind: .skills, rowLimit: 1)
        XCTAssertTrue(limited.market.isEmpty)
        XCTAssertNil(limited.characters[0].jobs, "A skill widget must not read unrelated resources")
        let empty = CharacterSkillQueueSample(queue: [], fetchedAt: now.addingTimeInterval(60), names: [:])
        _ = try await store.accept(.skills(empty), id: 1, at: empty.fetchedAt)
        XCTAssertEqual(store.snapshot().characters[0].skills, [])
        XCTAssertEqual(store.snapshot().characters[0].jobs, [])
    }

    func testFreshSkillQueueIsUsedWithoutNetwork() async throws {
        let store = try store()
        let sample = CharacterSkillQueueSample(queue: [], fetchedAt: Date(), names: [:])
        try store.saveCatalog(.init(accounts: [.init(id: 1, name: "Fixture", needsLogin: false)]))
        _ = try await store.accept(.skills(sample), id: 1, at: sample.fetchedAt)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetFixtureProtocol.self]
        WidgetFixtureProtocol.configure(failSecondPage: false)
        let repository = WidgetRepository(session: URLSession(configuration: configuration), store: store)
        let read = try await repository.skillQueue(for: 1, maxAge: 1800, force: false, afterCompletion: false)
        XCTAssertEqual(read, sample)
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 0)
    }

    func testClearingSamplesPreservesAccountAndDisplayMetadata() async throws {
        let store = try store()
        let catalog = WidgetCatalog(
            accounts: [.init(id: 1, name: "Fixture", needsLogin: false)],
            typeNames: [3449: "导航学"]
        )
        try store.saveCatalog(catalog)
        _ = try await store.accept(.industry([]), id: 1, at: now)
        try FileManager.default.removeItem(at: XCTUnwrap(store.samplesDirectory))
        XCTAssertEqual(store.catalog, catalog)
        XCTAssertEqual(store.snapshot().characters.map(\.id), [1])
        XCTAssertNil(store.snapshot().characters[0].jobsAt)
    }

    func testExplicitChecksCanPrecedeAutomaticIntervalButHonorServerCooldown() {
        let target = WidgetResource(source: .industry, id: 1)
        let cached = WidgetRecord(fetchedAt: now.addingTimeInterval(-600), attemptedAt: now, retryAfter: now)
        XCTAssertFalse(target.isDue(at: now, record: cached, force: false))
        XCTAssertTrue(target.isDue(at: now, record: cached, force: true))
        let cooldown = WidgetRecord(attemptedAt: now, retryAfter: now.addingTimeInterval(120))
        XCTAssertFalse(target.isDue(at: now, record: cooldown, force: true))
    }

    func testMissingCharactersPreserveLastSuccessfulIndustrySyncTime() {
        let snapshot = WidgetSnapshot(characters: [
            .init(id: 1, name: "A", jobs: [], jobsAt: now),
            .init(id: 2, name: "B"),
        ])
        XCTAssertEqual(snapshot.lastSync(for: .industryOverview, rowLimit: 3), now)
    }

    func testNewSuccessClearsStoredFailure() async throws {
        let store = try store()
        try store.saveCatalog(.init(accounts: [.init(id: 1, name: "Fixture", needsLogin: false)]))
        let target = WidgetResource(source: .industry, id: 1)
        try store.write(.init(attemptedAt: now, retryAfter: now, failure: .unavailable), for: target)
        _ = try await store.accept(.industry([]), id: 1, at: now.addingTimeInterval(60))
        XCTAssertNil(store.read(target)?.failure)
    }

    func testNativeOAuthFormEscapesReservedCharactersAndExpiredTokenCannotBeReused() {
        let data = WidgetAuthorization.form(["refresh_token": "a+b&c=d%", "client_id": "native"])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "client_id=native&refresh_token=a%2Bb%26c%3Dd%25")
        let credential = WidgetCredential(
            refreshToken: "fixture",
            accessToken: "fixture",
            expiresAt: now.addingTimeInterval(30),
            clientID: "native"
        )
        XCTAssertNil(credential.usableAccessToken(at: now))
    }

    func testConcurrentMarketRefreshesReuseCompletedRequest() async throws {
        let store = try store()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetFixtureProtocol.self]
        WidgetFixtureProtocol.configure(failSecondPage: false)
        let item = WidgetMarketItem(id: 990_091, name: "Fixture", historyAt: Date())
        try store.write(
            .init(value: .history([]), fetchedAt: Date(), attemptedAt: Date(), retryAfter: Date()),
            for: .init(source: .history, id: item.id)
        )
        let refresher = WidgetRepository(
            session: URLSession(configuration: configuration),
            store: store,
            snapshotLoader: { _, _ in
                WidgetSnapshot(market: [item])
            }
        )
        let otherProcess = WidgetRepository(
            session: URLSession(configuration: configuration),
            store: store,
            snapshotLoader: { _, _ in
                WidgetSnapshot(market: [item])
            }
        )
        async let first: Void = refresher.refresh(kind: .market, rowLimit: 3)
        async let second: Void = otherProcess.refresh(kind: .market, rowLimit: 3)
        _ = await (first, second)
        let target = WidgetResource(source: .quotes, id: item.id)
        XCTAssertEqual(store.read(target)?.value, .quote(12))
        XCTAssertNil(store.read(target)?.failure)
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 2, "Two pages, fetched once despite two callers")
    }

    func testFailedMarketPagePreservesLastCompleteQuoteAndTimestamp() async throws {
        let store = try store()
        let old = Date().addingTimeInterval(-7200)
        let item = WidgetMarketItem(id: 990_092, name: "Fixture", price: 42, quotedAt: old, historyAt: Date())
        let target = WidgetResource(source: .quotes, id: item.id)
        try store.write(.init(value: .quote(42), fetchedAt: old, attemptedAt: old, retryAfter: old), for: target)
        try store.write(
            .init(value: .history([]), fetchedAt: Date(), attemptedAt: Date(), retryAfter: Date()),
            for: .init(source: .history, id: item.id)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetFixtureProtocol.self]
        WidgetFixtureProtocol.configure(failSecondPage: true)
        let refresher = WidgetRepository(
            session: URLSession(configuration: configuration),
            store: store,
            snapshotLoader: { _, _ in
                WidgetSnapshot(market: [item])
            }
        )
        await refresher.refresh(kind: .market, rowLimit: 3)
        XCTAssertEqual(store.read(target)?.value, .quote(42))
        XCTAssertEqual(store.read(target)?.fetchedAt, old)
        XCTAssertEqual(store.read(target)?.failure, .unavailable)
    }

    func testSeparateAuthorizationClientsRotateOnceAndHonorRevocation() async throws {
        let id = 990_095
        addTeardownBlock {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "EVE.WidgetAuthorization",
                kSecAttrAccount as String: String(id),
                kSecAttrAccessGroup as String: WidgetStore.appGroup,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary)
        }
        WidgetFixtureProtocol.configure(failSecondPage: false)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetFixtureProtocol.self]
        let first = WidgetAuthorization(session: URLSession(configuration: configuration))
        let second = WidgetAuthorization(session: URLSession(configuration: configuration))
        let legacy = WidgetCredential(refreshToken: "fixture-old", clientID: "fixture-client")
        try await first.install(legacy, id: id)
        async let a = first.accessToken(for: id)
        async let b = second.accessToken(for: id)
        let tokens = try await (a, b)
        XCTAssertEqual(tokens.0, "fixture-access")
        XCTAssertEqual(tokens.1, "fixture-access")
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 1)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "fixture-rotated")
        try await first.revoke(id)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "")
        do {
            _ = try await second.accessToken(for: id)
            XCTFail("Revoked credentials must not be refreshed")
        } catch WidgetAuthorizationError.needsLogin {}
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 1)
    }

    private func privateCredential(_ id: Int, data: Data = Data("fixture-private".utf8)) throws {
        WidgetCredentialStore.removePrivateToken(id)
        try WidgetCredentialStore.remove(id)
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "token_\(id)",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ] as CFDictionary, nil)
        XCTAssertEqual(status, errSecSuccess)
        addTeardownBlock {
            WidgetCredentialStore.removePrivateToken(id)
            try? WidgetCredentialStore.remove(id)
        }
    }

    private func fixtureAuthorization(status: Int = 200) -> WidgetAuthorization {
        WidgetFixtureProtocol.configure(failSecondPage: false, oauthStatus: status)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetFixtureProtocol.self]
        return WidgetAuthorization(session: URLSession(configuration: configuration))
    }

    @MainActor
    private func flaggedAccount(_ id: Int, expired: Bool) throws {
        let defaults = UserDefaults.standard
        let previousAccounts = defaults.data(forKey: "EVECharacters")
        let previousOrder = defaults.array(forKey: "EVECharacterOrder") as? [Int]
        var character = EVECharacterInfo(
            CharacterID: id,
            CharacterName: "Migration fixture",
            ExpiresOn: "",
            Scopes: "",
            TokenType: "Bearer",
            CharacterOwnerHash: "fixture"
        )
        character.refreshTokenExpired = expired
        let account = CharacterAuth(character: character, addedDate: now, lastTokenUpdateTime: now)
        try defaults.set(JSONEncoder().encode([account]), forKey: "EVECharacters")
        defaults.set([id], forKey: "EVECharacterOrder")
        addTeardownBlock {
            await MainActor.run {
                UserDefaults.standard.set(previousAccounts, forKey: "EVECharacters")
                UserDefaults.standard.set(previousOrder, forKey: "EVECharacterOrder")
                WidgetRefreshService.shared.reconcileCharacters()
            }
        }
    }

    func testConcurrentMigrationCopiesOnceAndRemovesPrivateCopy() async throws {
        let id = 990_101
        try privateCredential(id)
        let first = fixtureAuthorization()
        let second = WidgetAuthorization()
        async let a = first.prepareExistingCredential(for: id, clientID: "fixture-client")
        async let b = second.prepareExistingCredential(for: id, clientID: "fixture-client")
        let result = try await (a, b)
        XCTAssertTrue(result.0 && result.1)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "fixture-private")
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.clientID, "fixture-client")
        XCTAssertNil(try WidgetCredentialStore.privateToken(id))
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 0)
    }

    func testMigrationNeverOverwritesARotatedSharedCredential() async throws {
        let id = 990_102
        try privateCredential(id)
        let authorization = fixtureAuthorization()
        try await authorization.install(.init(refreshToken: "fixture-newer", clientID: "fixture-client"), id: id)
        let available = try await authorization.prepareExistingCredential(for: id, clientID: "fixture-client")
        XCTAssertTrue(available)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "fixture-newer")
        XCTAssertNil(try WidgetCredentialStore.privateToken(id))
    }

    func testUnreadableDestinationLeavesThePrivateCredentialIntact() async throws {
        let id = 990_108
        try privateCredential(id)
        XCTAssertEqual(SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "EVE.WidgetAuthorization",
            kSecAttrAccount as String: String(id),
            kSecAttrAccessGroup as String: WidgetStore.appGroup,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: Data("not a credential".utf8),
        ] as CFDictionary, nil), errSecSuccess)
        do {
            _ = try await fixtureAuthorization().prepareExistingCredential(for: id, clientID: "fixture-client")
            XCTFail("An unreadable destination must not be treated as a missing credential")
        } catch is DecodingError {}
        XCTAssertEqual(try WidgetCredentialStore.privateToken(id), "fixture-private")
    }

    func testExplicitRevocationBlocksMigrationOfAResidualPrivateToken() async throws {
        let id = 990_103
        try privateCredential(id)
        let authorization = fixtureAuthorization()
        try await authorization.revoke(id)
        let available = try await authorization.prepareExistingCredential(for: id, clientID: "fixture-client")
        XCTAssertFalse(available)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "")
        XCTAssertNil(try WidgetCredentialStore.privateToken(id))
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 0)
    }

    @MainActor
    func testStartupMigratesAndRestoresAMislabelledAccount() async throws {
        let id = 990_104
        try privateCredential(id)
        try flaggedAccount(id, expired: true)
        let manager = AuthTokenManager(authorization: fixtureAuthorization())
        await manager.validateStoredCredentials()
        XCTAssertEqual(EVELogin.shared.getCharacterByID(id)?.character.refreshTokenExpired, false)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "fixture-rotated")
        XCTAssertNil(try WidgetCredentialStore.privateToken(id))
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 1)
    }

    @MainActor
    func testServerRevocationRemainsExpiredAndCannotBeRemigrated() async throws {
        let id = 990_105
        try privateCredential(id)
        try flaggedAccount(id, expired: true)
        let authorization = fixtureAuthorization(status: 400)
        await AuthTokenManager(authorization: authorization).validateStoredCredentials()
        XCTAssertEqual(EVELogin.shared.getCharacterByID(id)?.character.refreshTokenExpired, true)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "")
        let available = try await authorization.prepareExistingCredential(for: id, clientID: "fixture-client")
        XCTAssertFalse(available)
        XCTAssertNil(try WidgetCredentialStore.privateToken(id))
    }

    @MainActor
    func testTemporaryFailureKeepsMigratedCredentialForNextLaunch() async throws {
        let id = 990_106
        try privateCredential(id)
        try flaggedAccount(id, expired: true)
        await AuthTokenManager(authorization: fixtureAuthorization(status: 503)).validateStoredCredentials()
        XCTAssertEqual(EVELogin.shared.getCharacterByID(id)?.character.refreshTokenExpired, true)
        XCTAssertEqual(try WidgetCredentialStore.read(id)?.refreshToken, "fixture-private")
        await AuthTokenManager(authorization: fixtureAuthorization()).validateStoredCredentials()
        XCTAssertEqual(EVELogin.shared.getCharacterByID(id)?.character.refreshTokenExpired, false)
    }

    @MainActor
    func testUnreadablePrivateCredentialDoesNotExpireAccountOrDeleteOriginal() async throws {
        let id = 990_107
        try privateCredential(id, data: Data([0xFF]))
        try flaggedAccount(id, expired: false)
        await AuthTokenManager(authorization: fixtureAuthorization()).validateStoredCredentials()
        XCTAssertEqual(EVELogin.shared.getCharacterByID(id)?.character.refreshTokenExpired, false)
        XCTAssertNil(try WidgetCredentialStore.read(id))
        XCTAssertThrowsError(try WidgetCredentialStore.privateToken(id))
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 0)
    }

    func testPartialPlanetFailureDoesNotAdvanceSyncTime() async throws {
        let store = try store()
        let old = Date().addingTimeInterval(-7200)
        let planets = [1, 2].map { WidgetPlanet(
            id: $0,
            name: "Fixture \($0)",
            planetType: "temperate",
            hasExtractor: true,
            cycles: []
        ) }
        let snapshot = WidgetSnapshot(characters: [.init(
            id: 990_096,
            name: "Fixture",
            planets: planets,
            planetsAt: old
        )])
        try store.saveCatalog(.init(
            accounts: [.init(id: 990_096, name: "Fixture", needsLogin: false)],
            planetNames: [1: "Fixture 1", 2: "Fixture 2"]
        ))
        _ = try await store.accept(.planets(planets), id: 990_096, at: old)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetFixtureProtocol.self]
        WidgetFixtureProtocol.configure(failSecondPage: true)
        let refresher = WidgetRepository(
            session: URLSession(configuration: configuration), store: store,
            snapshotLoader: { _, _ in snapshot }, tokenProvider: { _, _, _ in "fixture-access" }
        )
        await refresher.refresh(kind: .planets, rowLimit: 3)
        let result = store.snapshot()
        XCTAssertEqual(result.characters[0].planetsAt, old)
        XCTAssertEqual(result.characters[0].planets, planets)
        XCTAssertEqual(store.read(.init(source: .planets, id: 990_096))?.failure, .unavailable)
        XCTAssertEqual(WidgetFixtureProtocol.requestCount, 3)
    }

    @MainActor
    func testRenderWidgetStates() throws {
        let date = Date()
        let job = WidgetIndustryJob(
            id: 1, typeID: 2, name: "工业项目预览 · Blueprint", activity: .manufacturing,
            status: .active, end: date.addingTimeInterval(3700), start: date.addingTimeInterval(-7200),
            runs: 10, characterID: 1
        )
        let snapshot = WidgetSnapshot(characters: [.init(
            id: 1,
            name: "Preview character",
            jobs: (0 ..< 3).map { index in
                WidgetIndustryJob(
                    id: index + 1,
                    typeID: job.typeID,
                    name: job.name,
                    activity: [.manufacturing, .materialResearch, .reaction][index],
                    status: .active,
                    end: date.addingTimeInterval([5400, 183_600, 61][index]),
                    start: job.start,
                    runs: 10,
                    characterID: 1
                )
            },
            jobsAt: date.addingTimeInterval(-7200)
        )])
        for (language, dark) in [
            ("zh-Hans", false), ("zh-Hans", true), ("en", false), ("ru", false),
        ] {
            let view = NexusWidgetView(
                kind: .industryList,
                entry: .init(date: date, snapshot: snapshot),
                previewFamily: .systemMedium
            )
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: language))
            .frame(width: 306, height: 126)
            .padding(16)
            .background(dark ? Color.black : Color.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Industry-\(language)-\(dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testRenderAllWidgetFamilies() throws {
        let date = Date()
        let stamp = date.addingTimeInterval(-180)
        let snapshot = WidgetSnapshot(
            market: (1 ... 9).map { id in
                .init(
                    id: id,
                    name: "示例物品 \(id)",
                    price: 12_300_000 * Double(id),
                    quotedAt: stamp,
                    history: (0 ..< 12).map { .init(
                        date: date.addingTimeInterval(Double($0 - 12) * 86400),
                        average: Double(100 + $0 * id)
                    ) }
                )
            },
            characters: (1 ... 9).map { id in
                let end = date.addingTimeInterval(Double(id) * 3600)
                return .init(
                    id: id, name: "示例角色 \(id)",
                    skills: [.init(
                        typeID: 3449,
                        name: "导航学",
                        level: 4,
                        start: date.addingTimeInterval(-3600),
                        finish: end
                    )],
                    planets: (0 ..< 6).map { .init(
                        id: $0,
                        name: "示例行星 \($0)",
                        planetType: ["temperate", "barren", "gas"][$0 % 3],
                        hasExtractor: true,
                        cycles: [DateInterval(
                            start: date.addingTimeInterval(-7200),
                            end: $0 == 0 ? stamp : ($0 == 1 ? date.addingTimeInterval(300) : end)
                        )]
                    ) },
                    jobs: [.init(
                        id: id,
                        typeID: 2,
                        name: "示例蓝图 \(id)",
                        activity: .manufacturing,
                        status: id == 1 ? .ready : .active,
                        end: end,
                        start: date.addingTimeInterval(-7200),
                        runs: id,
                        characterID: id
                    )],
                    skillsAt: stamp, planetsAt: stamp, jobsAt: stamp
                )
            }
        )
        for kind in NexusWidgetKind.allCases {
            for family in kind.supportedFamilies {
                let height: CGFloat = family == .systemMedium ? 126 : (family == .systemLarge ? 322 : 500)
                let view = NexusWidgetView(
                    kind: kind,
                    entry: .init(date: date, snapshot: snapshot),
                    previewFamily: family
                )
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.colorScheme, .light)
                .frame(width: 306, height: height)
                .padding(16)
                .background(Color.white)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let attachment = try XCTAttachment(image: XCTUnwrap(renderer.uiImage))
                attachment.name = "\(kind.rawValue)-\(family)-preview"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

private final class WidgetFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var count = 0
    private static var fail = false
    private static var oauthStatus = 200
    static var requestCount: Int {
        lock.withLock { count }
    }

    static func configure(failSecondPage: Bool, oauthStatus: Int = 200) {
        lock.withLock { count = 0
            fail = failSecondPage
            Self.oauthStatus = oauthStatus
        }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let (failure, oauthStatus) = Self.lock.withLock { Self.count += 1
            return (Self.fail, Self.oauthStatus)
        }
        let path = request.url!.absoluteString.components(separatedBy: "?")[0]
        let isSecond = request.url!.query?.contains("page=2") == true || path.hasSuffix("/planets/2/")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: path.contains("oauth/token") ? oauthStatus : (failure && isSecond ? 503 : 200),
            httpVersion: nil,
            headerFields: ["X-Pages": "2"]
        )!
        let body: String
        if path.contains("oauth/token") {
            body = oauthStatus == 400 ? #"{"error":"invalid_grant"}"#
                : #"{"access_token":"fixture-access","refresh_token":"fixture-rotated","expires_in":1200}"#
        } else if path.hasSuffix("/planets/") {
            body = #"[{"planet_id":1,"planet_type":"temperate"},{"planet_id":2,"planet_type":"barren"}]"#
        } else if path.contains("/planets/") {
            body = #"{"pins":[{"extractor_details":{},"install_time":"2026-11-26T10:00:00Z","expiry_time":"2026-11-28T10:00:00Z"}]}"#
        } else {
            let price = isSecond ? 12 : 20
            body = "[{\"is_buy_order\":false,\"location_id\":60003760,\"price\":\(price)},{\"is_buy_order\":false,\"location_id\":1,\"price\":1}]"
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
