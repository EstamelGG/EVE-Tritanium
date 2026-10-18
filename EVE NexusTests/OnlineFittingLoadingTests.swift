@testable import EVE_Nexus
import XCTest

@MainActor
final class OnlineFittingLoadingTests: XCTestCase {
    private func context() throws -> (DatabaseManager, CharacterFitting) {
        let data = try FittingRegressionData.shared.get()
        return (data.db, CharacterFitting(description: "", fitting_id: 123, items: [], name: "Online fit", ship_type_id: 587))
    }

    private func assertCatalog(_ model: OnlineFittingViewModel, fitting: CharacterFitting,
                               file: StaticString = #filePath, line: UInt = #line)
    {
        XCTAssertEqual(model.fittingsByID[fitting.fitting_id]?.name, fitting.name, file: file, line: line)
        XCTAssertEqual(model.tree.flatMap(\.children).flatMap(\.fittings).map(\.ref), [.online(fitting.fitting_id)], file: file, line: line)
        XCTAssertFalse(model.isLoading, file: file, line: line)
        XCTAssertNil(model.errorMessage, file: file, line: line)
    }

    func testRepeatedEntriesRestoreCatalogFromImmediateCacheHits() async throws {
        let (db, fitting) = try context()
        var cache: [CharacterFitting]?
        var requests = 0
        var networkRequests = 0
        let fetch: (Int, Bool) async throws -> [CharacterFitting] = { _, forceRefresh in
            requests += 1
            if !forceRefresh, let cache {
                return cache
            }
            networkRequests += 1
            await Task.yield() // 首次网络请求会挂起，后续命中缓存立即返回。
            cache = [fitting]
            return [fitting]
        }
        let model = OnlineFittingViewModel(characterId: 9_999_001, databaseManager: db, fetchFittings: fetch)
        for _ in 0 ..< 10 {
            await model.loadOnlineFittings()
            assertCatalog(model, fitting: fitting)
        }
        for _ in 0 ..< 10 {
            let reopened = OnlineFittingViewModel(characterId: 9_999_001, databaseManager: db, fetchFittings: fetch)
            await reopened.loadOnlineFittings()
            assertCatalog(reopened, fitting: fitting)
        }
        XCTAssertEqual(requests, 11, "同一模型复用已完成目录，页面重建后从 API 缓存恢复")
        XCTAssertEqual(networkRequests, 1, "重复进入应优先使用缓存，无需强制刷新")
    }

    func testSourceSwitchWaitsForExistingPreload() async throws {
        let (db, fitting) = try context()
        var requests = 0
        var pending: CheckedContinuation<[CharacterFitting], Error>?
        let model = OnlineFittingViewModel(characterId: 9_999_004, databaseManager: db) { _, _ in
            requests += 1
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        let preload = Task { await model.loadOnlineFittings() }
        for _ in 0 ..< 100 {
            if pending != nil {
                break
            }
            await Task.yield()
        }
        let continuation = try XCTUnwrap(pending)
        var switched = false
        let sourceSwitch = Task {
            switched = true
            await model.loadOnlineFittings()
        }
        for _ in 0 ..< 100 {
            if switched {
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(switched)
        XCTAssertEqual(requests, 1, "切换来源不能取消并重新发起正在进行的预加载")
        continuation.resume(returning: [fitting])
        await preload.value
        await sourceSwitch.value
        assertCatalog(model, fitting: fitting)
    }

    func testFailedLoadsCanRetryAndEmptyResultsCanBeForceRefreshed() async throws {
        let (db, fitting) = try context()
        var requests = 0
        let model = OnlineFittingViewModel(characterId: 9_999_002, databaseManager: db) { _, forceRefresh in
            XCTAssertEqual(forceRefresh, requests >= 2)
            requests += 1
            if requests == 1 {
                throw URLError(.notConnectedToInternet)
            }
            return requests == 2 ? [] : [fitting]
        }
        await model.loadOnlineFittings()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        await model.loadOnlineFittings()
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.tree.isEmpty)
        await model.loadOnlineFittings()
        XCTAssertEqual(requests, 2, "真实的空列表也应复用，避免来源切换反复加载")
        await model.loadOnlineFittings(forceRefresh: true)
        assertCatalog(model, fitting: fitting)
    }

    func testForceRefreshIsForwardedAndFailedRefreshPreservesVisibleData() async throws {
        let (db, fitting) = try context()
        var flags: [Bool] = []
        let model = OnlineFittingViewModel(characterId: 9_999_003, databaseManager: db) { _, forceRefresh in
            flags.append(forceRefresh)
            if flags.count == 2 {
                throw URLError(.timedOut)
            }
            return [fitting]
        }
        await model.loadOnlineFittings()
        await model.loadOnlineFittings(forceRefresh: true)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.fittingsByID.count, 1)
        XCTAssertFalse(model.tree.isEmpty)
        XCTAssertFalse(model.isLoading)
        await model.loadOnlineFittings(forceRefresh: true)
        assertCatalog(model, fitting: fitting)
        XCTAssertEqual(flags, [false, true, true])
    }
}
