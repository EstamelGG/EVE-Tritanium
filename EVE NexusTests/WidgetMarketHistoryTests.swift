import Foundation
import SwiftUI
import XCTest
@testable import EVE_Nexus

final class WidgetMarketHistoryTests: XCTestCase {
    func testTrendColorsSupportBothConventionsAndKeepFlatChangesNeutral() {
        XCTAssertEqual(WidgetMarketTrendColors.defaultStyle(for: "zh-Hans"), .redUp)
        XCTAssertEqual(WidgetMarketTrendColors.defaultStyle(for: "zh-Hant"), .redUp)
        XCTAssertEqual(WidgetMarketTrendColors.defaultStyle(for: "en"), .greenUp)
        XCTAssertEqual(WidgetMarketTrendColors.defaultStyle(for: "ru"), .greenUp)
        XCTAssertEqual(WidgetMarketTrendColors.defaultStyle(for: nil), .greenUp)
        XCTAssertEqual(WidgetMarketTrendColors.greenUp.color(for: 0.1), .green)
        XCTAssertEqual(WidgetMarketTrendColors.greenUp.color(for: -0.1), .red)
        XCTAssertEqual(WidgetMarketTrendColors.redUp.color(for: 0.1), .red)
        XCTAssertEqual(WidgetMarketTrendColors.redUp.color(for: -0.1), .green)
        XCTAssertEqual(WidgetMarketTrendColors.redUp.color(for: 0), .secondary)
        XCTAssertEqual(WidgetMarketTrendColors.greenUp.color(for: nil), .secondary)
    }

    func testTrendsUseThreeCalendarMonthsAndCarryForwardMissingDays() throws {
        let day = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        let now = try day.parse("2025-06-30")
        let data = try [
            ("2025-06-20", 8.0),
            ("2025-03-29", 40.0),
            ("2025-03-30", 4.0),
            ("2025-04-01", 0.0),
            ("2025-06-20", 9.0),
            ("2025-06-21", Double.infinity),
            ("2025-07-01", 20.0),
        ].map { WidgetMarketPoint(date: try day.parse($0.0), average: $0.1) }

        let points = WidgetMarketPoint.recent(data, through: now)

        XCTAssertEqual(points.map(\.average), [4, 9, 9])
        XCTAssertEqual(points.map { day.format($0.date) }, ["2025-03-30", "2025-06-20", "2025-06-30"])

        let plotted = MarketHistorySparkline.plottedPoints(from: points)
        XCTAssertEqual(plotted.map(\.average), [4, 4, 9, 9])
        XCTAssertEqual(
            plotted.map { day.format($0.date) },
            ["2025-03-30", "2025-06-19", "2025-06-20", "2025-06-30"]
        )
    }

    func testTrendsCarryForwardPreWindowPriceWhenStartDayHasNoTrades() throws {
        let day = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        let now = try day.parse("2025-06-30")
        let data = try [
            ("2025-03-10", 50.0),
            ("2025-05-01", 100.0),
        ].map { WidgetMarketPoint(date: try day.parse($0.0), average: $0.1) }

        let points = WidgetMarketPoint.recent(data, through: now)

        XCTAssertEqual(points.map(\.average), [50, 100, 100])
        XCTAssertEqual(points.map { day.format($0.date) }, ["2025-03-30", "2025-05-01", "2025-06-30"])

        let plotted = MarketHistorySparkline.plottedPoints(from: points)
        XCTAssertEqual(plotted.map(\.average), [50, 50, 100, 100])
        XCTAssertEqual(
            plotted.map { day.format($0.date) },
            ["2025-03-30", "2025-04-30", "2025-05-01", "2025-06-30"]
        )
    }

}
