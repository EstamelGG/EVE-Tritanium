import Foundation
import SwiftUI

/// 配置编辑器视图模型 - 管理配置编辑过程中的状态
@MainActor
class FittingEditorViewModel: ObservableObject {
    /// 配置数据
    @Published var simulationInput: SimulationInput

    /// 新的计算结果（使用输出结构）
    @Published private(set) var simulationOutput: SimulationOutput?

    // 技能选择状态（在配置生命周期内保持，但不持久化到文件）
    @Published var currentSkillsMode: String = UserDefaults.standard.string(forKey: "skillsModePreference") ?? "current_char"
    @Published var currentSelectedCharacterId: Int? = nil

    // 元数据
    @Published var shipInfo: (name: String, iconFileName: String)
    @Published var isNewFitting: Bool
    @Published var isLocalFitting: Bool = true // 是否为本地配置，默认为true
    @Published var hasUnsavedChanges = false
    @Published var errorMessage: String? // 添加错误消息
    @Published var invalidModules: [(module: SimModule, reason: String)] = [] // 无效的模块列表

    // 槽位折叠状态（临时保存，退出页面时自动清除）
    @Published var hiSlotsCollapsed = false
    @Published var medSlotsCollapsed = false
    @Published var loSlotsCollapsed = false
    @Published var rigSlotsCollapsed = false

    // 计算器和数据库
    private let attributeCalculator: AttributeCalculator
    let databaseManager: DatabaseManager

    // MARK: - 初始化方法

    /// 初始化方法（新建配置）
    /// - Parameter characterSkills: 若在外部已异步加载（如 `loadSkillsBeforeFittingCalculation`），传入可避免先用全5级再覆盖。
    init(
        shipTypeId: Int, shipInfo: (name: String, iconFileName: String),
        databaseManager: DatabaseManager,
        characterSkills: [Int: Int]? = nil
    ) {
        self.databaseManager = databaseManager
        self.shipInfo = shipInfo
        isNewFitting = true
        isLocalFitting = true // 新建配置为本地配置
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        let resolvedSkills = characterSkills ?? FittingCharacterSkillsLoader.skillsFromUserPreferences()

        // 创建初始配置
        let localFitting = FitConvert.createInitialFitting(shipTypeId: shipTypeId)

        // 转换为模拟输入
        simulationInput = FitConvert.localFittingToSimulationInput(
            localFitting: localFitting,
            databaseManager: databaseManager,
            characterSkills: resolvedSkills
        )

        Logger.info("新建配置，计算初始属性")
        calculateAttributes()
        syncSelectedCharacterIdFromPreferencesIfNeeded()
    }

    /// 初始化方法（加载本地配置）
    init(fittingId: UUID, databaseManager: DatabaseManager, characterSkills: [Int: Int]? = nil) {
        self.databaseManager = databaseManager
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        let resolvedSkills = characterSkills ?? FittingCharacterSkillsLoader.skillsFromUserPreferences()

        do {
            // 加载配置
            let localFitting = try FitConvert.loadLocalFitting(fittingId: fittingId)

            // 查询飞船信息
            if let info = ItemInfoMap.typeInfo(for: localFitting.ship_type_id) {
                shipInfo = (name: info.name, iconFileName: info.iconFilename)
            } else {
                shipInfo = (
                    name: NSLocalizedString("Unknown", comment: "Unknown Ship"), iconFileName: ""
                )
            }

            isNewFitting = false
            isLocalFitting = true // 本地配置文件

            // 转换为模拟输入
            let simInput = FitConvert.localFittingToSimulationInput(
                localFitting: localFitting,
                databaseManager: databaseManager,
                characterSkills: resolvedSkills
            )

            // 验证配置中的装备是否都可以安装
            let (processedInput, invalidModules) = processConfiguration(
                simulationInput: simInput,
                databaseManager: databaseManager
            )

            // 直接使用处理后的输入，保留原始状态
            simulationInput = processedInput
            self.invalidModules = invalidModules

            // 如果有无效模块，设置错误消息
            if !invalidModules.isEmpty {
                let invalidModuleNames = invalidModules.map { $0.module.name }.joined(
                    separator: ", "
                )
                errorMessage = "以下装备无法安装到当前飞船，已自动移除: \(invalidModuleNames)"
                hasUnsavedChanges = true

                // 记录警告日志
                Logger.warning("配置中包含无法安装的装备，已移除: \(invalidModuleNames)")
            }

            // 计算初始属性
            Logger.info("加载本地配置，计算初始属性")
            calculateAttributes()
            // 计算后统一校验同组限制（装配数量/在线/激活上限以计算结果为准）
            validateGroupLimitsAfterCalculation()
            syncSelectedCharacterIdFromPreferencesIfNeeded()
        } catch {
            // 错误处理
            Logger.error("加载配置失败: \(error)")

            // 初始化为默认值
            isNewFitting = true
            isLocalFitting = true // 错误情况下默认为本地配置
            shipInfo = (name: "Error", iconFileName: "")

            // 使用默认值 - 这里应该更优雅地处理
            simulationInput = SimulationInput(
                fittingId: .local(UUID()),
                name: "",
                description: "",
                fighters: nil,
                ship: SimShip(
                    typeId: 0, baseAttributes: [:], baseAttributesByName: [:], effects: [],
                    groupID: 0, name: "Unknown", iconFileName: "not_found", requiredSkills: []
                ),
                modules: [],
                drones: [],
                cargo: SimCargo(items: []),
                implants: [],
                environmentEffects: [],
                characterSkills: [:]
            )
            Logger.info("加载本地配置失败，使用默认值计算初始属性")
            calculateAttributes()
        }
    }

    /// 初始化方法（临时装配，如DNA导入，不保存文件）
    init(temporaryFitting: LocalFitting, databaseManager: DatabaseManager, characterSkills: [Int: Int]? = nil) {
        self.databaseManager = databaseManager
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        let resolvedSkills = characterSkills ?? FittingCharacterSkillsLoader.skillsFromUserPreferences()

        // 查询飞船信息
        if let info = ItemInfoMap.typeInfo(for: temporaryFitting.ship_type_id) {
            shipInfo = (name: info.name, iconFileName: info.iconFilename)
        } else {
            shipInfo = (
                name: NSLocalizedString("Unknown", comment: "Unknown Ship"), iconFileName: ""
            )
        }

        isNewFitting = false
        isLocalFitting = false // 临时装配，不是真正的本地配置文件

        // 转换为模拟输入
        let simInput = FitConvert.localFittingToSimulationInput(
            localFitting: temporaryFitting,
            databaseManager: databaseManager,
            characterSkills: resolvedSkills
        )

        // 验证配置中的装备是否都可以安装
        let (processedInput, invalidModules) = processConfiguration(
            simulationInput: simInput,
            databaseManager: databaseManager
        )

        // 直接使用处理后的输入
        simulationInput = processedInput
        self.invalidModules = invalidModules

        // 如果有无效模块，设置错误消息
        if !invalidModules.isEmpty {
            let invalidModuleNames = invalidModules.map { $0.module.name }.joined(separator: ", ")
            errorMessage = "以下装备无法安装到当前飞船，已自动移除: \(invalidModuleNames)"

            Logger.warning("DNA装配中包含无法安装的装备，已移除: \(invalidModuleNames)")
        }

        Logger.info("创建临时装配视图模型，计算初始属性")
        calculateAttributes()
        // 计算后统一校验同组限制（装配数量/在线/激活上限以计算结果为准）
        validateGroupLimitsAfterCalculation()
        syncSelectedCharacterIdFromPreferencesIfNeeded()
    }

    /// 初始化方法（加载在线配置）
    init(onlineFitting: CharacterFitting, databaseManager: DatabaseManager, characterSkills: [Int: Int]? = nil) {
        self.databaseManager = databaseManager
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        let resolvedSkills = characterSkills ?? FittingCharacterSkillsLoader.skillsFromUserPreferences()

        // 查询飞船信息
        if let info = ItemInfoMap.typeInfo(for: onlineFitting.ship_type_id) {
            shipInfo = (name: info.name, iconFileName: info.iconFilename)
        } else {
            shipInfo = (
                name: NSLocalizedString("Unknown", comment: "Unknown Ship"), iconFileName: ""
            )
        }

        isNewFitting = false
        isLocalFitting = false // 在线配置

        // 将在线配置转换为本地配置
        // 创建FittingItem数组
        let fittingItems = onlineFitting.items.map { item in
            FittingItem(flag: item.flag, quantity: item.quantity, type_id: item.type_id)
        }

        // 创建在线配置对象
        let onlineFittingObj = OnlineFitting(
            description: onlineFitting.description ?? "",
            fitting_id: onlineFitting.fitting_id,
            items: fittingItems,
            name: onlineFitting.name,
            ship_type_id: onlineFitting.ship_type_id
        )

        // 将在线配置转换为本地配置
        do {
            let jsonData = try JSONEncoder().encode([onlineFittingObj])
            Logger.info(
                "将在线配置转换为JSON: 飞船ID=\(onlineFitting.ship_type_id), 配置项数量=\(fittingItems.count)"
            )
            if let localFittings = try? FitConvert.online2local(jsonData: jsonData),
               let localFitting = localFittings.first
            {
                Logger.success("成功转换为本地配置: 舰载机数量=\(localFitting.fighters?.count ?? 0)")

                // 转换为模拟输入
                let simInput = FitConvert.localFittingToSimulationInput(
                    localFitting: localFitting,
                    databaseManager: databaseManager,
                    characterSkills: resolvedSkills
                )
                Logger.info("转换为模拟输入: 舰载机数量=\(simInput.fighters?.count ?? 0)")

                // 验证配置中的装备是否都可以安装
                let (processedInput, invalidModules) = processConfiguration(
                    simulationInput: simInput,
                    databaseManager: databaseManager
                )

                // 装备状态沿用乐观安装结果（localFittingToSimulationInput 已按 getMaxStatus 提升；
                // 同组限制由 calculateAttributes 后的 validateGroupLimitsAfterCalculation 用计算结果统一校验，
                // 此处不再用裸属性逐个 setStatus 降级，避免"先装先占名额"的假性死锁）
                simulationInput = processedInput
                // 经 online2local 转换会带上临时 UUID，覆写回在线身份（删除/保存分支依赖）
                simulationInput.fittingId = .online(onlineFitting.fitting_id)
                self.invalidModules = invalidModules

                // 如果有无效模块，设置错误消息
                if !invalidModules.isEmpty {
                    let invalidModuleNames = invalidModules.map { $0.module.name }.joined(
                        separator: ", "
                    )
                    errorMessage = "以下装备无法安装到当前飞船，已自动移除: \(invalidModuleNames)"
                    hasUnsavedChanges = true

                    // 记录警告日志
                    Logger.warning("在线配置中包含无法安装的装备，已移除: \(invalidModuleNames)")
                }
            } else {
                throw NSError(
                    domain: "FittingEditorViewModel", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "在线配置转换失败"]
                )
            }
        } catch {
            // 如果转换失败，使用默认值
            Logger.error("在线配置转换失败: \(error.localizedDescription)")
            simulationInput = SimulationInput(
                fittingId: .online(onlineFitting.fitting_id),
                name: onlineFitting.name,
                description: onlineFitting.description ?? "",
                fighters: nil,
                ship: SimShip(
                    typeId: 0, baseAttributes: [:], baseAttributesByName: [:], effects: [],
                    groupID: 0, name: "Unknown", iconFileName: "not_found", requiredSkills: []
                ),
                modules: [],
                drones: [],
                cargo: SimCargo(items: []),
                implants: [],
                environmentEffects: [],
                characterSkills: [:]
            )
        }

        Logger.info("在线配置转换结束，计算初始属性")
        calculateAttributes()
        // 计算后统一校验同组限制（装配数量/在线/激活上限以计算结果为准）
        validateGroupLimitsAfterCalculation()
        if simulationInput.ship.typeId != 0 {
            syncSelectedCharacterIdFromPreferencesIfNeeded()
        }
    }

    // MARK: - 公共方法

    /// 技能模式为「指定人物」时，与设置中的选中 ID 对齐（供设置页展示）
    private func syncSelectedCharacterIdFromPreferencesIfNeeded() {
        guard UserDefaults.standard.string(forKey: "skillsModePreference") == "character" else { return }
        let id = UserDefaults.standard.integer(forKey: "selectedSkillCharacterId")
        if id != 0 {
            currentSelectedCharacterId = id
        }
    }

    /// 保存当前配置
    func saveConfiguration() {
        do {
            let localFitting = FitConvert.simulationInputToLocalFitting(input: simulationInput)
            try FitConvert.saveLocalFitting(localFitting)
            hasUnsavedChanges = false
            Logger.info("配置保存成功")
        } catch {
            Logger.error("保存配置失败: \(error)")
        }
    }

    /// 计算动态挂点数量（考虑子系统修饰器）
    func calculateDynamicHardpoints() -> (turretHardpoints: Int, launcherHardpoints: Int) {
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

        return (
            turretHardpoints: totalTurretHardpoints, launcherHardpoints: totalLauncherHardpoints
        )
    }

    /// 重新计算属性
    func calculateAttributes() {
        Logger.info("【calculateAttributes】开始重新计算属性")

        // 记录输入中的舰载机信息（仅在调试模式下）
        if AppConfiguration.Fitting.showDebug {
            if let fighters = simulationInput.fighters {
                Logger.info("【calculateAttributes】输入中有 \(fighters.count) 个舰载机")
                for fighter in fighters {
                    Logger.info(
                        "【calculateAttributes】输入舰载机: \(fighter.name), typeId: \(fighter.typeId), 属性数量: \(fighter.attributesByName.count)"
                    )
                }
            } else {
                Logger.info("【calculateAttributes】输入中没有舰载机")
            }
        }

        let output = attributeCalculator.calculateAndGenerateOutput(input: simulationInput)
        simulationOutput = output

        // 记录输出中的舰载机信息（仅在调试模式下）
        if AppConfiguration.Fitting.showDebug {
            if let outputFighters = simulationOutput?.fighters {
                Logger.info("【calculateAttributes】输出中有 \(outputFighters.count) 个舰载机")
                for fighter in outputFighters {
                    Logger.info(
                        "【calculateAttributes】输出舰载机: \(fighter.name), typeId: \(fighter.typeId), 属性数量: \(fighter.attributesByName.count)"
                    )

                    // 检查伤害属性
                    let damageAttributes = fighter.attributesByName.filter {
                        $0.key.lowercased().contains("damage")
                    }
                    if !damageAttributes.isEmpty {
                        Logger.info("【calculateAttributes】输出舰载机伤害属性数量: \(damageAttributes.count)")
                    } else {
                        Logger.warning("【calculateAttributes】输出舰载机没有伤害属性")
                    }
                }
            } else {
                Logger.info("【calculateAttributes】输出中没有舰载机")
            }
        }

        Logger.info("【calculateAttributes】属性计算完成")
    }

    /// 更新配置名称
    func updateName(_ newName: String) {
        simulationInput.name = newName
        hasUnsavedChanges = true
        // calculateAttributes()
        objectWillChange.send()
    }

    /// 更新配置使用的技能
    func updateCharacterSkills(skills: [Int: Int], sourceType: CharacterSkillsType) {
        Logger.info("更新配置使用的技能数据，来源类型: \(sourceType), 技能数量: \(skills.count)")

        // 更新技能数据
        simulationInput.characterSkills = skills

        // 重新计算属性
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()
    }

    /// 收集装配所需的所有物品 typeID（飞船、装备、弹药、无人机、货舱、舰载机、植入体）
    private func collectFittingTypeIDs() -> [Int] {
        var typeIDs: [Int] = []
        typeIDs.append(simulationInput.ship.typeId)
        for module in simulationInput.modules {
            typeIDs.append(module.typeId)
            if let charge = module.charge {
                typeIDs.append(charge.typeId)
            }
        }
        for drone in simulationInput.drones {
            typeIDs.append(drone.typeId)
        }
        if let fighters = simulationInput.fighters {
            for squad in fighters {
                typeIDs.append(squad.typeId)
            }
        }
        for item in simulationInput.cargo.items {
            typeIDs.append(item.typeId)
        }
        for implant in simulationInput.implants {
            typeIDs.append(implant.typeId)
        }
        return typeIDs
    }

    /// 获取装配所需的全部技能（含飞船、装备、弹药、无人机、货舱、舰载机、植入体）
    /// 包含已满足和未满足的技能，用于生成完整技能队列
    /// 当前等级取自 `simulationInput.characterSkills`，与装配模拟使用的技能来源一致（含「当前角色」「指定角色」等模式）。
    /// - Returns: [(skillID, requiredLevel, currentLevel, skillName)] 按 skillID 升序
    func getAllRequiredSkillsForFitting() -> [(skillID: Int, requiredLevel: Int, currentLevel: Int, skillName: String)] {
        let characterSkills = simulationInput.characterSkills
        let typeIDs = collectFittingTypeIDs()

        var requiredLevels: [Int: Int] = [:]
        for typeID in typeIDs {
            let reqs = databaseManager.getDirectSkillRequirements(for: typeID)
            for (skillID, level) in reqs {
                let current = requiredLevels[skillID] ?? 0
                requiredLevels[skillID] = max(current, level)
            }
        }

        var result: [(skillID: Int, requiredLevel: Int, currentLevel: Int, skillName: String)] = []
        for (skillID, requiredLevel) in requiredLevels {
            let currentLevel = characterSkills[skillID] ?? 0
            let skillName = SkillTreeManager.shared.getSkillName(for: skillID) ?? "Unknown (\(skillID))"
            result.append((skillID: skillID, requiredLevel: requiredLevel, currentLevel: currentLevel, skillName: skillName))
        }
        return result.sorted { $0.skillID < $1.skillID }
    }

    /// 获取配置所需但当前所选技能配置下缺失的技能（仅计算上船和使用装备所需的最低技能）
    /// 与 `simulationInput.characterSkills` 一致；设置里选择「指定角色」时，按该角色技能与需求对比。
    /// - Returns: [(skillID, requiredLevel, currentLevel, skillName)] 按 skillID 升序
    func getMissingSkillsForFitting() -> [(skillID: Int, requiredLevel: Int, currentLevel: Int, skillName: String)] {
        getAllRequiredSkillsForFitting().filter { $0.currentLevel < $0.requiredLevel }
    }
}
