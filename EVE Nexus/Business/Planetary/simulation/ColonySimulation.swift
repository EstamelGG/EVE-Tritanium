import Foundation

/// 行星殖民地模拟
class ColonySimulation {
    /// 模拟进度回调类型
    /// - Parameter progress: 进度值（0.0 到 1.0）
    typealias SimulationProgressCallback = (Double) -> Void

    // MARK: - 类型别名

    typealias ItemType = Type

    // MARK: - 模拟结束条件

    /// 模拟结束条件
    enum SimulationEndCondition {
        /// 模拟到当前时间
        case untilNow
        /// 模拟到工作结束
        case untilWorkEnds
        /// 模拟到指定时间
        case untilTimestamp(Date)

        /// 获取模拟结束时间
        /// - Returns: 模拟结束时间
        func getSimEndTime() -> Date {
            switch self {
            case .untilNow:
                return Date()
            case .untilWorkEnds:
                // 使用一个很远的未来时间
                return Date(timeIntervalSince1970: Double.greatestFiniteMagnitude)
            case let .untilTimestamp(timestamp):
                return timestamp
            }
        }
    }

    // MARK: - 属性

    /// 模拟结束时间
    private static var simEndTime: Date?
    /// 当前正在模拟的殖民地引用，用于日志记录
    private static var colony: Colony?

    /// 每轮克隆后建立一次；字典仅用于查找，事件与路由仍按原数组顺序处理。
    private struct Lookup {
        var pins: [Int64: Pin] = [:]
        var incoming: [Int64: [Route]] = [:]
        var outgoing: [Int64: [Route]] = [:]
        var incomingByType: [Int64: [Int: [Route]]] = [:]
        var programs: [ObjectIdentifier: ExtractionSimulation.Program] = [:]

        init(colony: Colony) {
            for pin in colony.pins {
                // 与 first(where:) 一致，重复 ID 保留第一个设施。
                if pins[pin.id] == nil {
                    pins[pin.id] = pin
                }
                if let extractor = pin as? Pin.Extractor,
                   let baseValue = extractor.baseValue, let cycleTime = extractor.cycleTime
                {
                    programs[ObjectIdentifier(extractor)] = ExtractionSimulation.Program(
                        baseValue: baseValue, cycleDuration: cycleTime
                    )
                }
            }
            for route in colony.routes {
                incoming[route.destinationPinId, default: []].append(route)
                outgoing[route.sourcePinId, default: []].append(route)
                incomingByType[route.destinationPinId, default: [:]][route.type.id, default: []].append(route)
            }
        }
    }

    // MARK: - 公共方法

    /// 模拟殖民地
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - targetTime: 目标时间
    ///   - progressCallback: 可选的进度回调，参数为 (当前事件索引, 总事件数, 当前模拟时间)
    /// - Returns: 模拟后的殖民地
    static func simulate(colony: Colony, targetTime: Date, progressCallback: SimulationProgressCallback? = nil) -> Colony {
        // 克隆殖民地以避免修改原始数据
        var simulatedColony = colony.clone()

        // 如果目标时间早于当前模拟时间，直接返回
        if targetTime <= simulatedColony.currentSimTime {
            return simulatedColony
        }

        let lookup = Lookup(colony: simulatedColony)

        // 检查并处理已经在生产周期中的工厂
        for pin in simulatedColony.pins {
            if let factory = pin as? Pin.Factory,
               let lastCycleStartTime = factory.lastCycleStartTime,
               let schematic = factory.schematic,
               factory.isActive
            {
                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)

                // 如果生产周期在模拟开始前已经结束，但产品尚未被收集
                if cycleEndTime <= simulatedColony.currentSimTime {
                    // 添加产出
                    let outputType = schematic.outputType
                    let outputQuantity = schematic.outputQuantity
                    let currentOutputQuantity = factory.contents[outputType] ?? 0
                    factory.contents[outputType] = currentOutputQuantity + outputQuantity

                    // 更新容量使用情况
                    factory.capacityUsed += outputType.volume * Double(outputQuantity)

                    // 清除上一个周期的开始时间，表示已经完成了这个周期
                    factory.lastCycleStartTime = nil

                    // 处理产出的路由
                    // 注意：这里使用临时事件队列，因为这是在初始化事件队列之前调用的
                    var tempEventQueue: [(date: Date, pinId: Int64)] = []
                    let products = [outputType: outputQuantity]
                    routeCommodityOutput(
                        lookup: lookup,
                        colony: simulatedColony, sourcePin: factory, commodities: products,
                        currentTime: simulatedColony.currentSimTime, eventQueue: &tempEventQueue
                    )
                }
            }
        }

        // 创建局部事件队列，避免并发冲突
        var eventQueue: [(date: Date, pinId: Int64)] = []
        // 初始化事件队列 - 使用targetTime而不是.untilNow，确保未来模拟正确
        initializeSimulation(colony: simulatedColony, endCondition: .untilTimestamp(targetTime), eventQueue: &eventQueue)
        simEndTime = nil

        // 运行事件驱动的模拟
        let startTime = simulatedColony.currentSimTime
        runEventDrivenSimulation(
            lookup: lookup,
            colony: &simulatedColony, targetTime: targetTime, startTime: startTime,
            eventQueue: &eventQueue, progressCallback: progressCallback
        )

        // 更新设施状态
        updatePinStatuses(colony: simulatedColony)

        // 更新殖民地状态
        simulatedColony.status = getColonyStatus(pins: simulatedColony.pins)

        // 更新殖民地概览
        simulatedColony.overview = getColonyOverview(
            routes: simulatedColony.routes, pins: simulatedColony.pins
        )

        return simulatedColony
    }

    // MARK: - 私有方法

    /// 检查殖民地是否处于工作状态
    /// - Parameters:
    ///   - pins: 设施列表
    ///   - currentSimTime: 当前模拟时间（用于检查提取器是否过期）
    /// - Returns: 是否处于工作状态
    /// 逻辑：
    /// 1. 首先检查是否有提取器存在
    /// 2. 如果有提取器，检查是否有活跃的提取器（且未过期）
    ///    - 如果有活跃的提取器，返回 true
    ///    - 如果没有活跃的提取器，继续检查工厂
    /// 3. 如果没有提取器，跳过提取器检查，直接检查工厂
    /// 4. 检查工厂：
    ///    - 如果工厂正在生产，返回 true
    ///    - 如果工厂有足够的输入材料，返回 true
    ///    - 如果工厂没有足够的输入材料，返回 false（停工）
    /// 5. 仓储类设施完全不需要考虑
    private static func isColonyWorking(pins: [Pin], currentSimTime: Date) -> Bool {
        // 首先检查是否有提取器存在
        var hasExtractor = false
        var hasActiveExtractor = false

        for pin in pins {
            if let extractor = pin as? Pin.Extractor {
                hasExtractor = true
                if extractor.isActive {
                    // 检查是否已过期
                    if let expiryTime = extractor.expiryTime {
                        if expiryTime > currentSimTime {
                            // 提取器活跃且未过期
                            hasActiveExtractor = true
                            break
                        }
                    } else {
                        // 没有过期时间，认为提取器还在工作
                        hasActiveExtractor = true
                        break
                    }
                }
            }
        }

        // 如果有提取器且存在活跃的提取器，返回 true
        if hasExtractor && hasActiveExtractor {
            return true
        }

        // 如果没有提取器，或者有提取器但没有活跃的提取器，检查工厂状态
        for pin in pins {
            if let factory = pin as? Pin.Factory {
                // 如果工厂正在生产，返回 true
                if factory.isActive {
                    return true
                }
                // 如果工厂有足够的输入材料，返回 true
                if factory.hasEnoughInputs() {
                    return true
                }
            }
        }

        // 如果工厂也没有足够的输入材料，返回 false（停工）
        return false
    }

    /// 检查殖民地是否还在工作（公开方法，用于快照生成）
    /// - Parameter colony: 殖民地
    /// - Returns: 是否还在工作
    /// 逻辑：
    /// 1. 首先检查是否有提取器存在
    /// 2. 如果有提取器，检查是否有活跃的提取器（且未过期）
    ///    - 如果有活跃的提取器，继续检查工厂（因为提取器在工作）
    ///    - 如果没有活跃的提取器，继续检查工厂
    /// 3. 如果没有提取器，跳过提取器检查，直接检查工厂
    /// 4. 检查工厂：
    ///    - 如果工厂正在生产或有材料可以生产，返回 true
    ///    - 否则返回 false
    static func isColonyStillWorking(colony: Colony) -> Bool {
        let currentTime = colony.currentSimTime

        // 检查是否有活跃的提取器
        var hasActiveExtractor = false

        for pin in colony.pins {
            if let extractor = pin as? Pin.Extractor {
                if extractor.isActive {
                    // 检查是否已过期
                    if let expiryTime = extractor.expiryTime {
                        // 如果过期时间已过，认为提取器已停工
                        if expiryTime > currentTime {
                            hasActiveExtractor = true
                            break
                        }
                    } else {
                        // 如果没有过期时间，认为提取器还在工作
                        hasActiveExtractor = true
                        break
                    }
                }
            }
        }

        // 如果有提取器且存在活跃的提取器，继续检查工厂（因为提取器在工作）
        // 如果没有提取器，或者有提取器但没有活跃的提取器，也继续检查工厂

        // 检查工厂
        for pin in colony.pins {
            if let factory = pin as? Pin.Factory {
                // 工厂正在生产或有材料可以生产
                if factory.isActive || factory.hasEnoughInputs() {
                    return true
                }
            }
        }

        // 如果有活跃的提取器，即使工厂暂时没有材料，也认为还在工作
        // 因为提取器可能会继续产出资源
        if hasActiveExtractor {
            return true
        }

        // 如果没有提取器，且工厂也没有材料，返回 false（停工）
        // 如果有提取器但没有活跃的提取器，且工厂也没有材料，返回 false（停工）
        return false
    }

    /// 获取设施的下一个运行时间
    /// - Parameter pin: 设施
    /// - Returns: 下一个运行时间
    private static func getNextRunTime(pin: Pin) -> Date? {
        if let extractor = pin as? Pin.Extractor {
            if extractor.isActive, let lastRunTime = extractor.lastRunTime,
               let cycleTime = extractor.cycleTime
            {
                return lastRunTime.addingTimeInterval(cycleTime)
            }
        } else if let factory = pin as? Pin.Factory {
            // 关键修复：优先检查工厂是否正在生产中（isActive && lastCycleStartTime）
            // 只有在工厂真正处于激活状态时，才使用lastCycleStartTime
            if factory.isActive, let lastCycleStartTime = factory.lastCycleStartTime,
               let schematic = factory.schematic
            {
                return lastCycleStartTime.addingTimeInterval(schematic.cycleTime)
            }

            // 如果工厂不活跃但有足够的输入材料，返回nil表示立即运行
            if !factory.isActive && hasEnoughInputs(factory: factory) {
                return nil
            }

            // 如果工厂收到了输入但材料不足，使用正常的周期时间
            if (factory.hasReceivedInputs || factory.receivedInputsLastCycle)
                && !hasEnoughInputs(factory: factory)
            {
                if let lastRunTime = factory.lastRunTime, let schematic = factory.schematic {
                    return lastRunTime.addingTimeInterval(schematic.cycleTime)
                }
            }

            // 关键修复：如果工厂有lastRunTime，始终返回lastRunTime + cycleTime
            // 这确保工厂完成周期后，即使没有足够的材料，也会在正确的周期时间被调度
            // 而不是返回nil导致被安排在当前时间+1秒
            // 注意：这里不检查lastCycleStartTime，因为工厂完成周期后，lastCycleStartTime可能还存在但工厂已经不活跃了
            if let lastRunTime = factory.lastRunTime, let schematic = factory.schematic {
                return lastRunTime.addingTimeInterval(schematic.cycleTime)
            }
        }

        return nil
    }

    /// 初始化模拟事件队列
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - endCondition: 模拟结束条件
    ///   - eventQueue: 事件队列（inout参数）
    private static func initializeSimulation(colony: Colony, endCondition: SimulationEndCondition, eventQueue: inout [(date: Date, pinId: Int64)]) {
        // 清空事件队列
        eventQueue.removeAll()

        // 为每个可运行的设施安排事件
        for pin in colony.pins {
            // 跳过存储类设施
            if isStorage(pin: pin) {
                continue
            }

            // 特别处理正在生产中的工厂
            if let factory = pin as? Pin.Factory,
               let lastCycleStartTime = factory.lastCycleStartTime,
               let schematic = factory.schematic,
               factory.isActive
            {
                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)

                // 如果生产周期尚未结束，直接将其添加到事件队列
                if cycleEndTime > colony.currentSimTime {
                    eventQueue.append((cycleEndTime, factory.id))
                    continue
                }
            }

            // 处理其他可运行的设施
            if canRun(pin: pin, time: endCondition.getSimEndTime()) {
                schedulePin(pin: pin, currentTime: colony.currentSimTime, eventQueue: &eventQueue)
            }
        }

        // 按时间排序事件队列
        sortEventQueue(&eventQueue)
    }

    /// 按日期与 pinId 对事件队列排序
    private static func sortEventQueue(_ queue: inout [(date: Date, pinId: Int64)]) {
        queue.sort { event1, event2 in
            if event1.date == event2.date {
                return event1.pinId < event2.pinId
            }
            return event1.date < event2.date
        }
    }

    /// 运行事件驱动的模拟
    /// - Parameters:
    ///   - colony: 殖民地引用
    ///   - targetTime: 目标时间
    ///   - startTime: 模拟开始时间
    ///   - eventQueue: 事件队列（inout参数）
    ///   - progressCallback: 可选的进度回调
    private static func runEventDrivenSimulation(lookup: Lookup, colony: inout Colony, targetTime: Date, startTime: Date, eventQueue: inout [(date: Date, pinId: Int64)], progressCallback: SimulationProgressCallback?) {
        // 保存当前模拟时间
        var currentSimTime = colony.currentSimTime

        // 设置当前模拟的殖民地引用，用于日志记录
        self.colony = colony

        // 进度跟踪变量（每次模拟开始时重置）
        var lastReportedProgress: Double = -1.0
        var eventCount = 0
        let totalTime = targetTime.timeIntervalSince(startTime)

        // 检查事件队列
        if eventQueue.isEmpty {
            // 更新殖民地的当前模拟时间
            colony.currentSimTime = targetTime
            return
        }

        // 循环处理事件队列
        while !eventQueue.isEmpty {
            // 获取并移除队列中的第一个事件
            let event = eventQueue.removeFirst()
            let eventTime = event.date
            let pinId = event.pinId

            // 检查模拟结束条件
            // 1. 如果已设置模拟结束时间且事件时间超过结束时间，结束模拟
            if let endTime = simEndTime, eventTime > endTime {
                break
            }

            // 2. 如果事件时间超过目标时间，结束模拟
            if eventTime > targetTime {
                break
            }

            // 更新当前模拟时间
            currentSimTime = eventTime
            colony.currentSimTime = currentSimTime

            // 计算并报告进度（每处理一定数量的事件或进度有明显变化时报告）
            if let progressCallback = progressCallback {
                if totalTime > 0 {
                    let elapsedTime = currentSimTime.timeIntervalSince(startTime)
                    let progress = min(max(elapsedTime / totalTime, 0.0), 1.0)
                    eventCount += 1
                    // 每处理100个事件或进度变化超过1%时报告一次
                    if eventCount % 100 == 0 || abs(progress - lastReportedProgress) >= 0.01 || progress >= 1.0 {
                        progressCallback(progress)
                        lastReportedProgress = progress
                    }
                }
            }

            // 获取要处理的设施
            guard let pin = lookup.pins[pinId] else {
                continue
            }

            // 检查设施是否可以激活或已经激活，如果都不是，则检查是否是工厂且有足够的输入材料
            if !canActivate(pin: pin), !isActive(pin: pin) {
                // 特殊处理工厂：如果是工厂且有足够的输入材料，即使canActivate返回false也应该继续处理
                if let factory = pin as? Pin.Factory, hasEnoughInputs(factory: factory) {
                    // 继续处理，不跳过
                } else {
                    continue
                }
            }

            // 如果设施可以运行，处理该设施
            if canRun(pin: pin, time: targetTime) {
                // 1. 先运行设施并获取产出的资源
                let commodities = run(lookup: lookup, pin: pin, time: currentSimTime, eventQueue: &eventQueue)

                // 2. 如果设施是消费者，然后处理输入路由
                if isConsumer(pin: pin) {
                    routeCommodityInput(
                        lookup: lookup,
                        colony: colony, destinationPin: pin, currentTime: currentSimTime, eventQueue: &eventQueue
                    )
                }

                // 3. 如果设施可以激活或处于活跃状态，安排下一次运行
                if isActive(pin: pin) || canActivate(pin: pin) {
                    schedulePin(pin: pin, currentTime: currentSimTime, eventQueue: &eventQueue)
                }

                // 4. 如果设施产出了资源，处理输出路由
                if !commodities.isEmpty {
                    routeCommodityOutput(
                        lookup: lookup,
                        colony: colony, sourcePin: pin, commodities: commodities,
                        currentTime: currentSimTime, eventQueue: &eventQueue
                    )
                }
            } else {
                // 如果设施不能运行，但可以激活，仍然需要安排下一次运行，避免无限循环
                // 这通常发生在工厂尚未到达下一个生产周期的情况
                if canActivate(pin: pin) || isActive(pin: pin) {
                    schedulePin(pin: pin, currentTime: currentSimTime, eventQueue: &eventQueue)
                }
            }

            // 检查是否需要更新模拟结束时间（针对"直到工作结束"的模拟）
            if targetTime == SimulationEndCondition.untilWorkEnds.getSimEndTime(),
               simEndTime == nil
            {
                // 获取殖民地当前状态
                updatePinStatuses(colony: colony)
                let isWorking = isColonyWorking(pins: colony.pins, currentSimTime: currentSimTime)

                // 如果已经不在工作，设置模拟结束时间
                if !isWorking {
                    simEndTime = currentSimTime
                }
            } else {
                // 对于普通模拟（模拟到指定时间），也应该检查停工状态
                // 如果殖民地已经停工，提前结束模拟以避免不必要的计算
                // 使用与"模拟到未来"相同的判断逻辑
                // 每处理一定数量的事件后检查一次，避免频繁检查影响性能
                if eventCount % 50 == 0 {
                    updatePinStatuses(colony: colony)
                    let isWorking = isColonyWorking(pins: colony.pins, currentSimTime: currentSimTime)

                    // 如果已经不在工作，设置模拟结束时间并提前结束
                    if !isWorking {
                        simEndTime = currentSimTime
                        break
                    }
                }
            }
        }

        // 更新殖民地的当前模拟时间
        colony.currentSimTime = simEndTime ?? targetTime
        if colony.currentSimTime > targetTime {
            colony.currentSimTime = targetTime
        }

        // 模拟完成，报告100%进度
        if let progressCallback = progressCallback {
            progressCallback(1.0)
        }

        // 这个检查作为额外的安全措施，确保所有有足够材料的工厂都能开始生产
        for pin in colony.pins {
            if let factory = pin as? Pin.Factory,
               !factory.isActive,
               factory.schematic != nil,
               hasEnoughInputs(factory: factory)
            {
                // 立即运行工厂，开始生产周期
                // 注意：这里需要创建一个临时事件队列，因为这是在模拟结束后调用的
                var tempEventQueue: [(date: Date, pinId: Int64)] = []
                _ = runFactory(lookup: lookup, factory: factory, time: colony.currentSimTime, eventQueue: &tempEventQueue)
            }
        }

        // 清除当前模拟的殖民地引用
        self.colony = nil
    }

    /// 运行设施
    /// - Parameters:
    ///   - pin: 设施
    ///   - time: 当前时间
    ///   - eventQueue: 事件队列（inout参数）
    /// - Returns: 产出的资源
    private static func run(lookup: Lookup, pin: Pin, time: Date, eventQueue: inout [(date: Date, pinId: Int64)]) -> [ItemType: Int64] {
        var products: [ItemType: Int64] = [:]

        if let extractor = pin as? Pin.Extractor {
            runExtractor(lookup: lookup, extractor: extractor, time: time)

            // 收集提取器产出的资源
            if let productType = extractor.productType, extractor.isActive {
                let output = extractor.contents[productType] ?? 0
                if output > 0 {
                    products[productType] = output

                    // 清空提取器的存储，因为产出的资源会被路由
                    extractor.contents.removeValue(forKey: productType)
                    extractor.capacityUsed = 0
                }
            }
        } else if let factory = pin as? Pin.Factory {
            // 运行工厂并获取生产状态
            let productionStatus = runFactory(lookup: lookup, factory: factory, time: time, eventQueue: &eventQueue)

            // 只有当工厂完成了一个生产周期时，才收集产出
            if productionStatus == .completedCycle, let schematic = factory.schematic {
                // 移除对factory.isActive的检查，确保产出能被收集
                products[schematic.outputType] = schematic.outputQuantity

                // 清空工厂的产出存储，因为产出的资源会被路由
                factory.contents.removeValue(forKey: schematic.outputType)
                factory.capacityUsed -=
                    schematic.outputType.volume * Double(schematic.outputQuantity)
            }
        }

        return products
    }

    /// 运行提取器
    /// - Parameters:
    ///   - extractor: 提取器
    ///   - time: 当前时间
    private static func runExtractor(lookup: Lookup, extractor: Pin.Extractor, time: Date) {
        guard let productType = extractor.productType,
              let baseValue = extractor.baseValue,
              let installTime = extractor.installTime,
              let cycleTime = extractor.cycleTime
        else {
            return
        }

        // 计算产量
        let program = lookup.programs[ObjectIdentifier(extractor)]
            ?? ExtractionSimulation.Program(baseValue: baseValue, cycleDuration: cycleTime)
        let output = program.output(startTime: installTime, currentTime: time)

        // 将产出的资源添加到存储中
        let currentQuantity = extractor.contents[productType] ?? 0
        extractor.contents[productType] = currentQuantity + output

        // 更新容量使用情况
        extractor.capacityUsed += productType.volume * Double(output)

        // 更新运行时间
        extractor.lastRunTime = time

        // 检查是否过期
        if let expiryTime = extractor.expiryTime, expiryTime <= time {
            extractor.isActive = false
        }
    }

    /// 工厂生产状态
    enum FactoryProductionStatus {
        /// 未生产（缺少材料或配方）
        case notProduced
        /// 开始新的生产周期
        case startedCycle
        /// 完成生产周期
        case completedCycle
    }

    /// 运行工厂
    /// - Parameters:
    ///   - factory: 工厂
    ///   - time: 当前时间
    ///   - eventQueue: 事件队列（inout参数）
    /// - Returns: 工厂生产状态
    private static func runFactory(lookup: Lookup, factory: Pin.Factory, time: Date, eventQueue: inout [(date: Date, pinId: Int64)]) -> FactoryProductionStatus {
        // 首先检查是否有配方
        guard let schematic = factory.schematic else {
            return .notProduced
        }

        // 检查是否有上一个生产周期的产品需要输出
        if let lastCycleStartTime = factory.lastCycleStartTime, factory.isActive {
            let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)

            // 如果当前时间已经达到或超过了周期结束时间，则完成生产周期
            if time >= cycleEndTime {
                // 添加产出
                let outputType = schematic.outputType
                let outputQuantity = schematic.outputQuantity
                let currentOutputQuantity = factory.contents[outputType] ?? 0
                factory.contents[outputType] = currentOutputQuantity + outputQuantity

                // 更新容量使用情况
                factory.capacityUsed += outputType.volume * Double(outputQuantity)

                // 清除上一个周期的开始时间，表示已经完成了这个周期
                factory.lastCycleStartTime = nil
                factory.isActive = false
                factory.lastRunTime = time

                // 工厂完成周期后，尝试从仓储设施重新填充其缓冲区
                refillFactoryBuffer(lookup: lookup, factory: factory, time: time, eventQueue: &eventQueue)

                if hasEnoughInputs(factory: factory) {
                    // 立即开始新的生产周期
                    factory.isActive = true
                    factory.lastCycleStartTime = time

                    // 消耗输入材料
                    for (inputType, requiredQuantity) in schematic.inputs {
                        let currentQuantity = factory.contents[inputType] ?? 0
                        factory.contents[inputType] = currentQuantity - requiredQuantity
                        factory.capacityUsed -= inputType.volume * Double(requiredQuantity)
                    }

                    // 更新运行时间和输入状态
                    factory.lastRunTime = time
                    factory.receivedInputsLastCycle = factory.hasReceivedInputs
                    factory.hasReceivedInputs = false

                    // 继续尝试填充缓冲区
                    refillFactoryBuffer(lookup: lookup, factory: factory, time: time, eventQueue: &eventQueue)
                }

                // 返回completedCycle，让run函数收集产出
                return .completedCycle
            }

            // 当前时间还未到达周期结束时间，继续等待
            return .startedCycle
        }

        // 检查是否在生产周期内
        if let lastRunTime = factory.lastRunTime {
            let nextRunTime = lastRunTime.addingTimeInterval(schematic.cycleTime)
            // 特殊处理：如果工厂有足够的输入材料，允许立即开始新的生产周期，不受上一次运行时间的限制
            if time < nextRunTime && !hasEnoughInputs(factory: factory) {
                return .notProduced
            }
        }

        // 检查是否有足够的输入材料
        var canConsume = true
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            if availableQuantity < requiredQuantity {
                canConsume = false
                break
            }
        }

        if canConsume {
            // 消耗输入材料
            for (inputType, requiredQuantity) in schematic.inputs {
                let currentQuantity = factory.contents[inputType] ?? 0
                factory.contents[inputType] = currentQuantity - requiredQuantity

                // 更新容量使用情况
                factory.capacityUsed -= inputType.volume * Double(requiredQuantity)
            }

            // 更新状态
            factory.isActive = true
            factory.lastCycleStartTime = time

            // 更新运行时间和输入状态
            factory.lastRunTime = time
            factory.receivedInputsLastCycle = factory.hasReceivedInputs
            factory.hasReceivedInputs = false

            // 工厂开始生产后，尝试从仓储设施重新填充其缓冲区
            refillFactoryBuffer(lookup: lookup, factory: factory, time: time, eventQueue: &eventQueue)

            return .startedCycle // 开始新的生产周期
        } else {
            factory.isActive = false
            factory.lastRunTime = time
            factory.receivedInputsLastCycle = factory.hasReceivedInputs
            factory.hasReceivedInputs = false

            return .notProduced
        }
    }

    /// 安排设施的下一次运行
    /// - Parameters:
    ///   - pin: 设施
    ///   - currentTime: 当前时间
    private static func schedulePin(pin: Pin, currentTime: Date, eventQueue: inout [(date: Date, pinId: Int64)]) {
        // 获取下一次运行时间
        let nextRunTime = getNextRunTime(pin: pin)

        // 添加检查：如果是工厂且没有足够的输入材料，确保不会在当前时间点调度
        if let factory = pin as? Pin.Factory,
           !hasEnoughInputs(factory: factory),
           factory.hasReceivedInputs || factory.receivedInputsLastCycle
        {
            // 使用lastRunTime + cycleTime作为下一次运行时间
            if let lastRunTime = factory.lastRunTime, let schematic = factory.schematic {
                let nextTime = lastRunTime.addingTimeInterval(schematic.cycleTime)

                // 检查是否已经在队列中
                if let index = eventQueue.firstIndex(where: { $0.pinId == pin.id }) {
                    // 如果新的运行时间更早，则更新事件
                    if nextTime < eventQueue[index].date {
                        eventQueue.remove(at: index)
                        eventQueue.append((nextTime, pin.id))
                        // 重新排序队列
                        sortEventQueue(&eventQueue)
                    }
                } else {
                    // 添加新事件到队列
                    eventQueue.append((nextTime, pin.id))
                    // 重新排序队列
                    sortEventQueue(&eventQueue)
                }

                return
            }
        }

        // 计算调度时间
        let scheduleTime: Date
        if let nextRunTime = nextRunTime {
            // 如果nextRunTime是未来的时间，使用它
            if nextRunTime > currentTime {
                scheduleTime = nextRunTime
            } else {
                // 如果nextRunTime已经过去了，至少安排在当前时间之后1秒，避免无限循环
                scheduleTime = currentTime.addingTimeInterval(1.0)
            }
        } else {
            // 如果nextRunTime为nil，表示立即运行，但至少安排在当前时间之后1秒，避免无限循环
            scheduleTime = currentTime.addingTimeInterval(1.0)
        }

        // 检查是否已经在队列中
        if let index = eventQueue.firstIndex(where: { $0.pinId == pin.id }) {
            // 如果新的运行时间更早，则更新事件
            if scheduleTime < eventQueue[index].date {
                eventQueue.remove(at: index)
                eventQueue.append((scheduleTime, pin.id))
                // 重新排序队列
                sortEventQueue(&eventQueue)
            } else if scheduleTime > eventQueue[index].date {
                // 如果新的运行时间更晚，也更新事件（避免使用过时的时间）
                eventQueue.remove(at: index)
                eventQueue.append((scheduleTime, pin.id))
                // 重新排序队列
                sortEventQueue(&eventQueue)
            }
            // 如果时间相同，不需要更新
        } else {
            // 添加新事件到队列
            eventQueue.append((scheduleTime, pin.id))
            // 重新排序队列
            sortEventQueue(&eventQueue)
        }
    }

    /// 检查设施是否可以运行
    /// - Parameters:
    ///   - pin: 设施
    ///   - time: 当前时间
    /// - Returns: 是否可以运行
    private static func canRun(pin: Pin, time: Date) -> Bool {
        // 存储类设施不需要运行
        if isStorage(pin: pin) {
            return false
        }

        // 首先检查设施是否可以激活或已经激活
        if !canActivate(pin: pin) && !isActive(pin: pin) {
            // 特殊处理工厂：如果是工厂且有足够的输入材料，即使canActivate返回false也应该继续处理
            if let factory = pin as? Pin.Factory, hasEnoughInputs(factory: factory) {
                // 继续处理，不返回false
            } else {
                return false
            }
        }

        // 获取下一次运行时间
        let nextRunTime = getNextRunTime(pin: pin)

        // 如果是工厂且收到了输入但材料不足，确保不会在当前时间点运行
        if let factory = pin as? Pin.Factory,
           (factory.hasReceivedInputs || factory.receivedInputsLastCycle)
           && !hasEnoughInputs(factory: factory)
        {
            // 只有当下一次运行时间小于等于当前时间时才运行
            return nextRunTime != nil && nextRunTime! <= time
        }

        // 如果没有下一次运行时间或者下一次运行时间小于等于当前时间，则可以运行
        return nextRunTime == nil || nextRunTime! <= time
    }

    /// 检查设施是否可以激活
    /// - Parameter pin: 设施
    /// - Returns: 是否可以激活
    private static func canActivate(pin: Pin) -> Bool {
        if let extractor = pin as? Pin.Extractor {
            // 提取器需要是激活状态并且有产品类型
            if !extractor.isActive {
                return false
            }
            return extractor.productType != nil
        } else if let factory = pin as? Pin.Factory {
            // 工厂需要有配方
            if factory.schematic == nil {
                return false
            }

            // 如果已经激活，返回true
            if isActive(pin: factory) {
                return true
            }

            // 如果工厂收到了输入（不管材料是否足够），返回true
            if factory.hasReceivedInputs || factory.receivedInputsLastCycle {
                return true
            }

            // 关键：如果工厂有足够材料，返回false
            // 这看起来反直觉，但配合getNextRunTime是正确的：
            // getNextRunTime会对有足够材料的未激活工厂返回nil（立即运行）
            if hasEnoughInputs(factory: factory) {
                return false
            }
        }
        // 这对于刚初始化的工厂很重要
        return true
    }

    /// 检查设施是否处于激活状态
    /// - Parameter pin: 设施
    /// - Returns: 是否处于激活状态
    private static func isActive(pin: Pin) -> Bool {
        if let extractor = pin as? Pin.Extractor {
            return extractor.productType != nil && extractor.isActive
        } else if let factory = pin as? Pin.Factory {
            return factory.isActive
        } else {
            // 存储类设施默认是激活的
            return pin.isActive
        }
    }

    /// 检查设施是否为消费者
    /// - Parameter pin: 设施
    /// - Returns: 是否为消费者
    private static func isConsumer(pin: Pin) -> Bool {
        return pin is Pin.Factory
    }

    /// 检查设施是否为存储设施
    /// - Parameter pin: 设施
    /// - Returns: 是否为存储设施
    private static func isStorage(pin: Pin) -> Bool {
        return pin is Pin.Storage || pin is Pin.Launchpad || pin is Pin.CommandCenter
    }

    /// 获取设施的剩余容量
    /// - Parameter pin: 设施
    /// - Returns: 剩余容量
    private static func getCapacityRemaining(pin: Pin) -> Double {
        var totalCapacity: Double = 0

        if let capacity = getCapacity(for: pin) {
            totalCapacity = Double(capacity)
        }

        return max(0, totalCapacity - pin.capacityUsed)
    }

    /// 获取工厂的输入缓冲区状态
    /// - Parameter factory: 工厂
    /// - Returns: 输入缓冲区状态（0-1之间的浮点数，0表示满，1表示空）
    private static func getInputBufferState(factory: Pin.Factory) -> Double {
        guard let schematic = factory.schematic else {
            return 1.0
        }

        var productsRatio = 0.0
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            productsRatio += Double(availableQuantity) / Double(requiredQuantity)
        }

        // 如果没有输入材料，返回1.0（完全空）
        if schematic.inputs.isEmpty {
            return 1.0
        }

        // 返回空闲比例（1 - 填充比例）
        return 1.0 - productsRatio / Double(schematic.inputs.count)
    }

    /// 检查工厂是否有足够的输入材料
    /// - Parameter factory: 工厂
    /// - Returns: 是否有足够的输入材料
    private static func hasEnoughInputs(factory: Pin.Factory) -> Bool {
        guard let schematic = factory.schematic else {
            return false
        }

        // 检查每种输入材料是否足够
        for (inputType, requiredQuantity) in schematic.inputs {
            let availableQuantity = factory.contents[inputType] ?? 0
            if availableQuantity < requiredQuantity {
                return false
            }
        }

        return true
    }

    /// 处理设施的输入资源路由
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - destinationPin: 目标设施
    ///   - currentTime: 当前模拟时间
    ///   - eventQueue: 事件队列（inout参数）
    private static func routeCommodityInput(lookup: Lookup, colony _: Colony, destinationPin: Pin, currentTime: Date, eventQueue: inout [(date: Date, pinId: Int64)]) {
        // 获取以该设施为目标的所有路由
        let routesToEvaluate = lookup.incoming[destinationPin.id] ?? []

        // 记录接收资源的设施和数量
        var pinsReceivingCommodities: [Int64: [ItemType: Int64]] = [:]

        for route in routesToEvaluate {
            // 获取源设施
            guard let sourcePin = lookup.pins[route.sourcePinId] else {
                continue
            }

            // 仅处理存储设施作为源的路由
            if !isStorage(pin: sourcePin) {
                continue
            }

            // 获取存储的资源
            let storedCommodities = sourcePin.contents
            if storedCommodities.isEmpty {
                continue
            }

            // 执行路由
            let (type, transferredQuantity) = transferCommodities(
                sourcePin: sourcePin,
                destinationPin: destinationPin,
                type: route.type,
                quantity: route.quantity,
                commodities: storedCommodities,
                currentTime: currentTime
            )

            // 如果转移了资源，更新接收记录
            if let type = type, transferredQuantity > 0 {
                // 更新接收记录
                if !pinsReceivingCommodities.keys.contains(destinationPin.id) {
                    pinsReceivingCommodities[destinationPin.id] = [:]
                }

                pinsReceivingCommodities[destinationPin.id]![type] =
                    (pinsReceivingCommodities[destinationPin.id]![type] ?? 0) + transferredQuantity
            }
        }

        // 处理接收到资源的设施
        for (receivingPinId, _) in pinsReceivingCommodities {
            guard let receivingPin = lookup.pins[receivingPinId] else {
                continue
            }

            // 如果接收者是消费者，安排其运行
            if isConsumer(pin: receivingPin) {
                schedulePin(pin: receivingPin, currentTime: currentTime, eventQueue: &eventQueue)
            }
        }
    }

    /// 处理设施的输出资源路由
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - sourcePin: 源设施
    ///   - commodities: 要路由的资源
    ///   - currentTime: 当前模拟时间
    ///   - eventQueue: 事件队列（inout参数）
    private static func routeCommodityOutput(lookup: Lookup,
                                             colony: Colony, sourcePin: Pin, commodities: [ItemType: Int64], currentTime: Date, eventQueue: inout [(date: Date, pinId: Int64)])
    {
        // 记录接收资源的设施和数量
        var pinsReceivingCommodities: [Int64: [ItemType: Int64]] = [:]

        // 创建可变的资源副本
        var remainingCommodities = commodities

        // 获取并排序路由
        var (processorRoutes, storageRoutes) = getSortedRoutesForPin(lookup: lookup,
                                                                     colony: colony, pinId: sourcePin.id, commodities: commodities)

        // 优先处理处理器路由（工厂优先）
        var done = false

        // 首先处理处理器路由
        while !processorRoutes.isEmpty, !done {
            let route = processorRoutes.removeFirst()

            guard let destinationPin = lookup.pins[route.destinationId]
            else {
                continue
            }

            let (type, transferredQuantity) = transferCommodities(
                sourcePin: sourcePin,
                destinationPin: destinationPin,
                type: route.commodityType,
                quantity: route.quantity,
                commodities: remainingCommodities,
                currentTime: currentTime
            )

            // 更新剩余资源和接收记录
            updateCommoditiesAfterTransfer(
                type: type,
                transferredQuantity: transferredQuantity,
                remainingCommodities: &remainingCommodities,
                pinsReceivingCommodities: &pinsReceivingCommodities,
                destinationId: route.destinationId
            )

            // 如果所有资源都已路由，结束处理
            if remainingCommodities.isEmpty {
                done = true
                break
            }
        }

        // 然后处理存储路由
        while !storageRoutes.isEmpty, !done {
            let route = storageRoutes.removeFirst()

            guard let destinationPin = lookup.pins[route.destinationId]
            else {
                continue
            }

            // 为存储路由计算最大转移量（平均分配）
            var maxAmount: Int64 = 0
            if remainingCommodities.count > 0 {
                let commodity = route.commodityType
                let remaining = remainingCommodities[commodity] ?? 0
                maxAmount = Int64(ceil(Double(remaining) / Double(storageRoutes.count + 1)))
            }

            let (type, transferredQuantity) = transferCommodities(
                sourcePin: sourcePin,
                destinationPin: destinationPin,
                type: route.commodityType,
                quantity: route.quantity,
                commodities: remainingCommodities,
                maxAmount: maxAmount,
                currentTime: currentTime
            )

            // 更新剩余资源和接收记录
            updateCommoditiesAfterTransfer(
                type: type,
                transferredQuantity: transferredQuantity,
                remainingCommodities: &remainingCommodities,
                pinsReceivingCommodities: &pinsReceivingCommodities,
                destinationId: route.destinationId
            )

            // 如果所有资源都已路由，结束处理
            if remainingCommodities.isEmpty {
                done = true
                break
            }
        }

        // 处理接收到资源的设施
        for (receivingPinId, commoditiesAdded) in pinsReceivingCommodities {
            guard let receivingPin = lookup.pins[receivingPinId] else {
                continue
            }

            // 如果接收者是消费者，安排其运行
            if isConsumer(pin: receivingPin) {
                schedulePin(pin: receivingPin, currentTime: currentTime, eventQueue: &eventQueue)
            }

            // 如果源不是存储设施但接收者是存储设施，继续路由输出
            if !isStorage(pin: sourcePin), isStorage(pin: receivingPin),
               !commoditiesAdded.isEmpty
            {
                routeCommodityOutput(
                    lookup: lookup,
                    colony: colony, sourcePin: receivingPin, commodities: commoditiesAdded,
                    currentTime: currentTime, eventQueue: &eventQueue
                )
            }
        }
    }

    /// 更新资源转移后的状态
    /// - Parameters:
    ///   - type: 资源类型
    ///   - transferredQuantity: 转移数量
    ///   - remainingCommodities: 剩余资源
    ///   - pinsReceivingCommodities: 接收记录
    ///   - destinationId: 目标设施ID
    private static func updateCommoditiesAfterTransfer(
        type: ItemType?,
        transferredQuantity: Int64,
        remainingCommodities: inout [ItemType: Int64],
        pinsReceivingCommodities: inout [Int64: [ItemType: Int64]],
        destinationId: Int64
    ) {
        guard let type = type, transferredQuantity > 0 else {
            return
        }

        // 更新剩余资源
        if let remaining = remainingCommodities[type] {
            let newRemaining = remaining - transferredQuantity
            if newRemaining <= 0 {
                remainingCommodities.removeValue(forKey: type)
            } else {
                remainingCommodities[type] = newRemaining
            }
        }

        // 更新接收记录
        if !pinsReceivingCommodities.keys.contains(destinationId) {
            pinsReceivingCommodities[destinationId] = [:]
        }

        pinsReceivingCommodities[destinationId]![type] =
            (pinsReceivingCommodities[destinationId]![type] ?? 0) + transferredQuantity
    }

    /// 获取排序后的路由
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - pinId: 设施ID
    ///   - commodities: 资源
    /// - Returns: 处理器路由和存储路由的元组
    private static func getSortedRoutesForPin(lookup: Lookup,
                                              colony _: Colony, pinId: Int64, commodities: [ItemType: Int64]) -> (
        [(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)],
        [(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)]
    ) {
        // 存储路由和处理器路由
        var processorRoutes:
            [(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)] =
            []
        var storageRoutes:
            [(sortingKey: Double, destinationId: Int64, commodityType: ItemType, quantity: Int64)] =
            []

        // 筛选和排序路由
        for route in lookup.outgoing[pinId] ?? [] {
            // 如果路由的资源类型不在待处理资源中，跳过
            if !commodities.keys.contains(route.type) {
                continue
            }

            // 获取目标设施
            guard let destinationPin = lookup.pins[route.destinationPinId]
            else {
                continue
            }

            // 根据目标设施类型分类路由
            if let factory = destinationPin as? Pin.Factory {
                // 处理器路由，使用输入缓冲区状态作为排序键
                let inputBufferState = getInputBufferState(factory: factory)
                processorRoutes.append(
                    (
                        sortingKey: inputBufferState, destinationId: route.destinationPinId,
                        commodityType: route.type, quantity: route.quantity
                    )
                )
            } else if isStorage(pin: destinationPin) {
                // 存储路由，使用剩余空间作为排序键
                let freeSpace = getCapacityRemaining(pin: destinationPin)
                storageRoutes.append(
                    (
                        sortingKey: freeSpace, destinationId: route.destinationPinId,
                        commodityType: route.type, quantity: route.quantity
                    )
                )
            }
        }

        // 排序路由（按排序键升序，当排序键相同时按设施ID升序）
        processorRoutes.sort { route1, route2 in
            if route1.sortingKey == route2.sortingKey {
                return route1.destinationId < route2.destinationId
            }
            return route1.sortingKey < route2.sortingKey
        }

        storageRoutes.sort { route1, route2 in
            if route1.sortingKey == route2.sortingKey {
                return route1.destinationId < route2.destinationId
            }
            return route1.sortingKey < route2.sortingKey
        }

        return (processorRoutes, storageRoutes)
    }

    /// 转移资源
    /// - Parameters:
    ///   - sourcePin: 源设施
    ///   - destinationPin: 目标设施
    ///   - type: 资源类型
    ///   - quantity: 请求数量
    ///   - commodities: 可用资源
    ///   - maxAmount: 最大转移量
    ///   - currentTime: 当前模拟时间
    /// - Returns: 资源类型和转移数量的元组
    private static func transferCommodities(
        sourcePin: Pin,
        destinationPin: Pin,
        type: ItemType,
        quantity: Int64,
        commodities: [ItemType: Int64],
        maxAmount: Int64? = nil,
        currentTime _: Date
    ) -> (ItemType?, Int64) {
        // 检查资源是否存在
        if !commodities.keys.contains(type) {
            return (nil, 0)
        }

        // 计算要转移的数量
        var amountToMove = min(commodities[type]!, quantity)
        if let maxAmount = maxAmount {
            amountToMove = min(maxAmount, amountToMove)
        }

        if amountToMove <= 0 {
            return (nil, 0)
        }

        // 计算目标设施可接受的数量
        let amountAccepted = canAccept(pin: destinationPin, type: type, quantity: amountToMove)
        if amountAccepted <= 0 {
            return (nil, 0)
        }

        // 从源设施移除资源
        if isStorage(pin: sourcePin) {
            let currentQuantity = sourcePin.contents[type] ?? 0
            sourcePin.contents[type] = currentQuantity - amountAccepted
            sourcePin.capacityUsed -= type.volume * Double(amountAccepted)

            // 如果数量为0，移除该键
            if sourcePin.contents[type] == 0 {
                sourcePin.contents.removeValue(forKey: type)
            }
        }

        // 向目标设施添加资源
        let destinationQuantity = destinationPin.contents[type] ?? 0
        destinationPin.contents[type] = destinationQuantity + amountAccepted
        destinationPin.capacityUsed += type.volume * Double(amountAccepted)

        // 如果目标是工厂，标记为已接收输入并记录缓冲区状态
        if let factory = destinationPin as? Pin.Factory {
            factory.hasReceivedInputs = true
        }

        return (type, amountAccepted)
    }

    /// 计算设施可接受的资源数量
    /// - Parameters:
    ///   - pin: 设施
    ///   - type: 资源类型
    ///   - quantity: 请求数量
    /// - Returns: 可接受的数量
    private static func canAccept(pin: Pin, type: ItemType, quantity: Int64) -> Int64 {
        if let factory = pin as? Pin.Factory {
            // 工厂只接受配方中需要的输入材料
            guard let schematic = factory.schematic else {
                return 0
            }

            // 检查资源是否在配方需求中
            guard let demandQuantity = schematic.inputs[type] else {
                return 0
            }

            // 计算还需要的数量
            let currentQuantity = factory.contents[type] ?? 0
            let remainingSpace = demandQuantity - currentQuantity

            if remainingSpace <= 0 {
                return 0
            }

            return min(quantity, remainingSpace)
        } else if isStorage(pin: pin) {
            // 存储设施根据容量接受资源
            let volume = type.volume
            let newVolume = volume * Double(quantity)
            let capacityRemaining = getCapacityRemaining(pin: pin)

            if newVolume > capacityRemaining {
                return Int64(capacityRemaining / volume)
            } else {
                return quantity
            }
        }

        // 提取器不接受资源
        return 0
    }

    /// 更新设施状态
    /// - Parameter colony: 殖民地
    private static func updatePinStatuses(colony: Colony) {
        for pin in colony.pins {
            pin.status = getPinStatus(pin: pin, now: colony.currentSimTime, routes: colony.routes)
        }
    }

    // MARK: - 辅助方法

    /// 获取设施容量
    /// - Parameter pin: 设施
    /// - Returns: 容量
    private static func getCapacity(for pin: Pin) -> Int? {
        switch pin {
        case is Pin.Extractor:
            return nil
        case is Pin.Factory:
            return nil
        case is Pin.Storage:
            return 12000
        case is Pin.CommandCenter:
            return 500
        case is Pin.Launchpad:
            return 10000
        default:
            return nil
        }
    }

    /// 从仓储设施重新填充工厂缓冲区
    /// - Parameters:
    ///   - factory: 工厂
    ///   - time: 当前时间
    ///   - eventQueue: 事件队列（inout参数）
    private static func refillFactoryBuffer(lookup: Lookup, factory: Pin.Factory, time: Date, eventQueue: inout [(date: Date, pinId: Int64)]) {
        guard colony != nil, let schematic = factory.schematic else {
            return
        }

        // 获取所有指向该工厂的路由
        let incomingRoutes = lookup.incoming[factory.id] ?? []
        if incomingRoutes.isEmpty {
            return
        }

        // 检查每个输入材料是否需要补充
        for (inputType, requiredQuantity) in schematic.inputs {
            let currentQuantity = factory.contents[inputType] ?? 0
            let neededQuantity = requiredQuantity - currentQuantity

            if neededQuantity <= 0 {
                continue // 该材料已经足够
            }

            // 查找可以提供该材料的仓储设施和路由
            let relevantRoutes = lookup.incomingByType[factory.id]?[inputType.id] ?? []
            for route in relevantRoutes {
                // 查找源设施
                guard let sourcePin = lookup.pins[route.sourcePinId],
                      isStorage(pin: sourcePin)
                else {
                    continue
                }

                // 检查源设施是否有该材料
                let availableQuantity = sourcePin.contents[inputType] ?? 0
                if availableQuantity <= 0 {
                    continue
                }

                // 计算可以转移的数量
                let transferQuantity = min(neededQuantity, availableQuantity, route.quantity)
                if transferQuantity <= 0 {
                    continue
                }

                // 执行转移
                let (_, transferredQuantity) = transferCommodities(
                    sourcePin: sourcePin,
                    destinationPin: factory,
                    type: inputType,
                    quantity: transferQuantity,
                    commodities: sourcePin.contents,
                    currentTime: time
                )

                if transferredQuantity > 0 {
                    // 更新工厂的输入状态
                    factory.hasReceivedInputs = true

                    // 如果已经满足需求，跳出循环
                    if transferredQuantity >= neededQuantity {
                        break
                    }
                }
            }
        }

        // 如果工厂已经有足够的材料可以开始下一个周期，重新安排它
        if hasEnoughInputs(factory: factory) {
            schedulePin(pin: factory, currentTime: time, eventQueue: &eventQueue)
        }
    }
}

// MARK: - 模拟缓存管理

/// 行星模拟管理器
class ColonySimulationManager {
    /// 单例实例
    static let shared = ColonySimulationManager()

    /// 模拟缓存
    private var simulationCache: [String: Colony] = [:]

    /// 私有初始化方法
    private init() {}

    /// 模拟殖民地
    /// - Parameters:
    ///   - colony: 殖民地
    ///   - targetTime: 目标时间
    ///   - progressCallback: 可选的进度回调，参数为进度值（0.0 到 1.0）
    /// - Returns: 模拟后的殖民地
    func simulateColony(colony: Colony, targetTime: Date, progressCallback: ColonySimulation.SimulationProgressCallback? = nil) -> Colony {
        let cacheKey = "\(colony.id)_\(targetTime.timeIntervalSince1970)"

        // 检查缓存
        if let cachedColony = simulationCache[cacheKey] {
            // 如果有缓存，立即报告100%进度
            progressCallback?(1.0)
            return cachedColony
        }

        // 执行模拟
        let simulatedColony = ColonySimulation.simulate(colony: colony, targetTime: targetTime, progressCallback: progressCallback)

        // 缓存结果
        simulationCache[cacheKey] = simulatedColony

        return simulatedColony
    }

    /// 获取殖民地停工时间（提取器过期时间）
    /// - Parameter colony: 殖民地
    /// - Returns: 停工时间，如果无法确定则返回nil
    private func getExpireTime(colony: Colony) -> Date? {
        var earliestExpireTime: Date?

        // 查找所有提取器中最小的过期时间
        for pin in colony.pins {
            if let extractor = pin as? Pin.Extractor, extractor.isActive {
                if let expiryTime = extractor.expiryTime, expiryTime > colony.currentSimTime {
                    if earliestExpireTime == nil || expiryTime < earliestExpireTime! {
                        earliestExpireTime = expiryTime
                    }
                }
            }
        }

        return earliestExpireTime
    }

    /// 根据设施运转周期计算采样间隔（小时）
    /// 获取所有设施的运转周期，找到最短周期，使用其1/2作为采样间隔
    /// - Parameter colony: 殖民地
    /// - Returns: 采样间隔（小时）
    private func calculateSamplingIntervalFromCycles(colony: Colony) -> Double {
        var allCycleTimes: [TimeInterval] = []

        // 收集所有设施的运转周期
        for pin in colony.pins {
            if let extractor = pin as? Pin.Extractor, extractor.isActive {
                // 提取器的周期时间（秒）
                if let cycleTime = extractor.cycleTime {
                    allCycleTimes.append(TimeInterval(cycleTime))
                }
            } else if let factory = pin as? Pin.Factory {
                // 工厂的周期时间（秒）
                if let schematic = factory.schematic {
                    allCycleTimes.append(schematic.cycleTime)
                }
            }
        }

        // 如果没有找到任何周期，使用默认值（0.1小时）
        guard let minCycleTime = allCycleTimes.min(), minCycleTime > 0 else {
            return 0.1
        }

        // 使用最短周期的1/2作为采样间隔（转换为小时）
        return minCycleTime / 2.0 / 3600.0 // 秒转小时
    }

    /// 生成每小时快照（从当前时间开始，直到停工或30天）
    /// 策略：
    /// 1. 根据设施运转周期计算采样间隔（最短周期的1/2）
    /// 2. 使用该间隔生成快照直到停工
    /// - Parameter colony: 殖民地
    /// - Returns: 快照字典 [分钟数: 殖民地状态]，分钟数从0开始（0 = 当前时间），使用分钟数作为key以保留精度
    func generateHourlySnapshots(colony: Colony) -> [Int: Colony] {
        var snapshots: [Int: Colony] = [:]
        let startTime = colony.currentSimTime
        let maxHours = 30 * 24 // 最多30天
        var currentColony = colony.clone()

        // 根据设施运转周期计算采样间隔
        let samplingInterval = calculateSamplingIntervalFromCycles(colony: colony)

        // 第0分钟 = 初始状态（当前时间）
        snapshots[0] = currentColony.clone()

        // 使用计算出的采样间隔生成快照
        var snapshotIndex = 0
        var totalElapsedHours = 0.0

        while totalElapsedHours < Double(maxHours) {
            // 计算下一个采样点
            totalElapsedHours += samplingInterval
            snapshotIndex += 1

            // 如果超过最大时间，终止
            if totalElapsedHours >= Double(maxHours) {
                break
            }

            let targetTime = startTime.addingTimeInterval(TimeInterval(totalElapsedHours * 3600.0))

            // 模拟到目标时间
            let simulatedColony = ColonySimulation.simulate(
                colony: currentColony,
                targetTime: targetTime
            )

            // 保存快照（使用分钟数作为key以保留精度）
            let minutesKey = Int(totalElapsedHours * 60.0)
            snapshots[minutesKey] = simulatedColony.clone()

            // 检查是否停工
            let isWorking = ColonySimulation.isColonyStillWorking(colony: simulatedColony)

            // 检查提取器是否过期（动态检测停工时间）
            let currentExpireTime = getExpireTime(colony: simulatedColony)
            if let expire = currentExpireTime, expire <= targetTime {
                break
            }

            // 如果停工，终止生成
            if !isWorking {
                break
            }

            // 更新当前殖民地状态，用于下一次增量模拟
            currentColony = simulatedColony
        }

        // 第二阶段：智能二次采样，将采样点压缩
        let targetSnapshotCount = 300
        let currentCount = snapshots.count

        if currentCount > targetSnapshotCount {
            // 计算采样点间隔倍数（每N个采样点保留1个）
            let ratio = Double(currentCount) / Double(targetSnapshotCount)
            let multiplier = max(1, Int(ratio.rounded())) // 四舍五入取整，但至少为1

            // 从现有快照中按索引间隔提取
            var finalSnapshots: [Int: Colony] = [:]
            let sortedMinutes = snapshots.keys.sorted()

            // 按索引间隔提取：每multiplier个采样点保留1个
            for (index, minutes) in sortedMinutes.enumerated() {
                // 始终保留第0个（初始状态），以及索引能被multiplier整除的采样点
                if index == 0 || index % multiplier == 0 {
                    finalSnapshots[minutes] = snapshots[minutes]
                }
            }

            // 确保包含最后一个快照
            if let lastMinutes = sortedMinutes.last, lastMinutes > 0 {
                if finalSnapshots[lastMinutes] == nil {
                    finalSnapshots[lastMinutes] = snapshots[lastMinutes]
                }
            }

            return finalSnapshots
        } else {
            // 如果采样点数量已经小于等于目标数量，直接返回
            return snapshots
        }
    }
}
