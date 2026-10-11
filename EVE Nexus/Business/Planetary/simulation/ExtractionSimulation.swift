import Foundation

class ExtractionSimulation {
    private static let SEC: Int64 = 10_000_000
    private static let decayFactor: Double = 0.012
    private static let noiseFactor: Double = 0.8
    private static let f1: Double = 1.0 / 12.0
    private static let f2: Double = 1.0 / 5.0
    private static let f3: Double = 1.0 / 2.0

    /// 计算特定时间点的产出
    /// - Parameters:
    ///   - baseValue: 基础产量
    ///   - startTime: 开始时间
    ///   - currentTime: 当前时间
    ///   - cycleTime: 周期时长（秒）
    /// - Returns: 该时间点的产量
    static func getProgramOutput(
        baseValue: Int,
        startTime: Date,
        currentTime: Date,
        cycleTime: TimeInterval
    ) -> Int64 {
        Program(baseValue: baseValue, cycleDuration: cycleTime)
            .output(startTime: startTime, currentTime: currentTime)
    }

    /// 固定采集参数；仅复用常量，保留原公式的运算顺序和逐周期取整。
    struct Program {
        private let baseValue: Int
        private let cycleTime: Int64
        private let barWidth: Double
        private let phaseShift: Double

        init(baseValue: Int, cycleDuration: TimeInterval) {
            self.baseValue = baseValue
            cycleTime = Int64(cycleDuration * Double(SEC))
            barWidth = Double(cycleTime) / Double(SEC) / 900.0
            phaseShift = pow(Double(baseValue), 0.7)
        }

        func output(startTime: Date, currentTime: Date) -> Int64 {
            let startTimeSeconds = Int64(startTime.timeIntervalSince1970 * Double(SEC))
            let currentTimeSeconds = Int64(currentTime.timeIntervalSince1970 * Double(SEC))
            return output(startTime: startTimeSeconds, currentTime: currentTimeSeconds)
        }

        func prediction(cycleIndex: Int) -> Int64 {
            output(startTime: 0, currentTime: Int64(cycleIndex + 1) * cycleTime)
        }

        private func output(startTime: Int64, currentTime: Int64) -> Int64 {
            let timeDiff = currentTime - startTime
            let cycleNum = max((timeDiff + SEC) / cycleTime - 1, 0)
            let t = (Double(cycleNum) + 0.5) * barWidth
            let decayValue = Double(baseValue) / (1.0 + t * decayFactor)
            let sinA = cos(phaseShift + t * f1)
            let sinB = cos(phaseShift / 2.0 + t * f2)
            let sinC = cos(t * f3)
            let sinStuff = max((sinA + sinB + sinC) / 3.0, 0.0)
            let barHeight = decayValue * (1.0 + noiseFactor * sinStuff)
            let output = barWidth * barHeight
            return Int64(floor(output))
        }
    }

    /// 预测未来多个周期的产出
    /// - Parameters:
    ///   - baseValue: 基础产量
    ///   - cycleDuration: 周期时长（秒）
    ///   - length: 预测周期数
    /// - Returns: 预测的产量列表
    static func getProgramOutputPrediction(
        baseValue: Int,
        cycleDuration: TimeInterval,
        length: Int
    ) -> [Int64] {
        let program = Program(baseValue: baseValue, cycleDuration: cycleDuration)
        var results = [Int64]()
        results.reserveCapacity(length)
        for i in 0 ..< length {
            results.append(program.prediction(cycleIndex: i))
        }
        return results
    }
}
