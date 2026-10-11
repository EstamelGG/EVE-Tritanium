import XCTest
@testable import EVE_Nexus

final class PlanetaryCalculationReuseTests: XCTestCase {
    /// 优化前的逐周期公式，作为固定回归基准，独立于生产代码的预计算路径。
    private func originalOutput(base: Int, cycleDuration: Double, index: Int) -> Int64 {
        let sec: Int64 = 10_000_000
        let cycleTime = Int64(cycleDuration * Double(sec))
        let timeDiff = Int64(index + 1) * cycleTime
        let cycleNum = max((timeDiff + sec) / cycleTime - 1, 0)
        let barWidth = Double(cycleTime) / Double(sec) / 900.0
        let t = (Double(cycleNum) + 0.5) * barWidth
        let decayValue = Double(base) / (1.0 + t * 0.012)
        let phaseShift = pow(Double(base), 0.7)
        let sinA = cos(phaseShift + t * (1.0 / 12.0))
        let sinB = cos(phaseShift / 2.0 + t * (1.0 / 5.0))
        let sinC = cos(t * (1.0 / 2.0))
        let sinStuff = max((sinA + sinB + sinC) / 3.0, 0.0)
        let barHeight = decayValue * (1.0 + 0.8 * sinStuff)
        return Int64(floor(barWidth * barHeight))
    }

    func testPreparedPredictionMatchesOriginalFormula() {
        for base in [0, 1, 17, 1000, 12000, 1_000_000] {
            for duration in [900.0, 901.25, 1800, 3600, 14400] {
                let values = ExtractionSimulation.getProgramOutputPrediction(
                    baseValue: base, cycleDuration: duration, length: 2048
                )
                for index in values.indices {
                    XCTAssertEqual(values[index], originalOutput(base: base, cycleDuration: duration, index: index))
                }
            }
        }
    }

    func testSingleCycleAndRangeKeepOriginalIndexing() {
        let calculator = ExtractorYieldCalculator(quantityPerCycle: 12000, cycleTime: 900)
        XCTAssertEqual(calculator.calculateYield(cycleIndex: -1), 0)
        for index in [0, 1, 99, 1000, 5000] {
            XCTAssertEqual(Int64(calculator.calculateYield(cycleIndex: index)), originalOutput(base: 12000, cycleDuration: 900, index: index))
        }
        let values = calculator.calculateRange(startCycle: 10, endCycle: 20)
        XCTAssertEqual(values.map(\.cycle), Array(11 ... 21))
        XCTAssertEqual(values.map(\.yield), (10 ... 20).map { Int(originalOutput(base: 12000, cycleDuration: 900, index: $0)) })
    }

    func testCurveUsesEveryNumericInputAndKeepsMaximum() {
        let inputs = [(12000, 900, 0, 100), (12001, 900, 0, 100),
                      (12000, 1800, 0, 100), (12000, 900, 10, 100), (12000, 900, 0, 101)]
        for (base, duration, start, end) in inputs {
            let calculator = ExtractorYieldCalculator(quantityPerCycle: base, cycleTime: duration)
            let expected = (start ... end).map { Int(originalOutput(base: base, cycleDuration: Double(duration), index: $0)) }
            // 重复读取和交错的不同输入都必须返回各自的完整结果。
            for _ in 0 ..< 2 {
                let curve = calculator.curve(startCycle: start, endCycle: end)
                XCTAssertEqual(curve.yields.map(\.yield), expected)
                XCTAssertEqual(curve.maximumYield, expected.max())
            }
        }
    }

    func testParsedDatesAndCycleBoundariesMatchOriginalSemantics() {
        let install = "2026-10-13T00:00:00Z"
        let expiry = "2026-10-13T01:00:00Z"
        let start = ISO8601DateFormatter().date(from: install)!
        XCTAssertEqual(ExtractorYieldCalculator.calculateTotalCycles(installTime: install, expiryTime: expiry, cycleTime: 900), 3)
        for (seconds, expected) in [(0.0, 0), (899.0, 0), (900.0, 1), (3599.0, 3), (3600.0, -1)] {
            XCTAssertEqual(ExtractorYieldCalculator.getCurrentCycle(installTime: install, expiryTime: expiry, cycleTime: 900, currentTime: start.addingTimeInterval(seconds)), expected)
        }
        for text in [install, expiry, "2026-10-13T08:00:00+08:00", "invalid", ""] {
            for _ in 0 ..< 2 {
                XCTAssertEqual(ExtractorYieldCalculator.parsedDate(text), ISO8601DateFormatter().date(from: text))
            }
        }
    }
}
