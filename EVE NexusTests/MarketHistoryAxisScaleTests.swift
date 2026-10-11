import XCTest
@testable import EVE_Nexus

final class MarketHistoryAxisScaleTests: XCTestCase {
    func testBothAxesAndBarsShareGridPositions() {
        let scale = MarketHistoryAxisScale(
            prices: [310_000_000, 430_000_000, 560_000_000],
            volumes: [400, 2_500, 8_000]
        )
        XCTAssertEqual(scale.priceStep, 100_000_000)
        XCTAssertLessThanOrEqual(scale.priceLowerBound, 310_000_000)
        XCTAssertGreaterThanOrEqual(scale.priceUpperBound, 560_000_000)
        XCTAssertEqual(scale.priceTicks.count, scale.volumeTicks.count)
        for (price, volume) in zip(scale.priceTicks, scale.volumeTicks) {
            XCTAssertEqual(scale.pricePosition(forVolume: volume), price, accuracy: 0.000001)
            XCTAssertEqual(scale.normalizedPrice(price), scale.normalizedVolume(volume), accuracy: 0.000001)
        }
        XCTAssertEqual(scale.gridPositions.first, 0)
        XCTAssertEqual(scale.gridPositions.last, 1)
        XCTAssertEqual(scale.normalizedPrice(scale.priceLowerBound), 0)
        XCTAssertEqual(scale.normalizedPrice(scale.priceUpperBound), 1)
        XCTAssertEqual(scale.normalizedVolume(0), 0)
        XCTAssertEqual(scale.normalizedVolume(scale.volumeUpperBound), 1)
        XCTAssertEqual(
            (scale.pricePosition(forVolume: 2_500) - scale.priceLowerBound) / scale.priceRange,
            2_500 / scale.volumeUpperBound,
            accuracy: 0.000001
        )
    }

    func testTimeWindowsRecalculateVolumeScaleEvenWithUnchangedPrices() {
        let prices = Array(repeating: 500_000_000.0, count: 360)
        let volumes = Array(repeating: 9_000.0, count: 270)
            + Array(repeating: 1_500.0, count: 60)
            + Array(repeating: 300.0, count: 30)
        let year = MarketHistoryAxisScale(prices: prices, volumes: volumes)
        let quarter = MarketHistoryAxisScale(
            prices: Array(prices.suffix(90)), volumes: Array(volumes.suffix(90))
        )
        let month = MarketHistoryAxisScale(
            prices: Array(prices.suffix(30)), volumes: Array(volumes.suffix(30))
        )
        XCTAssertEqual(year.priceTicks, month.priceTicks)
        XCTAssertGreaterThan(year.volumeUpperBound, quarter.volumeUpperBound)
        XCTAssertGreaterThan(quarter.volumeUpperBound, month.volumeUpperBound)
        XCTAssertNotEqual(year, quarter)
        XCTAssertNotEqual(quarter, month)
    }

    func testVolumeStepsAreIntegersAndAllowHeadroom() {
        for maxVolume in [0.0, 1, 7, 500, 1_500, 99_999, 2_000_000, 9_000_000_000] {
            let scale = MarketHistoryAxisScale(prices: [100, 200], volumes: [maxVolume])
            XCTAssertGreaterThanOrEqual(scale.volumeStep, 1)
            XCTAssertEqual(scale.volumeStep, scale.volumeStep.rounded())
            XCTAssertLessThanOrEqual(maxVolume / scale.volumeUpperBound, 0.85 + 0.000001)
            if maxVolume >= 100 {
                XCTAssertGreaterThan(maxVolume / scale.volumeUpperBound, 0.75)
            }
            XCTAssertTrue(scale.volumeTicks.allSatisfy { $0 == $0.rounded() })
        }
    }

    func testEmptyConstantAndSmallPricesHaveValidRanges() {
        for prices in [[], [0.0], [100.0, 100], [0.001, 0.002]] {
            let scale = MarketHistoryAxisScale(prices: prices, volumes: [0])
            XCTAssertTrue(scale.priceLowerBound.isFinite)
            XCTAssertTrue(scale.priceUpperBound.isFinite)
            XCTAssertGreaterThan(scale.priceRange, 0)
            XCTAssertGreaterThan(scale.volumeUpperBound, 0)
            XCTAssertGreaterThanOrEqual(scale.priceTicks.count, 4)
            XCTAssertEqual(scale.pricePosition(forVolume: 0), scale.priceLowerBound)
            for price in prices {
                XCTAssertLessThanOrEqual(scale.priceLowerBound, price)
                XCTAssertGreaterThanOrEqual(scale.priceUpperBound, price)
            }
        }
    }

    func testNarrowPriceWindowDoesNotLeaveMostOfPlotEmpty() {
        // Similar to the reported one-month window: 884–949M ISK and 71 units.
        let scale = MarketHistoryAxisScale(prices: [884_000_000, 949_000_000], volumes: [71])
        XCTAssertGreaterThan(scale.normalizedPrice(949_000_000), 0.75)
        let midpoint = scale.normalizedPrice((884_000_000 + 949_000_000) / 2)
        XCTAssertGreaterThan(midpoint, 0.35)
        XCTAssertLessThan(midpoint, 0.65)
        XCTAssertGreaterThan(scale.normalizedVolume(71), 0.75)
        XCTAssertLessThanOrEqual(scale.normalizedVolume(71), 0.85)
        for (price, volume) in zip(scale.priceTicks, scale.volumeTicks) {
            XCTAssertEqual(scale.normalizedPrice(price), scale.normalizedVolume(volume), accuracy: 0.000001)
        }
    }
}
