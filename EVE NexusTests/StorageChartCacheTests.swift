import XCTest
@testable import EVE_Nexus

final class StorageChartCacheTests: XCTestCase {
    func testChangedVolumesRefreshWithUnchangedSampleTimes() {
        var cache = StorageChartCache()
        cache.update(StorageChartInput(pinId: 1, capacity: 1_000, volumes: [60: 10, 0: 5]))
        let oldMax = cache.maxVolume

        XCTAssertTrue(cache.update(StorageChartInput(pinId: 1, capacity: 1_000, volumes: [60: 800, 0: 500])))
        XCTAssertEqual(cache.samples.map(\.hour), [0, 60])
        XCTAssertEqual(cache.samples.map(\.volume), [500, 800])
        XCTAssertGreaterThan(cache.maxVolume, oldMax)
    }

    func testCapacityChangeRefreshesScale() {
        var cache = StorageChartCache()
        cache.update(StorageChartInput(pinId: 1, capacity: 1_000, volumes: [0: 500]))
        XCTAssertEqual(cache.maxVolume, 1_200)
        cache.update(StorageChartInput(pinId: 1, capacity: 2_000, volumes: [0: 500]))
        XCTAssertEqual(cache.maxVolume, 2_400)
    }

    func testClearingDataRemovesOldSamples() {
        var cache = StorageChartCache()
        cache.update(StorageChartInput(pinId: 1, capacity: 1_000, volumes: [0: 500]))
        XCTAssertTrue(cache.update(StorageChartInput(pinId: 1, capacity: 1_000, volumes: [:])))
        XCTAssertTrue(cache.samples.isEmpty)
        XCTAssertGreaterThan(cache.maxVolume, 0)
    }

    func testUnchangedInputReusesCache() {
        var cache = StorageChartCache()
        let input = StorageChartInput(pinId: 1, capacity: 1_000, volumes: [0: 10])
        XCTAssertTrue(cache.update(input))
        XCTAssertFalse(cache.update(input))
    }

    func testEmptyAndZeroCapacityHaveFinitePositiveRanges() {
        for volumes in [[:], [0: 0.0], [0: 50.0]] {
            var cache = StorageChartCache()
            cache.update(StorageChartInput(pinId: 1, capacity: 0, volumes: volumes))
            XCTAssertTrue(cache.maxVolume.isFinite)
            XCTAssertGreaterThan(cache.maxVolume, 0)
        }
    }
}
