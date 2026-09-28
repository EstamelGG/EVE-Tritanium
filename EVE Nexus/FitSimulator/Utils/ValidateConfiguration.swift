import Foundation

/// 计算动态挂点数量（考虑子系统修饰器）
private func calculateDynamicHardpoints(simulationInput: SimulationInput) -> (
    turretHardpoints: Int, launcherHardpoints: Int
) {
    // 获取基础挂点数
    let baseTurretHardpoints = Int(
        simulationInput.ship.baseAttributesByName["turretSlotsLeft"] ?? 0
    )
    let baseLauncherHardpoints = Int(
        simulationInput.ship.baseAttributesByName["launcherSlotsLeft"] ?? 0
    )

    var totalTurretHardpoints = baseTurretHardpoints
    var totalLauncherHardpoints = baseLauncherHardpoints

    // 遍历所有已安装的模块，查找子系统的挂点修饰器
    for module in simulationInput.modules {
        if let turretHardPointModifier = module.attributesByName["turretHardPointModifier"] {
            totalTurretHardpoints += Int(turretHardPointModifier)
            if AppConfiguration.Fitting.showDebug {
                Logger.info("子系统 \(module.name) 增加炮台挂点: \(Int(turretHardPointModifier))")
            }
        }

        if let launcherHardPointModifier = module.attributesByName["launcherHardPointModifier"] {
            totalLauncherHardpoints += Int(launcherHardPointModifier)
            if AppConfiguration.Fitting.showDebug {
                Logger.info("子系统 \(module.name) 增加发射器挂点: \(Int(launcherHardPointModifier))")
            }
        }
    }

    // 确保挂点数不为负数
    totalTurretHardpoints = max(0, totalTurretHardpoints)
    totalLauncherHardpoints = max(0, totalLauncherHardpoints)

    if AppConfiguration.Fitting.showDebug {
        Logger.info(
            "动态挂点计算结果 - 炮台挂点: \(totalTurretHardpoints) (基础: \(baseTurretHardpoints)), 发射器挂点: \(totalLauncherHardpoints) (基础: \(baseLauncherHardpoints))"
        )
    }

    return (turretHardpoints: totalTurretHardpoints, launcherHardpoints: totalLauncherHardpoints)
}

/// 处理配置中的装备，逐个检查是否可以安装到飞船上
/// - Parameters:
///   - simulationInput: 模拟输入数据
///   - databaseManager: 数据库管理器
/// - Returns: (处理后的配置, 被跳过的模块列表)
func processConfiguration(simulationInput: SimulationInput, databaseManager: DatabaseManager) -> (
    SimulationInput, [(module: SimModule, reason: String)]
) {
    // 创建空的模拟输入作为起点
    var processedInput = simulationInput
    processedInput.modules = []

    // 跟踪被跳过的模块
    var skippedModules: [(module: SimModule, reason: String)] = []

    // 按优先级对模块进行分类
    let modulesByPriority = categorizeModulesByPriority(modules: simulationInput.modules)

    // 按优先级顺序逐个尝试安装模块
    let allModulesInOrder =
        modulesByPriority.subsystems + modulesByPriority.rigs + modulesByPriority.hiSlots
            + modulesByPriority.medSlots + modulesByPriority.lowSlots + modulesByPriority.others

    for module in allModulesInOrder {
        // 获取当前配置的动态挂点数量
        let (turretSlotsNum, launcherSlotsNum) = calculateDynamicHardpoints(
            simulationInput: processedInput
        )

        // 执行装配检查
        let canInstall = canFit(
            simulationInput: processedInput, // 使用已处理的配置进行检查
            itemAttributes: module.attributes,
            itemAttributesName: module.attributesByName,
            itemEffects: module.effects,
            volume: module.attributesByName["volume"] ?? 0,
            typeId: module.typeId,
            itemGroupID: module.groupID,
            databaseManager: databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )

        if canInstall {
            // 如果可以安装，添加到处理后的配置中
            processedInput.modules.append(module)
            if AppConfiguration.Fitting.showDebug {
                Logger.success("成功安装装备: \(module.name) 到槽位 \(module.flag?.rawValue ?? "未知")")
            }
        } else {
            // 复查：跳过同组装配数量上限（maxGroupFitted）后再试一次。
            // 若通过说明仅是数量超限（同组数量上限依赖计算后属性，如加成处理器增加脉冲波槽位，
            // 逐个累积检查会产生"先装先占名额"的假性死锁）→ 保留装配但强制离线，待计算后统一校验
            let canInstallIgnoringGroupLimit = canFit(
                simulationInput: processedInput,
                itemAttributes: module.attributes,
                itemAttributesName: module.attributesByName,
                itemEffects: module.effects,
                volume: module.attributesByName["volume"] ?? 0,
                typeId: module.typeId,
                itemGroupID: module.groupID,
                databaseManager: databaseManager,
                turretSlotsNum: turretSlotsNum,
                launcherSlotsNum: launcherSlotsNum,
                ignoreGroupLimit: true
            )

            if canInstallIgnoringGroupLimit {
                processedInput.modules.append(module.withStatus(0))
                Logger.warning(
                    "装备同组数量超限，保留装配但强制离线（待计算后校验）: \(module.name) 到槽位 \(module.flag?.rawValue ?? "未知")"
                )
            } else {
                // 真不兼容（槽位/挂点/船型限制等），剔除并记录
                let reason = "该装备无法安装到当前飞船: \(module.name)"
                Logger.fault(reason)
                skippedModules.append((module: module, reason: reason))
            }
        }
    }

    return (processedInput, skippedModules)
}

/// 按优先级对模块进行分类
/// - Parameter modules: 模块列表
/// - Returns: 按优先级分类的模块
private func categorizeModulesByPriority(modules: [SimModule]) -> (
    subsystems: [SimModule],
    rigs: [SimModule],
    hiSlots: [SimModule],
    medSlots: [SimModule],
    lowSlots: [SimModule],
    others: [SimModule]
) {
    var subsystems: [SimModule] = []
    var rigs: [SimModule] = []
    var hiSlots: [SimModule] = []
    var medSlots: [SimModule] = []
    var lowSlots: [SimModule] = []
    var others: [SimModule] = []

    for module in modules {
        guard let flag = module.flag else {
            others.append(module)
            continue
        }

        switch flag.slot {
        // 子系统槽位 (最高优先级)
        case .subsystem:
            subsystems.append(module)

        // 改装槽位 (第二优先级)
        case .rig:
            rigs.append(module)

        // 高槽位 (第三优先级)
        case .high:
            hiSlots.append(module)

        // 中槽位 (第四优先级)
        case .medium:
            medSlots.append(module)

        // 低槽位 (第五优先级)
        case .low:
            lowSlots.append(module)

        default:
            others.append(module)
        }
    }

    // 对每个分类内的模块按槽位索引排序
    subsystems.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    rigs.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    hiSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    medSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    lowSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }

    Logger.info(
        "装备分类完成 - 子系统: \(subsystems.count), 改装: \(rigs.count), 高槽: \(hiSlots.count), 中槽: \(medSlots.count), 低槽: \(lowSlots.count), 其他: \(others.count)"
    )

    return (
        subsystems: subsystems, rigs: rigs, hiSlots: hiSlots, medSlots: medSlots,
        lowSlots: lowSlots, others: others
    )
}

/// 从槽位标识中提取槽位索引
/// - Parameter flag: 槽位标识
/// - Returns: 槽位索引
private func getSlotIndex(from flag: FittingFlag?) -> Int {
    flag?.slotIndex ?? 999
}
