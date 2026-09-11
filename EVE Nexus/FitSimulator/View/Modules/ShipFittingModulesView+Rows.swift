import SwiftUI

extension ShipFittingModulesView {
    func getDisplayModule(for flag: FittingFlag) -> SimModule? {
        // 只使用计算后的模块数据进行显示
        guard let outputModules = viewModel.simulationOutput?.modules,
              let outputModule = outputModules.first(where: { $0.flag == flag })
        else {
            return nil
        }

        // 从simulationInput获取突变信息（如果有）
        let inputModule = viewModel.simulationInput.modules.first(where: { $0.flag == flag })
        let mutatedTypeId = inputModule?.mutatedTypeId
        let mutatedName = inputModule?.mutatedName
        let mutatedIconFileName = inputModule?.mutatedIconFileName
        let selectedMutaplasmidID = inputModule?.selectedMutaplasmidID
        let mutatedAttributes = inputModule?.mutatedAttributes ?? [:]

        // 从输出模块创建显示用的SimModule对象，使用突变后的名称和图标（如果有）
        return SimModule(
            instanceId: outputModule.instanceId,
            typeId: outputModule.typeId,
            attributes: outputModule.attributes,
            attributesByName: outputModule.attributesByName,
            effects: outputModule.effects,
            groupID: outputModule.groupID,
            status: outputModule.status,
            charge: outputModule.charge.map { outputCharge in
                SimCharge(
                    typeId: outputCharge.typeId,
                    attributes: outputCharge.attributes,
                    attributesByName: outputCharge.attributesByName,
                    effects: outputCharge.effects,
                    groupID: outputCharge.groupID,
                    chargeQuantity: outputCharge.chargeQuantity,
                    requiredSkills: outputCharge.requiredSkills,
                    name: outputCharge.name,
                    iconFileName: outputCharge.iconFileName
                )
            },
            flag: outputModule.flag,
            quantity: outputModule.quantity,
            name: mutatedName ?? outputModule.name, // 使用突变后的名称（如果有）
            iconFileName: mutatedIconFileName ?? outputModule.iconFileName, // 使用突变后的图标（如果有）
            requiredSkills: FitConvert.extractRequiredSkills(attributes: outputModule.attributes),
            selectedMutaplasmidID: selectedMutaplasmidID,
            mutatedAttributes: mutatedAttributes,
            mutatedTypeId: mutatedTypeId,
            mutatedName: mutatedName,
            mutatedIconFileName: mutatedIconFileName,
            isSpoolUpFull: inputModule?.isSpoolUpFull ?? true
        )
    }

    /// 计算动态槽位数（考虑子系统修饰器）
    func calculateDynamicSlots() -> (hiSlots: Int, medSlots: Int, lowSlots: Int) {
        // 获取基础槽位数 - 只使用计算后的数据
        guard let outputShip = viewModel.simulationOutput?.ship else {
            // 如果没有计算后的数据，返回默认值
            return (hiSlots: 0, medSlots: 0, lowSlots: 0)
        }

        let baseHiSlots = Int(outputShip.attributesByName["hiSlots"] ?? 0)
        let baseMedSlots = Int(outputShip.attributesByName["medSlots"] ?? 0)
        let baseLowSlots = Int(outputShip.attributesByName["lowSlots"] ?? 0)
        Logger.info("动态槽位计算结果 - 高槽: \(baseHiSlots), 中槽: \(baseMedSlots), 低槽: \(baseLowSlots)")

        return (hiSlots: baseHiSlots, medSlots: baseMedSlots, lowSlots: baseLowSlots)
    }

    /// 获取模块状态图标
    func getStatusIcon(status: Int) -> some View {
        switch status {
        case 0:
            return IconManager.shared.loadImage(for: "offline")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 1:
            return IconManager.shared.loadImage(for: "online")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 2:
            return IconManager.shared.loadImage(for: "active")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 3:
            return IconManager.shared.loadImage(for: "overheating")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        default:
            return IconManager.shared.loadImage(for: "offline")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }

    /// 统一所有打开选择器的函数
    func openHiSlotSelector(flag: FittingFlag) {
        hiSlotSelectorState.slotFlag = flag
        Logger.info("打开高槽装备选择器，槽位标识：\(flag.rawValue)")
    }

    func openMedSlotSelector(flag: FittingFlag) {
        medSlotSelectorState.slotFlag = flag
        Logger.info("打开中槽装备选择器，槽位标识：\(flag.rawValue)")
    }

    func openLowSlotSelector(flag: FittingFlag) {
        lowSlotSelectorState.slotFlag = flag
        Logger.info("打开低槽装备选择器，槽位标识：\(flag.rawValue)")
    }

    func openRigSlotSelector(flag: FittingFlag) {
        rigSlotSelectorState.slotFlag = flag
        Logger.info("打开改装槽装备选择器，槽位标识：\(flag.rawValue)")
    }

    func openSubSysSlotSelector(flag: FittingFlag) {
        subSysSlotSelectorState.slotFlag = flag
        Logger.info("打开子系统选择器，槽位标识：\(flag.rawValue)")
    }

    func openT3DModeSelector(flag: FittingFlag) {
        t3dModeSelectorState.slotFlag = flag
        Logger.info("打开T3D模式选择器，槽位标识：\(flag.rawValue)")
    }

    /// 打开装备设置视图
    func openModuleSettings(flag: FittingFlag, moduleName: String) {
        moduleSettingsState.slotFlag = flag
        Logger.info("打开装备设置，槽位: \(flag.rawValue), 装备: \(moduleName)")
    }

    func sectionHeader(title: String, iconName: String) -> some View {
        HStack {
            IconManager.shared.loadImage(for: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            Text(title)
        }
    }

    /// 带折叠按钮的区域头部视图
    func sectionHeaderWithCollapse(
        title: String, iconName: String, isCollapsed: Bool, onToggle: @escaping () -> Void
    ) -> some View {
        HStack {
            IconManager.shared.loadImage(for: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            Text(title)

            Spacer()

            Button(action: onToggle) {
                Image(
                    systemName: isCollapsed
                        ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                )
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .contentTransition(.opacity)
            }
        }
    }

    // MARK: - 折叠/展开动画

    /// 折叠/展开的统一弹簧动画
    var collapseAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.85)
    }

    /// 分组行的过渡：折叠时从顶部淡入并轻微缩放归位，展开时快速淡出
    var groupRowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
            removal: .opacity
        )
    }

    /// 槽位行的过渡：展开时从上方滑入，折叠时淡出收拢
    var slotRowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }

    /// 切换指定槽位类型的折叠状态（带弹簧动画）
    func toggleCollapse(for slotType: FittingSlotType) {
        withAnimation(collapseAnimation) {
            switch slotType {
            case .hiSlots:
                viewModel.hiSlotsCollapsed.toggle()
            case .medSlots:
                viewModel.medSlotsCollapsed.toggle()
            case .loSlots:
                viewModel.loSlotsCollapsed.toggle()
            case .rigSlots:
                viewModel.rigSlotsCollapsed.toggle()
            case .subSystemSlots, .t3dModeSlot:
                break // 子系统和T3D模式不支持折叠
            }
        }
    }

    /// 为槽位行应用展开过渡与波浪式（staggered）延迟动画
    func slotRowAnimation(for row: some View, index: Int, isCollapsed: Bool) -> some View {
        row
            .transition(slotRowTransition)
            .animation(collapseAnimation.delay(Double(index) * 0.03), value: isCollapsed)
    }

    /// 统一的模块行视图组件
    func ModuleRowView(
        iconName: String?,
        isIconPlaceholder _: Bool = false,
        iconOpacity: Double = 1.0,
        title: String,
        titleColor: Color = .primary,
        subtitle: String? = nil,
        charge: SimCharge? = nil,
        moduleForCapacity: SimModule? = nil,
        module: SimModule? = nil,
        rightContent: AnyView? = nil,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack {
            // 装备图标
            if let iconName = iconName {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .opacity(iconOpacity)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                IconManager.shared.loadImage(for: "not_found")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            // 右侧垂直布局：装备名称和其他信息
            VStack(alignment: .leading, spacing: 2) {
                // 第一行：装备名称和副标题
                HStack(spacing: 8) {
                    Text(title)
                        .foregroundColor(titleColor)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 第二行：弹药信息（如果有）
                if let charge = charge {
                    HStack(spacing: 4) {
                        // 弹药图标
                        if let iconFileName = charge.iconFileName {
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                        } else {
                            // 如果没有弹药图标，使用占位图标
                            Image(systemName: "circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.secondary)
                        }

                        // 弹药名称
                        Text(charge.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        // 显示弹药数量
                        if let chargeQuantity = charge.chargeQuantity {
                            // 如果有存储的弹药数量，直接显示
                            Text("×\(chargeQuantity)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let chargeVolume = charge.attributesByName["volume"],
                                  chargeVolume > 0,
                                  let module = moduleForCapacity
                        {
                            // 从模块属性中获取容量并计算
                            let capacity = module.attributesByName["capacity"] ?? 0
                            if capacity > 0 {
                                let ammoCount = Int(capacity / chargeVolume)
                                Text("×\(ammoCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if let module = module {
                    // 特殊属性展示（射程/维修/加成/指挥脉冲等）见 ShipFittingModulesView+ModuleAttributes.swift
                    moduleSpecialAttributeRows(module: module)
                }
            }

            Spacer()

            // 右侧内容（如状态图标等）
            if let rightContent = rightContent {
                rightContent
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = title
            } label: {
                Label(
                    NSLocalizedString("Misc_Copy_Module_Name", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// 折叠模式下的分组行视图
    func collapsedGroupRow(group: ModuleGroup, slotType: FittingSlotType) -> some View {
        // 如果有突变，使用突变后的图标和名称
        let displayIcon = group.typeId == -1 ? getSlotIcon(for: slotType) : (group.modules.first?.mutatedIconFileName ?? group.iconFileName)
        let displayName = group.typeId == -1 ? group.name : (group.modules.first?.mutatedName ?? group.name)
        return ModuleRowView(
            iconName: displayIcon,
            iconOpacity: group.typeId == -1 ? 0.6 : 1.0,
            title: displayName,
            titleColor: group.typeId == -1 ? .secondary : .primary,
            subtitle: "×\(group.totalCount)",
            charge: group.typeId != -1 ? group.modules.first?.charge : nil,
            moduleForCapacity: group.modules.first,
            module: group.typeId != -1 ? group.modules.first : nil,
            rightContent: group.typeId != -1 && group.modules.first != nil
                ? AnyView(getStatusIcon(status: group.modules.first!.status)) : nil
        ) {
            handleGroupTap(group: group, slotType: slotType)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    /// 已安装装备的行视图
    func filledSlotRow(
        module: SimModule, slotId _: String, slotIndex: Int, slotType: FittingSlotType
    ) -> some View {
        ModuleRowView(
            iconName: module.mutatedIconFileName ?? module.iconFileName,
            title: module.mutatedName ?? module.name,
            charge: module.charge,
            moduleForCapacity: module,
            module: module,
            rightContent: AnyView(getStatusIcon(status: module.status))
        ) {
            // 处理点击事件，获取当前槽位的flag
            let slotFlag = slotType.getSlotFlag(index: slotIndex)

            // 记录点击日志
            Logger.info("点击了已安装装备: \(module.name), 槽位: \(slotFlag.rawValue)")

            // 使用统一的打开函数
            openModuleSettings(flag: slotFlag, moduleName: module.name)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    /// 空槽位行视图，增加了slotId、slotIndex和slotType参数
    func emptySlotRow(
        icon: String, title: String, slotId: String, slotIndex: Int,
        slotType: FittingSlotType? = nil
    ) -> some View {
        HStack {
            IconManager.shared.loadImage(for: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .opacity(0.6)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            Text(title)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            // 处理点击事件，根据槽位类型打开不同的选择器
            Logger.info("点击了槽位: \(slotId), 索引: \(slotIndex)")

            if let slotType = slotType {
                let slotFlag = slotType.getSlotFlag(index: slotIndex)

                // 根据槽位类型打开对应的选择器
                switch slotType {
                case .hiSlots:
                    openHiSlotSelector(flag: slotFlag)
                case .medSlots:
                    openMedSlotSelector(flag: slotFlag)
                case .loSlots:
                    openLowSlotSelector(flag: slotFlag)
                case .rigSlots:
                    openRigSlotSelector(flag: slotFlag)
                case .subSystemSlots:
                    openSubSysSlotSelector(flag: slotFlag)
                case .t3dModeSlot:
                    openT3DModeSelector(flag: slotFlag)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}
