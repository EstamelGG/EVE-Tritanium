import Foundation
import SwiftUI

extension FittingEditorViewModel {
    // MARK: - 私有辅助方法

    /// 复制模块并更新状态（保留突变数据与instanceId）
    private func updatedModule(_ currentModule: SimModule, status: Int) -> SimModule {
        SimModule(
            instanceId: currentModule.instanceId, // 保留原模块的instanceId
            typeId: currentModule.typeId,
            attributes: currentModule.attributes,
            attributesByName: currentModule.attributesByName,
            effects: currentModule.effects,
            groupID: currentModule.groupID,
            status: status,
            charge: currentModule.charge,
            flag: currentModule.flag,
            quantity: currentModule.quantity,
            name: currentModule.name,
            iconFileName: currentModule.iconFileName,
            requiredSkills: currentModule.requiredSkills,
            selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
            mutatedAttributes: currentModule.mutatedAttributes,
            mutatedTypeId: currentModule.mutatedTypeId,
            mutatedName: currentModule.mutatedName,
            mutatedIconFileName: currentModule.mutatedIconFileName,
            isSpoolUpFull: currentModule.isSpoolUpFull
        )
    }

    /// 复制模块并更新弹药（保留突变数据与instanceId）
    private func updatedModule(_ currentModule: SimModule, charge: SimCharge?) -> SimModule {
        SimModule(
            instanceId: currentModule.instanceId, // 保留原模块的instanceId
            typeId: currentModule.typeId,
            attributes: currentModule.attributes,
            attributesByName: currentModule.attributesByName,
            effects: currentModule.effects,
            groupID: currentModule.groupID,
            status: currentModule.status,
            charge: charge,
            flag: currentModule.flag,
            quantity: currentModule.quantity,
            name: currentModule.name,
            iconFileName: currentModule.iconFileName,
            requiredSkills: currentModule.requiredSkills,
            selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
            mutatedAttributes: currentModule.mutatedAttributes,
            mutatedTypeId: currentModule.mutatedTypeId,
            mutatedName: currentModule.mutatedName,
            mutatedIconFileName: currentModule.mutatedIconFileName,
            isSpoolUpFull: currentModule.isSpoolUpFull
        )
    }

    /// 复制模块并更新预热状态（保留突变数据与instanceId）
    private func updatedModule(_ currentModule: SimModule, isSpoolUpFull: Bool) -> SimModule {
        SimModule(
            instanceId: currentModule.instanceId,
            typeId: currentModule.typeId,
            attributes: currentModule.attributes,
            attributesByName: currentModule.attributesByName,
            effects: currentModule.effects,
            groupID: currentModule.groupID,
            status: currentModule.status,
            charge: currentModule.charge,
            flag: currentModule.flag,
            quantity: currentModule.quantity,
            name: currentModule.name,
            iconFileName: currentModule.iconFileName,
            requiredSkills: currentModule.requiredSkills,
            selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
            mutatedAttributes: currentModule.mutatedAttributes,
            mutatedTypeId: currentModule.mutatedTypeId,
            mutatedName: currentModule.mutatedName,
            mutatedIconFileName: currentModule.mutatedIconFileName,
            isSpoolUpFull: isSpoolUpFull
        )
    }

    /// 重新计算属性、标记未保存更改、通知UI并自动保存配置
    private func applyChanges() {
        calculateAttributes()
        hasUnsavedChanges = true
        objectWillChange.send()
        saveConfiguration()
    }

    /// 加载配置后的统一校验（两阶段装配的第二阶段）：
    /// 乐观安装并跑完计算管线后，用**计算后**的同组限制统一校验并降级，有降级则补算一次。
    /// 解决"装配数量/同组上限依赖计算结果（如加成处理器增加脉冲波槽位）而逐个安装时无法得知"的死锁。
    func validateGroupLimitsAfterCalculation() {
        guard let output = simulationOutput else { return }

        let groups = Dictionary(grouping: simulationInput.modules) { $0.groupID }
        var changed = false

        for (groupID, modules) in groups {
            // 同组任一模块的计算后属性即代表该组限制（修饰器来源相同）
            guard let outModule = output.modules.first(where: { $0.groupID == groupID })
            else { continue }

            // 1. 装配数量上限（计算后值）：超限模块按槽位倒序强制离线，保留装配
            let maxFitted = Int(outModule.attributesByName["maxGroupFitted"] ?? 0)
            if maxFitted > 0, modules.count > maxFitted {
                let overflow = modules
                    .sorted { ($0.flag?.rawValue ?? "") > ($1.flag?.rawValue ?? "") }
                    .dropFirst(maxFitted)
                for m in overflow where m.status > 0 {
                    if let idx = simulationInput.modules.firstIndex(where: { $0.instanceId == m.instanceId }) {
                        simulationInput.modules[idx] = m.withStatus(0)
                        changed = true
                        Logger.warning(
                            "装配数量超限（计算后上限 \(maxFitted)），强制离线: \(m.name) @ \(m.flag?.rawValue ?? "?")"
                        )
                    }
                }
            }

            // 2. 同组在线/激活上限（计算后值）：链式降级
            let maxOnline = Int(outModule.attributesByName["maxGroupOnline"] ?? 0)
            let maxActive = Int(outModule.attributesByName["maxGroupActive"] ?? 0)
            if maxOnline > 0 || maxActive > 0 {
                let modified = ModuleGroupManager.handleGroupDowngrade(
                    modules: &simulationInput.modules,
                    groupID: groupID,
                    maxGroupOnline: maxOnline,
                    maxGroupActive: maxActive
                )
                changed = changed || !modified.isEmpty
            }
        }

        if changed {
            Logger.info("计算后同组限制校验发生降级，补算一次属性")
            calculateAttributes()
        }
    }

    /// 查询物品的属性（按ID和按名称，内存索引）
    private func queryTypeAttributes(typeId: Int)
        -> (attributes: [Int: Double], attributesByName: [String: Double])
    {
        SDEMemoryStore.typeAttributesFull(for: typeId)
    }

    /// 加载弹药数据（属性、效果、分组、体积），并将volume写入属性字典
    /// - Parameter useAttributeVolumeFallback: 为true时，若ItemInfoMap无有效体积则回退使用属性表中的volume
    private func loadChargeData(typeId: Int, useAttributeVolumeFallback: Bool) -> (
        attributes: [Int: Double],
        attributesByName: [String: Double],
        effects: [Int],
        groupId: Int,
        volume: Double
    ) {
        var (attributes, attributesByName) = queryTypeAttributes(typeId: typeId)
        let effects = SDEMemoryStore.effectIDs(forType: typeId)
        var groupId = 0
        var volume: Double = useAttributeVolumeFallback ? (attributesByName["volume"] ?? 0) : 0

        // 查询弹药分组和体积
        if let info = ItemInfoMap.typeInfo(for: typeId),
           let id = info.groupID,
           info.volume > 0
        {
            groupId = id
            volume = info.volume
        }

        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume

        return (attributes, attributesByName, effects, groupId, volume)
    }

    /// 加载装备数据（属性、效果、分组、体积、名称、图标），并将volume/capacity写入属性字典
    private func loadModuleInstallData(typeId: Int, logPrefix: String) -> (
        attributes: [Int: Double],
        attributesByName: [String: Double],
        effects: [Int],
        groupId: Int,
        name: String,
        iconFileName: String,
        volume: Double
    ) {
        var (attributes, attributesByName) = queryTypeAttributes(typeId: typeId)
        let effects = SDEMemoryStore.effectIDs(forType: typeId)
        var groupId = 0
        var name = ""
        var iconFileName = ""
        var volume: Double = 0

        // 查询装备分组和体积
        if let info = ItemInfoMap.typeInfo(for: typeId) {
            name = info.name
            iconFileName = info.iconFilename
            if let id = info.groupID {
                groupId = id
            }
            volume = info.volume

            // 获取capacity字段
            if info.capacity > 0 {
                attributes[38] = info.capacity
                attributesByName["capacity"] = info.capacity
                Logger.info("\(logPrefix): \(name), capacity=\(info.capacity)")
            }
        }

        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume

        return (attributes, attributesByName, effects, groupId, name, iconFileName, volume)
    }

    /// 根据装备容量和弹药体积计算可装填的弹药数量
    private func computeChargeQuantity(module: SimModule, chargeVolume: Double, logPrefix: String)
        -> Int?
    {
        guard chargeVolume > 0 else {
            Logger.warning("\(logPrefix)失败: 弹药体积为0")
            return nil
        }

        let capacity = module.attributesByName["capacity"] ?? 0
        guard capacity > 0 else {
            Logger.warning("\(logPrefix)失败: 装备=\(module.name), 容量为0")
            return nil
        }

        let quantity = Int(capacity / chargeVolume)
        Logger.info(
            "\(logPrefix)计算: 装备=\(module.name), 容量=\(capacity), 弹药体积=\(chargeVolume), 计算数量=\(quantity)"
        )
        return quantity
    }

    /// 获取同组装备限制（优先从计算后的输出中获取，没有则从原始属性中获取）
    private func groupLimits(
        outputModule: SimModuleOutput?,
        fallbackAttributesByName: [String: Double]
    ) -> (maxGroupOnline: Int, maxGroupActive: Int) {
        let source = outputModule?.attributesByName ?? fallbackAttributesByName
        return (
            maxGroupOnline: Int(source["maxGroupOnline"] ?? 0),
            maxGroupActive: Int(source["maxGroupActive"] ?? 0)
        )
    }

    /// 计算装备的默认状态（考虑最大可用状态和同组装备限制）
    private func computeDefaultModuleStatus(
        attributes: [Int: Double],
        attributesByName: [String: Double],
        effects: [Int],
        typeId: Int,
        groupId: Int,
        modelName: String
    ) -> Int {
        // 计算最大状态
        let maxStatus = getMaxStatus(
            itemEffects: effects,
            itemAttributes: attributes,
            databaseManager: databaseManager
        )

        // 根据最大状态设置默认状态
        let moduleStatus: Int
        switch maxStatus {
        case 2, 3: // 可激活/可超载
            moduleStatus = 2 // 默认为激活状态
        case 1: // 可在线
            moduleStatus = 1 // 默认为在线状态
        default:
            moduleStatus = 0 // 默认为离线状态
        }

        // 考虑同组装备限制
        let finalStatus = setStatus(
            itemAttributes: attributes,
            itemAttributesName: attributesByName,
            typeId: typeId,
            typeGroupId: groupId,
            currentModules: simulationInput.modules,
            currentStatus: moduleStatus,
            maxStatus: maxStatus
        )

        Logger.info("计算装备默认状态: \(modelName), 最大状态: \(maxStatus), 设置状态: \(finalStatus)")
        return finalStatus
    }

    // MARK: - 模块状态更新

    /// 更新模块状态
    func updateModuleStatus(flag: FittingFlag, newStatus: Int) {
        // 找到指定槽位的模块
        if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
            // 获取当前模块
            let currentModule = simulationInput.modules[index]

            // 记录原始状态用于日志
            let originalStatus = currentModule.status

            // 检查是否有同组装备限制
            let (maxGroupOnline, maxGroupActive) = groupLimits(
                outputModule: simulationOutput?.modules.first(where: { $0.flag == flag }),
                fallbackAttributesByName: currentModule.attributesByName
            )

            Logger.info(
                """
                装备状态更新检查:
                - 装备: \(currentModule.name)
                - 槽位: \(flag.rawValue)
                - maxGroupOnline: \(maxGroupOnline)
                - maxGroupActive: \(maxGroupActive)
                - 当前状态: \(originalStatus)
                - 新状态: \(newStatus)
                """
            )

            // 首先更新当前模块的状态（保留突变数据）
            simulationInput.modules[index] = updatedModule(currentModule, status: newStatus)

            if maxGroupOnline > 0 || maxGroupActive > 0 {
                // 使用ModuleGroupManager处理同组装备的连锁降级
                ModuleGroupManager.handleGroupDowngrade(
                    modules: &simulationInput.modules,
                    groupID: currentModule.groupID,
                    maxGroupOnline: maxGroupOnline,
                    maxGroupActive: maxGroupActive,
                    excludeFlags: [flag] // 不降级当前正在设置的装备
                )
            }

            // 重新计算属性
            Logger.info("更新装备状态，重新计算属性")
            applyChanges()

            Logger.info("更新模块状态成功: \(currentModule.name), 从 \(originalStatus) 到 \(newStatus)")
        }
    }

    func updateModuleSpoolUpFull(flag: FittingFlag, isFull: Bool) {
        guard let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) else { return }
        let currentModule = simulationInput.modules[index]
        if currentModule.isSpoolUpFull == isFull {
            return
        }

        simulationInput.modules[index] = updatedModule(currentModule, isSpoolUpFull: isFull)

        Logger.info(
            "更新装备完全预热: \(currentModule.name), isSpoolUpFull=\(isFull)"
        )
        applyChanges()
    }

    func batchUpdateModuleSpoolUpFull(flags: [FittingFlag], isFull: Bool) {
        var didChange = false
        for flag in flags {
            guard let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) else {
                continue
            }
            let currentModule = simulationInput.modules[index]
            if currentModule.isSpoolUpFull == isFull {
                continue
            }
            didChange = true
            simulationInput.modules[index] = updatedModule(currentModule, isSpoolUpFull: isFull)
        }
        guard didChange else { return }

        Logger.info("批量更新装备完全预热: \(flags.count) 个槽位, isSpoolUpFull=\(isFull)")
        applyChanges()
    }

    /// 批量更新模块状态（优化版本，只在最后计算一次属性）
    func batchUpdateModuleStatus(flags: [FittingFlag], newStatus: Int) {
        Logger.info("开始批量更新模块状态: \(flags.count) 个模块，目标状态: \(newStatus)")

        var updatedModules: [SimModule] = []
        var actualUpdatedFlags: [FittingFlag] = []

        for flag in flags {
            if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let currentModule = simulationInput.modules[index]

                // 1. 首先检查模块的最大可用状态
                let maxStatus = getMaxStatus(
                    itemEffects: currentModule.effects,
                    itemAttributes: currentModule.attributes,
                    databaseManager: databaseManager
                )

                // 2. 确保新状态不超过最大可用状态
                let clampedStatus = min(newStatus, maxStatus)

                // 3. 使用setStatus函数考虑同组装备限制
                // 创建不包含当前模块的模块列表，用于状态检查
                var otherModules = simulationInput.modules
                otherModules.remove(at: index)

                // 获取计算后的属性（如果有的话）
                let calculatedAttributesName = simulationOutput?.modules.first(where: {
                    $0.flag == flag
                })?.attributesByName

                let finalStatus = setStatus(
                    itemAttributes: currentModule.attributes,
                    itemAttributesName: currentModule.attributesByName,
                    typeId: currentModule.typeId,
                    typeGroupId: currentModule.groupID,
                    currentModules: otherModules,
                    currentStatus: clampedStatus,
                    maxStatus: maxStatus,
                    calculatedAttributesName: calculatedAttributesName
                )

                // 4. 只有当状态确实需要改变时才更新
                if finalStatus != currentModule.status {
                    // 创建更新后的模块（保留突变数据）
                    let newModule = updatedModule(currentModule, status: finalStatus)

                    // 更新模块列表
                    simulationInput.modules[index] = newModule
                    updatedModules.append(newModule)
                    actualUpdatedFlags.append(flag)

                    Logger.info(
                        "批量更新模块状态: \(currentModule.name), 从 \(currentModule.status) 到 \(finalStatus) (目标: \(newStatus), 最大: \(maxStatus))"
                    )
                } else {
                    Logger.info("模块状态无需更新: \(currentModule.name), 保持状态 \(currentModule.status)")
                }
            }
        }

        // 5. 处理同组装备的连锁反应
        // 如果有模块被更新，需要检查是否影响了其他同组装备
        if !updatedModules.isEmpty {
            // 按组ID分组处理
            let groupedModules = Dictionary(grouping: updatedModules) { $0.groupID }

            for (groupID, modules) in groupedModules {
                if let firstModule = modules.first {
                    let (maxGroupOnline, maxGroupActive) = groupLimits(
                        outputModule: simulationOutput?.modules.first(where: {
                            $0.groupID == groupID
                        }),
                        fallbackAttributesByName: firstModule.attributesByName
                    )

                    // 只有当有同组限制时才处理
                    if maxGroupOnline > 0 || maxGroupActive > 0 {
                        // 使用ModuleGroupManager处理同组装备的连锁降级
                        ModuleGroupManager.handleGroupDowngrade(
                            modules: &simulationInput.modules,
                            groupID: groupID,
                            maxGroupOnline: maxGroupOnline,
                            maxGroupActive: maxGroupActive,
                            excludeFlags: actualUpdatedFlags // 不降级刚刚批量设置的装备
                        )
                    }
                }
            }
        }

        // 只在最后计算一次属性
        Logger.info("批量更新模块状态完成，重新计算属性")
        applyChanges()

        Logger.info("批量更新模块状态成功: \(actualUpdatedFlags.count)/\(flags.count) 个模块实际更新")
    }

    // MARK: - 弹药安装与移除

    /// 批量安装弹药（优化版本，只在最后计算一次属性）
    func batchInstallCharge(typeId: Int, name: String, iconFileName: String?, flags: [FittingFlag]) {
        Logger.info("开始批量安装弹药: \(name) 到 \(flags.count) 个模块")

        // 从数据库加载弹药属性和效果
        let (attributes, attributesByName, effects, groupId, volume) = loadChargeData(
            typeId: typeId, useAttributeVolumeFallback: true
        )

        // 批量安装弹药
        for flag in flags {
            if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let currentModule = simulationInput.modules[index]

                // 计算弹药数量
                let chargeQuantity = computeChargeQuantity(
                    module: currentModule, chargeVolume: volume, logPrefix: "批量安装弹药"
                )

                // 创建弹药对象
                let charge = SimCharge(
                    typeId: typeId,
                    attributes: attributes,
                    attributesByName: attributesByName,
                    effects: effects,
                    groupID: groupId,
                    chargeQuantity: chargeQuantity,
                    requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                    name: name,
                    iconFileName: iconFileName
                )

                // 创建新的模块对象，添加弹药（保留突变数据）
                simulationInput.modules[index] = updatedModule(currentModule, charge: charge)

                Logger.info("批量安装弹药: \(name) 到模块 \(currentModule.name)")
            }
        }

        // 只在最后计算一次属性
        Logger.info("批量安装弹药完成，重新计算属性")
        applyChanges()

        Logger.info("批量安装弹药成功: \(name) 到 \(flags.count) 个模块")
    }

    /// 批量清除弹药（优化版本，只在最后计算一次属性）
    func batchRemoveCharge(flags: [FittingFlag]) {
        Logger.info("开始批量清除弹药: \(flags.count) 个模块")

        for flag in flags {
            if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let currentModule = simulationInput.modules[index]

                // 创建新的模块对象，移除弹药（保留突变数据）
                simulationInput.modules[index] = updatedModule(currentModule, charge: nil)

                Logger.info("批量清除弹药: 模块 \(currentModule.name)")
            }
        }

        // 只在最后计算一次属性
        Logger.info("批量清除弹药完成，重新计算属性")
        applyChanges()

        Logger.info("批量清除弹药成功: \(flags.count) 个模块")
    }

    /// 安装弹药到指定槽位的装备
    func installCharge(typeId: Int, name: String, iconFileName: String?, flag: FittingFlag) {
        // 找到指定槽位的模块
        if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
            // 获取当前模块
            let currentModule = simulationInput.modules[index]

            // 从数据库加载弹药属性
            let (attributes, attributesByName, effects, groupId, volume) = loadChargeData(
                typeId: typeId, useAttributeVolumeFallback: false
            )

            // 计算弹药数量
            let chargeQuantity = computeChargeQuantity(
                module: currentModule, chargeVolume: volume, logPrefix: "单独安装弹药"
            )

            // 创建弹药对象
            let charge = SimCharge(
                typeId: typeId,
                attributes: attributes,
                attributesByName: attributesByName,
                effects: effects,
                groupID: groupId,
                chargeQuantity: chargeQuantity,
                requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                name: name,
                iconFileName: iconFileName
            )

            // 创建新的模块对象，添加弹药（保留突变数据）
            simulationInput.modules[index] = updatedModule(currentModule, charge: charge)

            // 重新计算属性
            Logger.info("设置弹药，重新计算属性")
            applyChanges()

            Logger.info("安装弹药成功: \(name) 到 \(currentModule.name), 弹药数量: \(chargeQuantity ?? 0)")
        }
    }

    /// 移除指定槽位装备的弹药
    func removeCharge(flag: FittingFlag) {
        // 找到指定槽位的模块
        if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
            // 获取当前模块
            let currentModule = simulationInput.modules[index]

            // 如果当前没有弹药，直接返回
            guard currentModule.charge != nil else { return }

            // 创建新的模块对象，移除弹药（保留突变数据）
            simulationInput.modules[index] = updatedModule(currentModule, charge: nil)

            // 重新计算属性
            Logger.info("移除装备，重新计算属性")
            applyChanges()

            Logger.info("移除弹药成功: 从 \(currentModule.name)")
        }
    }

    // MARK: - 装备安装与移除

    /// 安装装备到指定的槽位
    func installModule(typeId: Int, flag: FittingFlag, status: Int = 0) {
        // 清除之前的错误消息
        errorMessage = nil

        // 从数据库加载装备属性和效果
        let (attributes, attributesByName, effects, groupId, model_name, model_iconFilename, volume) =
            loadModuleInstallData(typeId: typeId, logPrefix: "单独安装装备")

        // 获取飞船的炮台和发射器槽位数量
        let (turretSlotsNum, launcherSlotsNum) = calculateDynamicHardpoints()

        // 执行装配检查
        let canInstall = canFit(
            simulationInput: simulationInput,
            itemAttributes: attributes,
            itemAttributesName: attributesByName,
            itemEffects: effects,
            volume: volume,
            typeId: typeId,
            itemGroupID: groupId,
            databaseManager: databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )

        // 如果不能安装，设置错误消息并返回
        if !canInstall {
            errorMessage = "无法安装装备: \(model_name)。该装备不适合当前飞船。"
            Logger.error("装备安装失败: \(model_name) - 无法安装到当前飞船")
            return
        }

        // 如果状态为0（默认值），则计算合适的默认状态
        var moduleStatus = status
        if status == 0 {
            moduleStatus = computeDefaultModuleStatus(
                attributes: attributes,
                attributesByName: attributesByName,
                effects: effects,
                typeId: typeId,
                groupId: groupId,
                modelName: model_name
            )
        }

        // 创建新模块
        let newModule = SimModule(
            typeId: typeId,
            attributes: attributes,
            attributesByName: attributesByName,
            effects: effects,
            groupID: groupId,
            status: moduleStatus,
            charge: nil,
            flag: flag,
            quantity: 1,
            name: model_name,
            iconFileName: model_iconFilename,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes)
        )

        // 移除相同槽位的旧模块（如果有）
        simulationInput.modules.removeAll(where: { $0.flag == flag })

        // 添加新模块
        simulationInput.modules.append(newModule)

        // 计算新属性
        Logger.info("安装装备，重新计算属性")
        applyChanges()

        Logger.info("安装装备成功: \(model_name) 到 \(flag.rawValue), 状态: \(moduleStatus)")
    }

    /// 移除指定槽位的装备
    func removeModule(flag: FittingFlag) {
        // 检查是否有装备
        let initialCount = simulationInput.modules.count

        // 移除指定槽位的模块
        simulationInput.modules.removeAll(where: { $0.flag == flag })

        // 如果数量没变，说明没有移除任何模块
        if simulationInput.modules.count == initialCount {
            return
        }

        // 计算新属性
        Logger.info("移除属性，重新计算属性")
        applyChanges()

        Logger.info("移除槽位\(flag.rawValue)的装备成功")
    }

    /// 更新模块的突变数据
    func updateModuleMutation(flag: FittingFlag, mutaplasmidID: Int?, mutatedAttributes: [Int: Double]) {
        guard let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) else {
            Logger.warning("更新模块突变数据失败: 未找到槽位 \(flag.rawValue)")
            return
        }

        let currentModule = simulationInput.modules[index]

        // 查询突变后的typeID、名称和图标
        var mutatedTypeId: Int? = nil
        var mutatedName: String? = nil
        var mutatedIconFileName: String? = nil

        if let mutaplasmidID = mutaplasmidID {
            if let resultingTypeId = databaseManager.getMutatedTypeID(
                applicableTypeID: currentModule.typeId,
                mutaplasmidID: mutaplasmidID
            ) {
                mutatedTypeId = resultingTypeId

                // 查询突变后的名称和图标
                if let info = ItemInfoMap.typeInfo(for: resultingTypeId) {
                    mutatedName = info.name
                    mutatedIconFileName = info.iconFilename
                }
            }
        }

        let updatedModule = SimModule(
            instanceId: currentModule.instanceId,
            typeId: currentModule.typeId,
            attributes: currentModule.attributes,
            attributesByName: currentModule.attributesByName,
            effects: currentModule.effects,
            groupID: currentModule.groupID,
            status: currentModule.status,
            charge: currentModule.charge,
            flag: currentModule.flag,
            quantity: currentModule.quantity,
            name: currentModule.name,
            iconFileName: currentModule.iconFileName,
            requiredSkills: currentModule.requiredSkills,
            selectedMutaplasmidID: mutaplasmidID,
            mutatedAttributes: mutatedAttributes,
            mutatedTypeId: mutatedTypeId,
            mutatedName: mutatedName,
            mutatedIconFileName: mutatedIconFileName,
            isSpoolUpFull: currentModule.isSpoolUpFull
        )

        simulationInput.modules[index] = updatedModule

        // 重新计算属性（突变会影响属性值）
        Logger.info("更新模块突变数据，重新计算属性")
        applyChanges()

        Logger.info("更新模块突变数据成功: \(currentModule.name), 突变质体ID: \(mutaplasmidID?.description ?? "nil"), 突变属性数量: \(mutatedAttributes.count)")
    }

    /// 安全替换指定槽位的装备（先删除旧装备再安装新装备，如果安装失败则恢复旧装备）
    func replaceModule(typeId: Int, flag: FittingFlag, status: Int = 0) -> Bool {
        // 清除之前的错误消息
        errorMessage = nil

        // 保存旧模块
        let oldModule = simulationInput.modules.first(where: { $0.flag == flag })

        // 如果没有旧模块，直接安装新模块
        if oldModule == nil {
            installModule(typeId: typeId, flag: flag, status: status)
            return true
        }

        // 先删除旧模块
        simulationInput.modules.removeAll(where: { $0.flag == flag })

        // 从数据库加载装备属性和效果
        let (attributes, attributesByName, effects, groupId, model_name, model_iconFilename, volume) =
            loadModuleInstallData(typeId: typeId, logPrefix: "替换装备")

        // 获取飞船的炮台和发射器槽位数量
        let (turretSlotsNum, launcherSlotsNum) = calculateDynamicHardpoints()

        // 执行装配检查
        let canInstall = canFit(
            simulationInput: simulationInput,
            itemAttributes: attributes,
            itemAttributesName: attributesByName,
            itemEffects: effects,
            volume: volume,
            typeId: typeId,
            itemGroupID: groupId,
            databaseManager: databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )

        // 如果不能安装，恢复旧模块并返回失败
        if !canInstall {
            errorMessage = "无法安装装备: \(model_name)。该装备不适合当前飞船。"
            Logger.error("装备替换失败: \(model_name) - 无法安装到当前飞船")

            // 恢复旧模块
            if let oldModule = oldModule {
                simulationInput.modules.append(oldModule)
                Logger.info("撤回装备替换，重新计算属性")
                calculateAttributes()
                objectWillChange.send()
            }

            return false
        }

        // 如果状态为0（默认值），则计算合适的默认状态
        var moduleStatus = status
        if status == 0 {
            moduleStatus = computeDefaultModuleStatus(
                attributes: attributes,
                attributesByName: attributesByName,
                effects: effects,
                typeId: typeId,
                groupId: groupId,
                modelName: model_name
            )
        }

        // 创建新模块（装备更换后清除突变信息）
        let newModule = SimModule(
            typeId: typeId,
            attributes: attributes,
            attributesByName: attributesByName,
            effects: effects,
            groupID: groupId,
            status: moduleStatus,
            charge: nil,
            flag: flag,
            quantity: 1,
            name: model_name,
            iconFileName: model_iconFilename,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
            selectedMutaplasmidID: nil, // 装备更换后清除突变信息
            mutatedAttributes: [:], // 装备更换后清除突变信息
            isSpoolUpFull: oldModule?.isSpoolUpFull ?? true
        )

        // 尝试保留原有装备的弹药
        if let oldCharge = oldModule?.charge {
            // 检查新装备是否可以装载旧弹药
            let canLoadOldCharge = canLoadCharge(
                moduleTypeId: typeId, chargeTypeId: oldCharge.typeId
            )
            if canLoadOldCharge {
                // 重新计算弹药数量（基于新装备的容量）
                var updatedChargeQuantity: Int? = oldCharge.chargeQuantity
                let chargeVolume = oldCharge.attributesByName["volume"] ?? 0
                if chargeVolume > 0 {
                    let newModuleCapacity = attributesByName["capacity"] ?? 0
                    if newModuleCapacity > 0 {
                        updatedChargeQuantity = Int(newModuleCapacity / chargeVolume)
                    }
                }

                // 创建更新后的弹药对象
                let updatedCharge = SimCharge(
                    typeId: oldCharge.typeId,
                    attributes: oldCharge.attributes,
                    attributesByName: oldCharge.attributesByName,
                    effects: oldCharge.effects,
                    groupID: oldCharge.groupID,
                    chargeQuantity: updatedChargeQuantity, // 使用重新计算的数量
                    requiredSkills: oldCharge.requiredSkills,
                    name: oldCharge.name,
                    iconFileName: oldCharge.iconFileName
                )

                // 创建带有更新弹药的新模块（装备更换后清除突变信息）
                let updatedModule = SimModule(
                    instanceId: oldModule?.instanceId ?? UUID(), // 保留原模块的instanceId
                    typeId: typeId,
                    attributes: attributes,
                    attributesByName: attributesByName,
                    effects: effects,
                    groupID: groupId,
                    status: moduleStatus,
                    charge: updatedCharge, // 使用更新后的弹药
                    flag: flag,
                    quantity: 1,
                    name: model_name,
                    iconFileName: model_iconFilename,
                    requiredSkills: newModule.requiredSkills,
                    selectedMutaplasmidID: nil, // 装备更换后清除突变信息
                    mutatedAttributes: [:], // 装备更换后清除突变信息
                    isSpoolUpFull: oldModule?.isSpoolUpFull ?? true
                )

                // 使用带有弹药的模块
                simulationInput.modules.append(updatedModule)
                Logger.info(
                    "替换装备成功并保留弹药: \(model_name) 到 \(flag.rawValue), 弹药: \(oldCharge.name), 重新计算数量: \(updatedChargeQuantity ?? 0)"
                )
            } else {
                // 如果不能装载原有弹药，使用无弹药的模块
                simulationInput.modules.append(newModule)
                Logger.info("替换装备成功但无法保留原有弹药: \(model_name) 到 \(flag.rawValue)")
            }
        } else {
            // 如果原来没有弹药，直接添加新模块
            simulationInput.modules.append(newModule)
        }

        // 计算新属性
        Logger.info("替换装备，重新计算属性")
        applyChanges()

        Logger.info("替换装备成功: \(model_name) 到 \(flag.rawValue), 状态: \(moduleStatus)")
        return true
    }

    func canLoadCharge(moduleTypeId: Int, chargeTypeId: Int) -> Bool {
        // 获取模块的所有属性
        let (_, moduleAttributesByName) = queryTypeAttributes(typeId: moduleTypeId)

        // 获取模块可装载的弹药组和弹药大小
        var chargeGroupIDs: [Int] = []
        var chargeSize: Double? = nil

        for (name, value) in moduleAttributesByName {
            // 收集chargeGroup属性
            if name.hasPrefix("chargeGroup") && value > 0 {
                chargeGroupIDs.append(Int(value))
            }

            // 收集chargeSize属性
            if name == "chargeSize" {
                chargeSize = value
            }
        }

        // 如果没有弹药组，表示不能装载弹药
        if chargeGroupIDs.isEmpty {
            return false
        }

        // 获取弹药的组ID和大小
        var chargeGroupID = 0
        var chargeSizeValue: Double? = nil

        // 查询弹药组ID
        if let groupID = ItemInfoMap.typeInfo(for: chargeTypeId)?.groupID {
            chargeGroupID = groupID
        }

        // 查询弹药大小
        let chargeSizeQuery = """
            SELECT ta.value 
            FROM typeAttributes ta
            JOIN dogmaAttributes dat ON ta.attribute_id = dat.attribute_id
            WHERE ta.type_id = ? AND dat.name = 'chargeSize'
        """

        if case let .success(rows) = databaseManager.executeQuery(
            chargeSizeQuery, parameters: [chargeTypeId]
        ),
            let row = rows.first,
            let value = row["value"] as? Double
        {
            chargeSizeValue = value
        }

        // 检查弹药组是否匹配
        let groupMatches = chargeGroupIDs.contains(chargeGroupID)

        // 检查弹药大小是否匹配
        let sizeMatches: Bool
        if let moduleSize = chargeSize, let ammoSize = chargeSizeValue {
            sizeMatches = moduleSize == ammoSize
        } else {
            // 如果没有大小限制，则认为大小匹配
            sizeMatches = true
        }

        // 同时满足组和大小匹配才能装载
        return groupMatches && sizeMatches
    }
}
