import Foundation

class ExtractorYieldCalculator {
    private let quantityPerCycle: Int
    private let cycleTime: Int

    init(quantityPerCycle: Int, cycleTime: Int) {
        self.quantityPerCycle = quantityPerCycle
        self.cycleTime = cycleTime
    }

    func calculateYield(cycleIndex: Int) -> Int {
        // 原方法只使用预测数组的最后一项，其余周期没有被使用。
        guard cycleIndex >= 0 else { return 0 }
        return Int(ExtractionSimulation.Program(
            baseValue: quantityPerCycle, cycleDuration: TimeInterval(cycleTime)
        ).prediction(cycleIndex: cycleIndex))
    }

    func calculateRange(startCycle: Int, endCycle: Int) -> [(cycle: Int, yield: Int)] {
        curve(startCycle: startCycle, endCycle: endCycle).yields
    }

    final class YieldCurve {
        let yields: [(cycle: Int, yield: Int)]
        let maximumYield: Int

        init(yields: [(cycle: Int, yield: Int)]) {
            self.yields = yields
            maximumYield = yields.lazy.map(\.yield).max() ?? 0
        }
    }

    /// 纯输入决定的不可变结果；条数和内存均受限，不保存设施可变状态。
    private static let curves: NSCache<NSString, YieldCurve> = {
        let cache = NSCache<NSString, YieldCurve>()
        cache.countLimit = 64
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    private static let curveLock = NSLock()

    func curve(startCycle: Int, endCycle: Int) -> YieldCurve {
        let key = "\(quantityPerCycle):\(cycleTime):\(startCycle):\(endCycle)" as NSString
        Self.curveLock.lock()
        defer { Self.curveLock.unlock() }
        if let cached = Self.curves.object(forKey: key) {
            return cached
        }
        let program = ExtractionSimulation.Program(
            baseValue: quantityPerCycle, cycleDuration: TimeInterval(cycleTime)
        )
        var yields: [(cycle: Int, yield: Int)] = []
        yields.reserveCapacity(endCycle - startCycle + 1)
        for cycle in startCycle ... endCycle {
            yields.append((cycle: cycle + 1, yield: Int(program.prediction(cycleIndex: cycle))))
        }
        let result = YieldCurve(yields: yields)
        Self.curves.setObject(result, forKey: key, cost: yields.count * MemoryLayout<(Int, Int)>.stride)
        return result
    }

    private final class ParsedDate {
        let value: Date?
        init(_ value: Date?) {
            self.value = value
        }
    }

    private static let dates: NSCache<NSString, ParsedDate> = {
        let cache = NSCache<NSString, ParsedDate>()
        cache.countLimit = 256
        return cache
    }()

    static func parsedDate(_ text: String) -> Date? {
        if let cached = dates.object(forKey: text as NSString) {
            return cached.value
        }
        // formatter 保持局部，避免多个线程共享可变格式化器。
        let value = ISO8601DateFormatter().date(from: text)
        dates.setObject(ParsedDate(value), forKey: text as NSString)
        return value
    }

    static func calculateTotalCycles(installTime: String, expiryTime: String, cycleTime: Int) -> Int {
        guard let installDate = parsedDate(installTime),
              let expiryDate = parsedDate(expiryTime)
        else {
            return 0
        }

        let totalSeconds = expiryDate.timeIntervalSince(installDate)
        return Int(totalSeconds / Double(cycleTime)) - 1
    }

    static func getCurrentCycle(installTime: String, expiryTime: String, cycleTime: Int, currentTime: Date = Date()) -> Int {
        guard let installDate = parsedDate(installTime),
              let expiryDate = parsedDate(expiryTime)
        else {
            return 0
        }

        let elapsedSeconds = currentTime.timeIntervalSince(installDate)
        let currentCycle = Int(elapsedSeconds / Double(cycleTime))

        // 计算总周期数
        let totalSeconds = expiryDate.timeIntervalSince(installDate)
        let totalCycles = Int(totalSeconds / Double(cycleTime)) - 1

        // 如果超过了总周期数，返回-1表示已结束
        if currentCycle > totalCycles {
            return -1
        }

        return currentCycle
    }
}
