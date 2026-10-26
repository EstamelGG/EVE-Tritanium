import XCTest
import SwiftUI
@testable import EVE_Nexus

final class MarketHistoryChartDataTests: XCTestCase {
    @MainActor
    func testChartHeightDependsOnRowWidthInsteadOfViewportHeight() {
        let host = UIHostingController(rootView: MarketHistoryChartLayout { Color.clear })
        let tall = host.sizeThatFits(in: CGSize(width: 360, height: 900))
        let short = host.sizeThatFits(in: CGSize(width: 360, height: 300))
        XCTAssertEqual(tall.height, 198, accuracy: 1)
        XCTAssertEqual(short.height, tall.height, accuracy: 1)
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 280, height: 900)).height, 160, accuracy: 1)
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 800, height: 900)).height, 300, accuracy: 1)
    }

    private func history(_ date: String, price: Double = 100, volume: Int = 10) -> MarketHistory {
        MarketHistory(average: price, date: date, highest: price, lowest: price, order_count: 1, volume: volume)
    }

    func testSparseMonthsIncludeFirstAvailableDayAndDistinguishYears() {
        let data = MarketHistoryChartData(history: [
            history("2026-01-08"), history("2025-01-09"),
            history("2026-02-03"), history("2026-01-02"),
        ], timeRange: .threeMonths)
        XCTAssertEqual(data.xAxisDates, ["2025-01-09", "2026-01-02", "2026-02-03"])
        XCTAssertEqual(data.dates, ["2025-01-09", "2026-01-02", "2026-01-08", "2026-02-03"])
    }

    func testVisibleWindowPreservesFullSeriesPositionsAndUsesItsOwnScale() {
        let full = [history("2026-01-01", price: 10, volume: 100_000),
                    history("2026-02-01", price: 100, volume: 10),
                    history("2026-02-02", price: 110, volume: 20)]
        let data = MarketHistoryChartData(history: Array(full.suffix(2)), fullHistory: full)
        XCTAssertEqual(data.plottedHistory.count, 3)
        XCTAssertEqual(data.datePositions["2026-02-01"], 1)
        XCTAssertEqual(data.xDomain, 0.5 ... 2.5)
        XCTAssertEqual(data.xAxisDates, ["2026-02-01"])
        XCTAssertLessThan(data.axisScale.volumeUpperBound, 100)
    }

    @MainActor
    func testReconstructedViewsReusePreparedDataAndNewDataInvalidatesComparison() {
        let data = MarketHistoryChartData(history: [history("2026-01-01")])
        let first = MarketHistoryChartView(chartData: data)
        let reconstructed = MarketHistoryChartView(chartData: data)
        XCTAssertTrue(first == reconstructed)
        XCTAssertTrue(reconstructed.chartData === data)
        let refreshed = MarketHistoryChartData(history: [history("2026-01-01", price: 200)])
        XCTAssertFalse(first == MarketHistoryChartView(chartData: refreshed))
    }

    func testEmptyHistoryHasAValidDomainAndNoMonthLabels() {
        let data = MarketHistoryChartData(history: [])
        XCTAssertEqual(data.xDomain, -0.5 ... 0.5)
        XCTAssertTrue(data.xAxisDates.isEmpty)
        XCTAssertTrue(data.axisScale.priceUpperBound.isFinite)
    }

    func testOneMonthLabelsUseStartMidpointAndEndOfVisibleWindow() {
        let full = (1 ... 31).map { history(String(format: "2026-01-%02d", $0)) }
        let data = MarketHistoryChartData(
            history: Array(full.suffix(30)), fullHistory: full, timeRange: .oneMonth
        )
        XCTAssertEqual(data.xAxisDates, ["2026-01-02", "2026-01-17", "2026-01-31"])
        XCTAssertEqual(data.xAxisDates.compactMap { data.datePositions[$0] }, [1, 16, 30])
        XCTAssertEqual(data.timeRange, .oneMonth)
    }

    func testShortHistoryDoesNotDuplicateDateLabels() {
        for timeRange in PriceHistoryTimeRange.allCases {
            XCTAssertTrue(MarketHistoryChartData(history: [], timeRange: timeRange).xAxisDates.isEmpty)
            XCTAssertEqual(
                MarketHistoryChartData(history: [history("2026-01-08")], timeRange: timeRange).xAxisDates,
                ["2026-01-08"]
            )
        }
        let data = MarketHistoryChartData(
            history: [history("2026-01-08"), history("2026-01-20")], timeRange: .oneMonth
        )
        XCTAssertEqual(data.xAxisDates, ["2026-01-08", "2026-01-20"])
    }

    func testLongerRangesUseMonthlyAndEveryOtherMonthLabels() {
        let monthly = (1 ... 12).map { history(String(format: "2026-%02d-01", $0)) }
        let quarter = MarketHistoryChartData(history: Array(monthly.suffix(3)), timeRange: .threeMonths)
        XCTAssertEqual(quarter.xAxisDates, ["2026-10-01", "2026-11-01", "2026-12-01"])
        let year = MarketHistoryChartData(history: monthly, timeRange: .oneYear)
        XCTAssertEqual(year.xAxisDates, [
            "2026-01-01", "2026-03-01", "2026-05-01", "2026-07-01", "2026-09-01", "2026-11-01",
        ])
    }
}
