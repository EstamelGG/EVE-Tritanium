import SwiftUI

struct ShipFittingModulesView: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    // 为各类型选择器创建专用的状态对象
    @StateObject var moduleSettingsState = SlotState()
    @StateObject var hiSlotSelectorState = SlotState()
    @StateObject var medSlotSelectorState = SlotState()
    @StateObject var lowSlotSelectorState = SlotState()
    @StateObject var rigSlotSelectorState = SlotState()
    @StateObject var subSysSlotSelectorState = SlotState()
    @StateObject var t3dModeSelectorState = SlotState()

    func getModuleGroups(for slotType: FittingSlotType, totalSlots: Int) -> [ModuleGroup] {
        // 使用组合键来分组：对于有突变的装备，使用 instanceId 作为唯一标识，确保不堆叠
        struct GroupKey: Hashable {
            let typeId: Int
            let hasMutation: Bool
            let mutationKey: String // 对于有突变的装备，使用 instanceId 作为唯一标识

            init(module: SimModule) {
                typeId = module.typeId
                // 判断是否有突变：只有 mutatedAttributes 不为空才认为真正应用了突变
                // 注意：只选择突变质体但未设置属性值的情况不算应用突变
                hasMutation = !module.mutatedAttributes.isEmpty
                // 如果有突变，使用 instanceId 作为唯一标识；否则使用空字符串
                mutationKey = hasMutation ? module.instanceId.uuidString : ""
            }
        }

        struct GroupWithOrder {
            let group: ModuleGroup
            let order: Int
        }

        var groups: [GroupKey: ModuleGroup] = [:]
        var emptySlots: [FittingFlag] = []
        var firstAppearanceOrder: [GroupKey: Int] = [:] // 记录每个组合键的首次出现顺序

        // 收集所有槽位的模块和空槽位，同时记录首次出现顺序
        for index in 0 ..< totalSlots {
            let slotFlag = slotType.getSlotFlag(index: index)

            // 使用辅助函数获取显示模块
            if let installedModule = getDisplayModule(for: slotFlag) {
                // 创建分组键
                let groupKey = GroupKey(module: installedModule)

                // 记录首次出现的顺序（如果还没有记录过）
                if firstAppearanceOrder[groupKey] == nil {
                    firstAppearanceOrder[groupKey] = index
                }

                if var group = groups[groupKey] {
                    group.modules.append(installedModule)
                    groups[groupKey] = group
                } else {
                    groups[groupKey] = ModuleGroup(
                        id: "\(installedModule.typeId)-\(groupKey.mutationKey)",
                        typeId: installedModule.typeId,
                        name: installedModule.mutatedName ?? installedModule.name,
                        iconFileName: installedModule.mutatedIconFileName ?? installedModule.iconFileName,
                        modules: [installedModule],
                        emptySlots: []
                    )
                }
            } else {
                // 空槽位
                emptySlots.append(slotFlag)
            }
        }

        // 将分组转换为带顺序的结构
        var groupsWithOrder: [GroupWithOrder] = groups.map { key, group in
            GroupWithOrder(group: group, order: firstAppearanceOrder[key] ?? Int.max)
        }

        // 如果有空槽位，创建一个特殊的空槽位组
        if !emptySlots.isEmpty {
            groupsWithOrder.append(
                GroupWithOrder(
                    group: ModuleGroup(
                        id: "empty", // 空槽位组的固定标识
                        typeId: -1, // 特殊标识空槽位
                        name: slotType.localizedName,
                        iconFileName: nil,
                        modules: [],
                        emptySlots: emptySlots
                    ),
                    order: Int.max // 空槽位组排在最后
                )
            )
        }

        return groupsWithOrder.sorted { first, second in
            // 空槽位组（typeId = -1）排在最后
            if first.group.typeId == -1, second.group.typeId != -1 {
                return false // first 排在后面
            }
            if first.group.typeId != -1, second.group.typeId == -1 {
                return true // first 排在前面
            }

            // 其他情况按首次出现顺序排列
            return first.order < second.order
        }.map { $0.group }
    }

    /// 处理折叠模块组的点击事件
    func handleGroupTap(group: ModuleGroup, slotType: FittingSlotType) {
        if group.typeId == -1 {
            // 空槽位组，打开选择器
            if let firstEmptySlot = group.emptySlots.first {
                switch slotType {
                case .hiSlots:
                    openHiSlotSelector(flag: firstEmptySlot)
                case .medSlots:
                    openMedSlotSelector(flag: firstEmptySlot)
                case .loSlots:
                    openLowSlotSelector(flag: firstEmptySlot)
                case .rigSlots:
                    openRigSlotSelector(flag: firstEmptySlot)
                default:
                    break
                }
            }
        } else {
            // 已安装模块组，打开设置页面
            if let firstModule = group.modules.first {
                openModuleSettings(flag: firstModule.flag!, moduleName: firstModule.name)
            }
        }
    }

    /// 批量安装装备到空槽位（优化版本，只在最后计算一次属性）
    func installModuleToEmptySlots(typeId: Int, emptySlots: [FittingFlag]) {
        Logger.info("开始批量安装装备到空槽位: \(emptySlots.count) 个槽位，装备ID: \(typeId)")

        // 从数据库加载装备属性和效果（只查询一次）
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var groupId = 0
        var model_name = ""
        var model_iconFilename = ""
        var volume: Double = 0

        // 查询装备属性（内存索引）
        (attributes, attributesByName) = SDEMemoryStore.typeAttributesFull(for: typeId)

        // 查询装备效果
        effects = SDEMemoryStore.effectIDs(forType: typeId)

        // 查询装备基本信息，包括capacity
        if let info = ItemInfoMap.typeInfo(for: typeId) {
            model_name = info.name
            model_iconFilename = info.iconFilename
            groupId = info.groupID ?? 0
            volume = info.volume

            // 添加capacity到属性字典中（如果存在）
            if info.capacity > 0 {
                attributes[38] = info.capacity
                attributesByName["capacity"] = info.capacity
                Logger.info("批量安装装备: \(model_name), capacity=\(info.capacity)")
            }
        }

        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume

        var successCount = 0
        var failedFlags: [FittingFlag] = []

        // 批量安装装备
        for flag in emptySlots {
            // 检查是否可以安装（使用已查询的数据）
            if canInstallModuleWithData(
                attributes: attributes,
                attributesByName: attributesByName,
                effects: effects,
                volume: volume,
                typeId: typeId,
                groupId: groupId,
                flag: flag
            ) {
                // 计算合适的默认状态
                let maxStatus = getMaxStatus(
                    itemEffects: effects,
                    itemAttributes: attributes,
                    databaseManager: viewModel.databaseManager
                )

                var moduleStatus: Int
                switch maxStatus {
                case 3: moduleStatus = 2 // 可超载，默认为激活状态
                case 2: moduleStatus = 2 // 可激活，默认为激活状态
                case 1: moduleStatus = 1 // 可在线，默认为在线状态
                default: moduleStatus = 0 // 默认为离线状态
                }

                // 考虑同组装备限制
                moduleStatus = setStatus(
                    itemAttributes: attributes,
                    itemAttributesName: attributesByName,
                    typeId: typeId,
                    typeGroupId: groupId,
                    currentModules: viewModel.simulationInput.modules,
                    currentStatus: moduleStatus,
                    maxStatus: maxStatus
                )

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

                // 添加到模块列表（不触发属性计算）
                viewModel.simulationInput.modules.append(newModule)
                successCount += 1
                Logger.info("批量安装装备到槽位: \(flag.rawValue), 装备: \(model_name)")
            } else {
                failedFlags.append(flag)
                Logger.warning("无法安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                break // 如果有一个槽位无法安装，停止后续安装
            }
        }

        // 只在最后计算一次属性
        if successCount > 0 {
            Logger.info("批量安装装备完成，重新计算属性")
            viewModel.calculateAttributes()

            // 标记有未保存的更改
            viewModel.hasUnsavedChanges = true

            // 自动保存配置
            viewModel.saveConfiguration()
        }

        Logger.info("批量安装装备完成，成功: \(successCount)/\(emptySlots.count)")

        if !failedFlags.isEmpty {
            Logger.warning("批量安装装备部分失败，失败的槽位: \(failedFlags.map { $0.rawValue })")
        }
    }

    /// 使用已有数据检查是否可以安装模块（避免重复数据库查询）
    func canInstallModuleWithData(
        attributes: [Int: Double],
        attributesByName: [String: Double],
        effects: [Int],
        volume: Double,
        typeId: Int,
        groupId: Int,
        flag _: FittingFlag
    ) -> Bool {
        // 只计算实际需要的挂点数量 - 只使用计算后的数据
        guard let outputShip = viewModel.simulationOutput?.ship else {
            return false
        }

        let turretSlotsNum = Int(outputShip.attributesByName["turretSlotsLeft"] ?? 0)
        let launcherSlotsNum = Int(outputShip.attributesByName["launcherSlotsLeft"] ?? 0)

        // 使用canFit函数检查
        return canFit(
            simulationInput: viewModel.simulationInput,
            itemAttributes: attributes,
            itemAttributesName: attributesByName,
            itemEffects: effects,
            volume: volume,
            typeId: typeId,
            itemGroupID: groupId,
            databaseManager: viewModel.databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )
    }

    /// 获取相关模块（同类型的所有模块，但考虑突变情况）
    func getRelatedModules(for module: SimModule, flag: FittingFlag) -> [SimModule] {
        // 确定槽位类型
        let slotType = getSlotType(for: flag)

        // 检查是否处于折叠状态
        let isCollapsed = isSlotTypeCollapsed(slotType)

        if isCollapsed {
            // 判断当前模块是否有突变：只有 mutatedAttributes 不为空才认为真正应用了突变
            let hasMutation = !module.mutatedAttributes.isEmpty

            if hasMutation {
                // 有突变的情况下，只返回具有相同突变标识的模块
                // 需要匹配：相同的 typeId、相同的 selectedMutaplasmidID、相同的 mutatedAttributes
                return viewModel.simulationInput.modules.filter { otherModule in
                    guard otherModule.typeId == module.typeId else { return false }

                    // 检查突变质体ID是否相同
                    let sameMutaplasmidID = otherModule.selectedMutaplasmidID == module.selectedMutaplasmidID

                    // 检查突变属性是否相同（比较字典内容）
                    let sameMutatedAttributes = otherModule.mutatedAttributes == module.mutatedAttributes

                    return sameMutaplasmidID && sameMutatedAttributes
                }
            } else {
                // 没有突变的情况下，返回所有相同typeId且没有突变的模块
                return viewModel.simulationInput.modules.filter { otherModule in
                    guard otherModule.typeId == module.typeId else { return false }
                    // 只包含没有应用突变的模块（mutatedAttributes 为空）
                    let otherHasMutation = !otherModule.mutatedAttributes.isEmpty
                    return !otherHasMutation
                }
            }
        } else {
            // 非折叠状态下，只返回当前模块
            return [module]
        }
    }

    /// 判断是否应该应用批量操作
    func shouldApplyBatchOperations(for module: SimModule) -> Bool {
        guard let flag = module.flag else { return false }
        let slotType = getSlotType(for: flag)
        return isSlotTypeCollapsed(slotType)
    }

    /// 删除所有相关模块
    func deleteAllRelatedModules(for module: SimModule) {
        let relatedModules = viewModel.simulationInput.modules.filter { $0.typeId == module.typeId }
        let flags = relatedModules.compactMap { $0.flag }

        // 批量删除所有相关模块
        batchRemoveModules(flags: flags)

        Logger.info("批量删除装备: \(relatedModules.count) 个 \(module.name)")
    }

    /// 替换所有相关模块
    func replaceAllRelatedModules(for module: SimModule, newTypeId: Int) {
        let relatedModules = viewModel.simulationInput.modules.filter { $0.typeId == module.typeId }
        let flags = relatedModules.compactMap { $0.flag }

        // 批量替换所有相关模块
        batchReplaceModules(flags: flags, newTypeId: newTypeId)

        Logger.info("批量替换装备: \(relatedModules.count) 个 \(module.name) -> 新装备ID: \(newTypeId)")
    }

    /// 批量删除模块（优化版本，只在最后计算一次属性）
    func batchRemoveModules(flags: [FittingFlag]) {
        Logger.info("开始批量删除模块: \(flags.count) 个")

        // 批量删除模块
        for flag in flags {
            viewModel.simulationInput.modules.removeAll(where: { $0.flag == flag })
            Logger.info("批量删除模块: 槽位 \(flag.rawValue)")
        }

        // 只在最后计算一次属性
        Logger.info("批量删除模块完成，重新计算属性")
        viewModel.calculateAttributes()

        // 标记有未保存的更改
        viewModel.hasUnsavedChanges = true

        // 自动保存配置
        viewModel.saveConfiguration()

        Logger.info("批量删除模块成功: \(flags.count) 个")
    }

    /// 批量替换模块（优化版本，只在最后计算一次属性）
    func batchReplaceModules(flags: [FittingFlag], newTypeId: Int) {
        Logger.info("开始批量替换模块: \(flags.count) 个，新装备ID: \(newTypeId)")

        var successCount = 0
        var failedFlags: [FittingFlag] = []

        // 从数据库加载新装备的属性和效果
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var groupId = 0
        var model_name = ""
        var model_iconFilename = ""
        var volume: Double = 0

        // 查询装备属性（内存索引）
        (attributes, attributesByName) = SDEMemoryStore.typeAttributesFull(for: newTypeId)

        // 查询装备效果
        effects = SDEMemoryStore.effectIDs(forType: newTypeId)

        // 查询装备基本信息
        if let info = ItemInfoMap.typeInfo(for: newTypeId) {
            model_name = info.name
            model_iconFilename = info.iconFilename
            groupId = info.groupID ?? 0
            volume = info.volume
        }

        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume

        // 批量替换模块
        for flag in flags {
            if let index = viewModel.simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let oldModule = viewModel.simulationInput.modules[index]

                // 计算合适的默认状态
                let maxStatus = getMaxStatus(
                    itemEffects: effects,
                    itemAttributes: attributes,
                    databaseManager: viewModel.databaseManager
                )

                var moduleStatus: Int
                switch maxStatus {
                case 3: moduleStatus = 2 // 可超载，默认为激活状态
                case 2: moduleStatus = 2 // 可激活，默认为激活状态
                case 1: moduleStatus = 1 // 可在线，默认为在线状态
                default: moduleStatus = 0 // 默认为离线状态
                }

                // 考虑同组装备限制
                moduleStatus = setStatus(
                    itemAttributes: attributes,
                    itemAttributesName: attributesByName,
                    typeId: newTypeId,
                    typeGroupId: groupId,
                    currentModules: viewModel.simulationInput.modules.filter { $0.flag != flag },
                    currentStatus: moduleStatus,
                    maxStatus: maxStatus
                )

                // 尝试保留原有装备的弹药
                if let oldCharge = oldModule.charge {
                    // 检查新装备是否可以装载旧弹药
                    let canLoadOldCharge = viewModel.canLoadCharge(
                        moduleTypeId: newTypeId, chargeTypeId: oldCharge.typeId
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

                        // 创建带有更新弹药的新模块
                        let updatedModule = SimModule(
                            instanceId: oldModule.instanceId, // 保留原模块的instanceId
                            typeId: newTypeId,
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
                            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                            isSpoolUpFull: oldModule.isSpoolUpFull
                        )

                        viewModel.simulationInput.modules[index] = updatedModule
                        Logger.info(
                            "批量替换装备并保留弹药: \(model_name) 到 \(flag.rawValue), 弹药: \(oldCharge.name), 重新计算数量: \(updatedChargeQuantity ?? 0)"
                        )
                    } else {
                        // 如果不能装载原有弹药，使用无弹药的模块
                        let newModule = SimModule(
                            instanceId: oldModule.instanceId, // 保留原模块的instanceId
                            typeId: newTypeId,
                            attributes: attributes,
                            attributesByName: attributesByName,
                            effects: effects,
                            groupID: groupId,
                            status: moduleStatus,
                            charge: nil, // 新模块暂时不保留弹药
                            flag: flag,
                            quantity: 1,
                            name: model_name,
                            iconFileName: model_iconFilename,
                            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                            isSpoolUpFull: oldModule.isSpoolUpFull
                        )

                        viewModel.simulationInput.modules[index] = newModule
                    }
                } else {
                    // 如果原来没有弹药，直接创建新模块
                    let newModule = SimModule(
                        instanceId: oldModule.instanceId, // 保留原模块的instanceId
                        typeId: newTypeId,
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
                        isSpoolUpFull: oldModule.isSpoolUpFull
                    )

                    viewModel.simulationInput.modules[index] = newModule
                }

                successCount += 1
                Logger.info("批量替换装备: \(oldModule.name) -> \(model_name), 槽位: \(flag.rawValue)")
            } else {
                failedFlags.append(flag)
                Logger.error("批量替换装备失败: 找不到槽位 \(flag.rawValue)")
            }
        }

        // 只在最后计算一次属性
        Logger.info("批量替换装备完成，重新计算属性")
        viewModel.calculateAttributes()

        // 标记有未保存的更改
        viewModel.hasUnsavedChanges = true

        // 自动保存配置
        viewModel.saveConfiguration()

        Logger.info("批量替换装备完成，成功: \(successCount)/\(flags.count)")

        if !failedFlags.isEmpty {
            Logger.warning("批量替换装备部分失败，失败的槽位: \(failedFlags.map { $0.rawValue })")
        }
    }

    /// 根据flag获取槽位类型
    func getSlotType(for flag: FittingFlag) -> FittingSlotType? {
        if flag == .t3dModeSlot0 {
            return .t3dModeSlot
        }
        return FittingSlotType.allCases.first { $0.slot != nil && $0.slot == flag.slot }
    }

    /// 检查指定槽位类型是否处于折叠状态
    func isSlotTypeCollapsed(_ slotType: FittingSlotType?) -> Bool {
        guard let slotType = slotType else { return false }

        switch slotType {
        case .hiSlots:
            return viewModel.hiSlotsCollapsed
        case .medSlots:
            return viewModel.medSlotsCollapsed
        case .loSlots:
            return viewModel.loSlotsCollapsed
        case .rigSlots:
            return viewModel.rigSlotsCollapsed
        case .subSystemSlots, .t3dModeSlot:
            return false // 子系统和T3D模式不支持折叠
        }
    }

    /// 获取槽位图标名称
    func getSlotIcon(for slotType: FittingSlotType) -> String {
        switch slotType {
        case .hiSlots:
            return "highSlot"
        case .medSlots:
            return "midSlot"
        case .loSlots:
            return "lowSlot"
        case .rigSlots:
            return "rigSlot"
        case .subSystemSlots:
            return "subSystem"
        case .t3dModeSlot:
            return "subSystem"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 船体属性条
            if let output = viewModel.simulationOutput {
                ShipAttributesView(attributes: output.ship, viewModel: viewModel)
            }

            // 获取飞船槽位数 - 只使用计算后的数据
            if let outputShip = viewModel.simulationOutput?.ship {
                List {
                    let (hiSlotsNum, medSlotsNum, lowSlotsNum) = calculateDynamicSlots()
                    let rigSlotsNum = Int(outputShip.attributesByName["rigSlots"] ?? 0)
                    let subSysSlotsNum = Int(outputShip.attributesByName["maxSubSystems"] ?? 0)

                    // 子系统槽位（如果有）
                    if subSysSlotsNum > 0 {
                        let subSysSlotsNum = 4 // 子系统槽位数修正为4
                        Section(
                            header: sectionHeader(
                                title: FittingSlotType.subSystemSlots.localizedName,
                                iconName: "subSystem"
                            )
                        ) {
                            ForEach(0 ..< subSysSlotsNum, id: \.self) { index in
                                let slotFlag = FittingSlotType.subSystemSlots.getSlotFlag(
                                    index: index
                                )

                                // 查找该槽位是否已安装装备 - 使用辅助函数
                                if let module = getDisplayModule(for: slotFlag) {
                                    filledSlotRow(
                                        module: module,
                                        slotId: slotFlag.rawValue,
                                        slotIndex: index,
                                        slotType: .subSystemSlots
                                    )
                                } else {
                                    emptySlotRow(
                                        icon: "subSystem",
                                        title: FittingSlotType.subSystemSlots.localizedName,
                                        slotId: slotFlag.rawValue,
                                        slotIndex: index,
                                        slotType: .subSystemSlots
                                    )
                                }
                            }
                        }
                    }

                    // 高槽位
                    if hiSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.hiSlots.localizedName,
                                iconName: "highSlot",
                                isCollapsed: viewModel.hiSlotsCollapsed,
                                onToggle: { toggleCollapse(for: .hiSlots) }
                            )
                        ) {
                            if viewModel.hiSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(for: .hiSlots, totalSlots: hiSlotsNum)
                                ForEach(groups) { group in
                                    collapsedGroupRow(group: group, slotType: .hiSlots)
                                        .transition(groupRowTransition)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0 ..< hiSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.hiSlots.getSlotFlag(index: index)

                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        slotRowAnimation(
                                            for: filledSlotRow(
                                                module: module,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .hiSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.hiSlotsCollapsed
                                        )
                                    } else {
                                        slotRowAnimation(
                                            for: emptySlotRow(
                                                icon: "highSlot",
                                                title: FittingSlotType.hiSlots.localizedName,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .hiSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.hiSlotsCollapsed
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // 中槽位
                    if medSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.medSlots.localizedName,
                                iconName: "midSlot",
                                isCollapsed: viewModel.medSlotsCollapsed,
                                onToggle: { toggleCollapse(for: .medSlots) }
                            )
                        ) {
                            if viewModel.medSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(
                                    for: .medSlots, totalSlots: medSlotsNum
                                )
                                ForEach(groups) { group in
                                    collapsedGroupRow(group: group, slotType: .medSlots)
                                        .transition(groupRowTransition)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0 ..< medSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.medSlots.getSlotFlag(
                                        index: index
                                    )

                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        slotRowAnimation(
                                            for: filledSlotRow(
                                                module: module,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .medSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.medSlotsCollapsed
                                        )
                                    } else {
                                        slotRowAnimation(
                                            for: emptySlotRow(
                                                icon: "midSlot",
                                                title: FittingSlotType.medSlots.localizedName,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .medSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.medSlotsCollapsed
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // 低槽位
                    if lowSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.loSlots.localizedName,
                                iconName: "lowSlot",
                                isCollapsed: viewModel.loSlotsCollapsed,
                                onToggle: { toggleCollapse(for: .loSlots) }
                            )
                        ) {
                            if viewModel.loSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(for: .loSlots, totalSlots: lowSlotsNum)
                                ForEach(groups) { group in
                                    collapsedGroupRow(group: group, slotType: .loSlots)
                                        .transition(groupRowTransition)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0 ..< lowSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.loSlots.getSlotFlag(index: index)

                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        slotRowAnimation(
                                            for: filledSlotRow(
                                                module: module,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .loSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.loSlotsCollapsed
                                        )
                                    } else {
                                        slotRowAnimation(
                                            for: emptySlotRow(
                                                icon: "lowSlot",
                                                title: FittingSlotType.loSlots.localizedName,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .loSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.loSlotsCollapsed
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // 改装槽位
                    if rigSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.rigSlots.localizedName,
                                iconName: "rigSlot",
                                isCollapsed: viewModel.rigSlotsCollapsed,
                                onToggle: { toggleCollapse(for: .rigSlots) }
                            )
                        ) {
                            if viewModel.rigSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(
                                    for: .rigSlots, totalSlots: rigSlotsNum
                                )
                                ForEach(groups) { group in
                                    collapsedGroupRow(group: group, slotType: .rigSlots)
                                        .transition(groupRowTransition)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0 ..< rigSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.rigSlots.getSlotFlag(
                                        index: index
                                    )

                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        slotRowAnimation(
                                            for: filledSlotRow(
                                                module: module,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .rigSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.rigSlotsCollapsed
                                        )
                                    } else {
                                        slotRowAnimation(
                                            for: emptySlotRow(
                                                icon: "rigSlot",
                                                title: FittingSlotType.rigSlots.localizedName,
                                                slotId: slotFlag.rawValue,
                                                slotIndex: index,
                                                slotType: .rigSlots
                                            ),
                                            index: index,
                                            isCollapsed: viewModel.rigSlotsCollapsed
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // 模式槽位（如果是模式切换飞船）
                    if ModeSwitchingUtils.isModeSwitchingShip(
                        shipTypeId: outputShip.typeId,
                        databaseManager: viewModel.databaseManager
                    ) {
                        Section(
                            header: sectionHeader(
                                title: FittingSlotType.t3dModeSlot.localizedName,
                                iconName: "subSystem"
                            )
                        ) {
                            let slotFlag = FittingSlotType.t3dModeSlot.getSlotFlag(index: 0)

                            // 查找该槽位是否已安装装备 - 使用辅助函数
                            if let module = getDisplayModule(for: slotFlag) {
                                filledSlotRow(
                                    module: module,
                                    slotId: slotFlag.rawValue,
                                    slotIndex: 0,
                                    slotType: .t3dModeSlot
                                )
                            } else {
                                emptySlotRow(
                                    icon: "subSystem",
                                    title: FittingSlotType.t3dModeSlot.localizedName,
                                    slotId: "T3DMode",
                                    slotIndex: 0,
                                    slotType: .t3dModeSlot
                                )
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                // 高槽选择器
                .sheet(item: $hiSlotSelectorState.slotFlag) { flag in
                    HiSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.hiSlotsCollapsed {
                                let groups = getModuleGroups(
                                    for: .hiSlots, totalSlots: calculateDynamicSlots().hiSlots
                                )
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(
                                        typeId: typeId, emptySlots: emptyGroup.emptySlots
                                    )
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装装备到槽位: \(flag.rawValue)")
                            }
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 中槽选择器
                .sheet(item: $medSlotSelectorState.slotFlag) { flag in
                    MedSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.medSlotsCollapsed {
                                let groups = getModuleGroups(
                                    for: .medSlots, totalSlots: calculateDynamicSlots().medSlots
                                )
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(
                                        typeId: typeId, emptySlots: emptyGroup.emptySlots
                                    )
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装装备到槽位: \(flag.rawValue)")
                            }
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 低槽选择器
                .sheet(item: $lowSlotSelectorState.slotFlag) { flag in
                    LowSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.loSlotsCollapsed {
                                let groups = getModuleGroups(
                                    for: .loSlots, totalSlots: calculateDynamicSlots().lowSlots
                                )
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(
                                        typeId: typeId, emptySlots: emptyGroup.emptySlots
                                    )
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装装备到槽位: \(flag.rawValue)")
                            }
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 改装槽选择器
                .sheet(item: $rigSlotSelectorState.slotFlag) { flag in
                    RigSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        shipTypeID: outputShip.typeId,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.rigSlotsCollapsed {
                                let rigSlotsNum = Int(outputShip.attributesByName["rigSlots"] ?? 0)
                                let groups = getModuleGroups(
                                    for: .rigSlots, totalSlots: rigSlotsNum
                                )
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(
                                        typeId: typeId, emptySlots: emptyGroup.emptySlots
                                    )
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装改装件到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装改装件到槽位: \(flag.rawValue)")
                            }
                        }
                    )
                }
                // 子系统槽选择器
                .sheet(item: $subSysSlotSelectorState.slotFlag) { flag in
                    SubSysSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        shipTypeID: outputShip.typeId,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 安装装备到选定的槽位
                            Logger.info("安装子系统到槽位: \(flag.rawValue), 装备ID: \(typeId)")

                            // 使用模型的安装方法，让模型内部计算并设置合适的状态
                            viewModel.installModule(typeId: typeId, flag: flag)

                            Logger.info("已安装子系统到槽位: \(flag.rawValue)")
                        }
                    )
                }
                // T3D模式选择器
                .sheet(item: $t3dModeSelectorState.slotFlag) { flag in
                    T3DModeSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 安装T3D模式到选定的槽位
                            Logger.info("安装T3D模式到槽位: \(flag.rawValue), 模式ID: \(typeId)")

                            // 对T3D模式，我们希望它默认为激活状态
                            viewModel.installModule(typeId: typeId, flag: flag, status: 2)

                            Logger.info("已安装T3D模式到槽位: \(flag.rawValue), 状态: 2")
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 装备设置视图
                .sheet(item: $moduleSettingsState.slotFlag) { flag in
                    if let module = viewModel.simulationInput.modules.first(where: {
                        $0.flag == flag
                    }) {
                        // 检查是否是折叠模式，如果是，需要传递同类型的所有模块
                        let relatedModules = getRelatedModules(for: module, flag: flag)

                        ModuleSettingsView(
                            module: module,
                            slotFlag: flag,
                            databaseManager: viewModel.databaseManager,
                            viewModel: viewModel,
                            relatedModules: relatedModules,
                            onDelete: {
                                // 删除装备 - 如果是批量模式，删除所有相同类型的装备
                                if shouldApplyBatchOperations(for: module) {
                                    deleteAllRelatedModules(for: module)
                                } else {
                                    viewModel.removeModule(flag: flag)
                                }
                                Logger.info("已删除装备，槽位: \(flag.rawValue)")
                            },
                            onReplaceModule: { newTypeId in
                                // 替换装备 - 如果是批量模式，替换所有相同类型的装备
                                if shouldApplyBatchOperations(for: module) {
                                    replaceAllRelatedModules(for: module, newTypeId: newTypeId)
                                } else {
                                    let success = viewModel.replaceModule(
                                        typeId: newTypeId, flag: flag
                                    )
                                    if success {
                                        Logger.info(
                                            "已替换装备，槽位: \(flag.rawValue), 新装备ID: \(newTypeId)"
                                        )
                                    } else {
                                        Logger.error(
                                            "替换装备失败，槽位: \(flag.rawValue), 新装备ID: \(newTypeId)"
                                        )
                                    }
                                }
                            }
                        )
                    }
                }
            } else {
                // 如果没有计算后的数据，显示加载状态
                VStack {
                    Text("Calc...")
                        .foregroundColor(.secondary)
                        .font(.headline)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }
}
