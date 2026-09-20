import Foundation

/// 模块组管理器 - 统一处理同组装备的状态限制逻辑
class ModuleGroupManager {
    /// 同组装备状态统计结果
    struct GroupStatusCount {
        let onlineCount: Int
        let activeCount: Int
        let onlineModules: [(Int, SimModule)]
        let activeModules: [(Int, SimModule)]
    }

    /// 统计指定组ID的装备状态
    /// - Parameters:
    ///   - modules: 所有模块列表
    ///   - groupID: 要统计的组ID
    /// - Returns: 状态统计结果
    static func countGroupStatus(modules: [SimModule], groupID: Int) -> GroupStatusCount {
        var onlineCount = 0
        var activeCount = 0
        var onlineModules: [(Int, SimModule)] = []
        var activeModules: [(Int, SimModule)] = []

        for (index, module) in modules.enumerated() {
            if module.groupID == groupID {
                if module.status >= 1 { // ONLINE 或更高状态
                    onlineCount += 1
                    onlineModules.append((index, module))
                }
                if module.status >= 2 { // ACTIVE 或更高状态
                    activeCount += 1
                    activeModules.append((index, module))
                }
            }
        }

        return GroupStatusCount(
            onlineCount: onlineCount,
            activeCount: activeCount,
            onlineModules: onlineModules,
            activeModules: activeModules
        )
    }

    /// 检查状态是否符合同组限制
    /// - Parameters:
    ///   - targetStatus: 目标状态
    ///   - groupID: 组ID
    ///   - maxGroupOnline: 最大在线数量限制
    ///   - maxGroupActive: 最大激活数量限制
    ///   - currentModules: 当前模块列表（不包含要设置的模块）
    /// - Returns: 调整后的合适状态
    static func validateStatus(
        targetStatus: Int,
        groupID: Int,
        maxGroupOnline: Int,
        maxGroupActive: Int,
        currentModules: [SimModule]
    ) -> Int {
        // 如果没有限制，直接返回目标状态
        if maxGroupOnline == 0 && maxGroupActive == 0 {
            return targetStatus
        }

        let statusCount = countGroupStatus(modules: currentModules, groupID: groupID)
        var adjustedStatus = targetStatus

        Logger.info(
            """
            状态验证:
            - 组ID: \(groupID)
            - 目标状态: \(targetStatus)
            - maxGroupOnline: \(maxGroupOnline)
            - maxGroupActive: \(maxGroupActive)
            - 当前在线数量: \(statusCount.onlineCount)
            - 当前激活数量: \(statusCount.activeCount)
            """
        )

        // 检查激活状态限制
        if maxGroupActive > 0 && adjustedStatus >= 2 {
            if statusCount.activeCount >= maxGroupActive {
                adjustedStatus = 1 // 降级到在线状态
                Logger.warning("达到maxGroupActive限制，状态降级到在线(1)")
            }
        }

        // 检查在线状态限制
        if maxGroupOnline > 0 && adjustedStatus >= 1 {
            if statusCount.onlineCount >= maxGroupOnline {
                adjustedStatus = 0 // 降级到离线状态
                Logger.warning("达到maxGroupOnline限制，状态降级到离线(0)")
            }
        }

        Logger.info("最终状态: \(adjustedStatus)")
        return adjustedStatus
    }

    /// 处理同组装备的连锁降级
    /// - Parameters:
    ///   - modules: 模块列表（会被修改）
    ///   - groupID: 组ID
    ///   - maxGroupOnline: 最大在线数量限制
    ///   - maxGroupActive: 最大激活数量限制
    ///   - excludeFlags: 不降级的槽位标识列表
    /// - Returns: 被修改的模块索引列表
    @discardableResult
    static func handleGroupDowngrade(
        modules: inout [SimModule],
        groupID: Int,
        maxGroupOnline: Int,
        maxGroupActive: Int,
        excludeFlags: [FittingFlag] = []
    ) -> [Int] {
        var modifiedIndices: [Int] = []

        // 如果没有限制，直接返回
        if maxGroupOnline == 0, maxGroupActive == 0 {
            return modifiedIndices
        }

        let statusCount = countGroupStatus(modules: modules, groupID: groupID)

        Logger.info(
            """
            处理同组降级:
            - 组ID: \(groupID)
            - maxGroupOnline: \(maxGroupOnline)
            - maxGroupActive: \(maxGroupActive)
            - 当前在线数量: \(statusCount.onlineCount)
            - 当前激活数量: \(statusCount.activeCount)
            - 排除槽位: \(excludeFlags.map { $0.rawValue })
            """
        )

        // 处理在线状态限制
        if maxGroupOnline > 0, statusCount.onlineCount > maxGroupOnline {
            let excessCount = statusCount.onlineCount - maxGroupOnline
            let sortedOnlineModules = statusCount.onlineModules.sorted { first, second in
                first.1.flag?.rawValue ?? "" < second.1.flag?.rawValue ?? ""
            }

            var downgraded = 0
            for (moduleIndex, module) in sortedOnlineModules.reversed() {
                if downgraded >= excessCount {
                    break
                }
                if let flag = module.flag, !excludeFlags.contains(flag) {
                    // 降级为离线状态
                    let updatedModule = SimModule(
                        instanceId: module.instanceId,
                        typeId: module.typeId,
                        attributes: module.attributes,
                        attributesByName: module.attributesByName,
                        effects: module.effects,
                        groupID: module.groupID,
                        status: 0,
                        charge: module.charge,
                        flag: module.flag,
                        quantity: module.quantity,
                        name: module.name,
                        iconFileName: module.iconFileName,
                        requiredSkills: FitConvert.extractRequiredSkills(
                            attributes: module.attributes
                        ),
                        isSpoolUpFull: module.isSpoolUpFull
                    )
                    modules[moduleIndex] = updatedModule
                    modifiedIndices.append(moduleIndex)
                    Logger.info(
                        "将同组装备[\(module.name)]从状态\(module.status)降级到离线(0)"
                    )
                    downgraded += 1
                }
            }
        }

        // 重新统计状态（因为可能有模块被降级到离线）
        let updatedStatusCount = countGroupStatus(modules: modules, groupID: groupID)

        // 处理激活状态限制
        if maxGroupActive > 0, updatedStatusCount.activeCount > maxGroupActive {
            let excessCount = updatedStatusCount.activeCount - maxGroupActive
            let sortedActiveModules = updatedStatusCount.activeModules.sorted { first, second in
                first.1.flag?.rawValue ?? "" < second.1.flag?.rawValue ?? ""
            }

            var downgraded = 0
            for (moduleIndex, module) in sortedActiveModules.reversed() {
                if downgraded >= excessCount {
                    break
                }
                if let flag = module.flag, !excludeFlags.contains(flag) {
                    // 降级为在线状态
                    let updatedModule = SimModule(
                        instanceId: module.instanceId,
                        typeId: module.typeId,
                        attributes: module.attributes,
                        attributesByName: module.attributesByName,
                        effects: module.effects,
                        groupID: module.groupID,
                        status: 1,
                        charge: module.charge,
                        flag: module.flag,
                        quantity: module.quantity,
                        name: module.name,
                        iconFileName: module.iconFileName,
                        requiredSkills: FitConvert.extractRequiredSkills(
                            attributes: module.attributes
                        ),
                        isSpoolUpFull: module.isSpoolUpFull
                    )
                    modules[moduleIndex] = updatedModule
                    modifiedIndices.append(moduleIndex)
                    Logger.info(
                        "将同组装备[\(module.name)]从状态\(module.status)降级到在线(1)"
                    )
                    downgraded += 1
                }
            }
        }

        return modifiedIndices
    }
}
