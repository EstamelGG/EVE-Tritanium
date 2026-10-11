import Foundation

/// 电容统计与视图生命周期分离；相同数值输入复用上次模拟结果。
final class FittingCapacitorCalculator {
    struct Cycle: Equatable {
        let duration: Double // 秒，含重激活延迟
        let need: Double
        let gain: Double // 每次激活的补能量，不摊入自然回充
        let shotsPerReload: Int // 0 表示无需换弹；备用弹药始终无限
        let reloadTime: Double // 秒

        init(duration: Double, need: Double, gain: Double = 0,
             shotsPerReload: Int = 0, reloadTime: Double = 0)
        {
            self.duration = duration
            self.need = need
            self.gain = gain
            self.shotsPerReload = shotsPerReload
            self.reloadTime = reloadTime
        }

        var averageInterval: Double {
            duration + (shotsPerReload > 0 ? reloadTime / Double(shotsPerReload) : 0)
        }
    }

    struct Input: Equatable {
        let capacity: Double
        let rechargeTime: Double // 秒
        let cycles: [Cycle]
    }

    struct Result: Equatable {
        let isStable: Bool
        let stableLevel: Double
        let lastsTime: Double
        let delta: Double
        /// 达到时间/事件上限不等于证明稳定，界面显示已验证的持续时间下限。
        let reachedLimit: Bool
    }

    private var cachedInput: Input?
    private var cachedResult: Result?

    func calculate(ship: SimShipOutput, modules: [SimModuleOutput]) -> Result {
        calculate(input: Self.makeInput(ship: ship, modules: modules))
    }

    func calculate(input: Input) -> Result {
        if cachedInput == input, let result = cachedResult {
            return result
        }
        let result = Self.simulate(input)
        cachedInput = input
        cachedResult = result
        return result
    }

    static func makeInput(ship: SimShipOutput, modules: [SimModuleOutput]) -> Input {
        var cycles: [Cycle] = []
        let durationKeys = ["speed", "duration", "durationHighisGood",
                            "durationSensorDampeningBurstProjector", "durationTargetIlluminationBurstProjector",
                            "durationECMJammerBurstProjector", "durationWeaponDisruptionBurstProjector"]
        for module in modules where module.status > 1 {
            let attrs = module.attributesByName
            let duration = (durationKeys.map { attrs[$0] ?? 0 }.max() ?? 0) / 1000
            let fullCycle = duration + max(0, attrs["moduleReactivationDelay"] ?? 0) / 1000
            guard duration > 0, fullCycle.isFinite, fullCycle > 0 else { continue }
            let need = max(0, attrs["capacitorNeed"] ?? 0)
            if module.groupID == 76 {
                guard let charge = module.charge else { continue }
                let quantity: Double
                if let loaded = charge.chargeQuantity {
                    quantity = Double(max(0, loaded))
                } else {
                    let volume = charge.attributesByName["volume"] ?? 0
                    guard volume > 0 else { continue }
                    quantity = floor((attrs["capacity"] ?? 0) / volume + 1e-9)
                }
                let chargeRate = attrs["chargeRate"] ?? 1
                guard chargeRate.isFinite, chargeRate > 0 else { continue }
                let shots = floor(quantity / chargeRate)
                guard shots.isFinite, shots > 0, shots < Double(Int.max) else { continue }
                cycles.append(Cycle(duration: fullCycle, need: need,
                                    gain: max(0, charge.attributesByName["capacitorBonus"] ?? 0) * chargeRate,
                                    shotsPerReload: Int(shots), reloadTime: max(0, attrs["reloadTime"] ?? 0) / 1000))
            } else {
                // 吸电仍假定目标能提供标称电量；没有引入目标电容/距离模拟。
                let gain = module.groupID == 68 ? max(0, attrs["powerTransferAmount"] ?? 0) : 0
                if need > 0 || gain > 0 {
                    cycles.append(Cycle(duration: fullCycle, need: need, gain: gain))
                }
            }
        }
        return Input(capacity: ship.attributesByName["capacitorCapacity"] ?? 0,
                     rechargeTime: (ship.attributesByName["rechargeRate"] ?? 0) / 1000,
                     cycles: cycles)
    }

    static func recharge(capacity: Double, time: Double, percent: Double) -> Double {
        guard capacity > 0, time > 0 else { return 0 }
        let root = sqrt(min(1, max(0, percent)))
        return 10 * capacity / time * root * (1 - root)
    }

    private static func simulate(_ input: Input) -> Result {
        let capacity = input.capacity
        let cycles = input.cycles.filter { $0.need > 0 || $0.gain > 0 }
        guard cycles.allSatisfy({ $0.duration.isFinite && $0.duration > 0 &&
                $0.need.isFinite && $0.need >= 0 && $0.gain.isFinite && $0.gain >= 0 &&
                $0.shotsPerReload >= 0 && $0.reloadTime.isFinite && $0.reloadTime >= 0 })
        else {
            return Result(isStable: false, stableLevel: 0, lastsTime: 0, delta: 0, reachedLimit: false)
        }
        // 平均收支只用于面板的 GJ/s，不向事件模拟中额外注入电量。
        let netUse = cycles.reduce(0.0) { $0 + ($1.need - $1.gain) / $1.averageInterval }
        let peak = recharge(capacity: capacity, time: input.rechargeTime, percent: 0.25)
        let delta = peak - netUse
        func result(_ stable: Bool, _ level: Double, _ time: Double, _ limited: Bool = false) -> Result {
            Result(isStable: stable, stableLevel: level, lastsTime: time, delta: delta, reachedLimit: limited)
        }
        guard capacity.isFinite, capacity > 0, input.rechargeTime.isFinite else { return result(false, 0, 0) }
        if cycles.allSatisfy({ $0.need == 0 }) {
            return result(true, 1, .infinity)
        }

        let maxTime = 8.0 * 3600
        let maxEvents = 100_000
        var cap = capacity
        var lastTime = 0.0
        var next = Array(repeating: 0.0, count: cycles.count)
        var referenceCap: Double?
        var shots = Array(repeating: 0, count: cycles.count)
        var minimumCap = capacity
        // 比较首次激活后的完整相位：下一次激活间隔和弹仓中的已用次数。
        let firstIntervals = cycles.map { $0.duration + ($0.shotsPerReload == 1 ? $0.reloadTime : 0) }
        let firstShots = cycles.map { $0.shotsPerReload > 1 ? 1 : 0 }
        for _ in 0 ..< maxEvents {
            let time = next.min()!
            if time > maxTime {
                return result(false, 0, maxTime, true)
            }
            let elapsed = time - lastTime
            if elapsed > 0 {
                if input.rechargeTime > 0 {
                    let root = 1 + (sqrt(max(0, cap / capacity)) - 1) * exp(-elapsed / (input.rechargeTime / 5))
                    cap = root * root * capacity
                }
                cap = min(capacity, max(0, cap))
            }
            lastTime = time

            // 同一时刻先合并补能并截断溢出，再合并扣电；不依赖装备数组顺序。
            // 所有启用模块从 t=0 连续运转，不自动择时注电或错开激活。
            var need = 0.0
            var gain = 0.0
            for index in cycles.indices where abs(next[index] - time) < 1e-8 {
                let cycle = cycles[index]
                need += cycle.need
                gain += cycle.gain
                next[index] += cycle.duration
                if cycle.shotsPerReload > 0 {
                    shots[index] += 1
                    if shots[index] == cycle.shotsPerReload {
                        shots[index] = 0
                        next[index] += cycle.reloadTime
                    }
                }
            }
            cap = min(capacity, cap + gain)
            if cap < need {
                return result(false, 0, time)
            }
            cap -= need
            minimumCap = min(minimumCap, cap)

            // 换弹也是相位的一部分，不能只在耗电模块的周期重合时宣告稳定。
            let repeatedPhase = next.indices.allSatisfy {
                abs((next[$0] - time) - firstIntervals[$0]) < 1e-7 && shots[$0] == firstShots[$0]
            }
            if repeatedPhase {
                if let previous = referenceCap, delta >= 0,
                   cap >= previous || abs(cap - previous) <= capacity * 1e-10
                {
                    // 脉冲补能会产生波动，显示最近一个完整重复周期内的电量低点。
                    return result(true, minimumCap / capacity, .infinity)
                }
                referenceCap = cap
                minimumCap = cap
            }
        }
        return result(false, 0, lastTime, true)
    }
}
