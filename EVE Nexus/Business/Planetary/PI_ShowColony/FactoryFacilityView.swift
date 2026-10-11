import SwiftUI

/// 工厂设施视图
struct FactoryFacilityView: View {
    @Environment(\.locale) private var displayLocale
    let pin: PlanetaryPin
    let simulatedPin: Pin.Factory?
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let typeGroupIds: [Int: Int]
    let typeEnNames: [Int: String]
    let schematic: SchematicInfo?
    let currentTime: Date
    var isLive: Bool = true

    /// 获取工厂类型对应的进度条颜色
    private var factoryProgressColor: Color {
        let enName = typeEnNames[pin.typeId]
        let factoryType = FactoryTypeClassifier.classifyFactory(enName: enName)
        let isActive = simulatedPin?.isActive ?? false
        return FactoryTypeClassifier.getProgressColor(for: factoryType, isActive: isActive)
    }

    /// 获取设施图标文件名
    /// 优先级：1. 根据 groupID 和 en_name 映射的图标 2. typeid 对应的图标（兜底）
    private func getFacilityIconName() -> String? {
        // 尝试使用映射规则获取图标
        if let groupId = typeGroupIds[pin.typeId] {
            let enName = typeEnNames[pin.typeId]
            let mappedIconName = PlanetaryUtils.getFacilityIconName(groupId: groupId, enName: enName)
            // 如果映射返回了有效的图标名称，使用它
            if !mappedIconName.isEmpty {
                return mappedIconName
            }
        }
        // 兜底：使用 typeid 对应的图标
        return typeIcons[pin.typeId]
    }

    var body: some View {
        // 设施名称和图标
        HStack(alignment: .center, spacing: 12) {
            if let iconName = getFacilityIconName() {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                // 设施名称
                HStack {
                    Text(
                        typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: "")
                    )
                    .fontWeight(.semibold)
                    .lineLimit(1)
                }

                // 加工进度
                if schematic != nil,
                   let simPin = simulatedPin
                {
                    VStack(alignment: .leading, spacing: 2) {
                        if let schematicObj = simPin.schematic {
                            let progress = calculateFactoryProgress(
                                factory: simPin, currentTime: currentTime
                            )

                            PulsingProgressBar(
                                progress: progress,
                                color: factoryProgressColor,
                                showPulse: isLive && simPin.isActive
                            )

                            if simPin.isActive, let lastCycleStartTime = simPin.lastCycleStartTime {
                                let cycleEndTime = lastCycleStartTime.addingTimeInterval(
                                    schematicObj.cycleTime
                                )
                                // 计算相对于模拟时间的时间差，而不是系统当前时间
                                let timeRemaining = cycleEndTime.timeIntervalSince(currentTime)
                                HStack {
                                    Text(NSLocalizedString("Factory_Processing", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                    Text("·")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    let remainingText = FormatUtil.formatSimulatedDuration(max(0, timeRemaining))
                                    Text(remainingText)
                                        .modifier(NumericTimeTransition(text: remainingText, countsDown: true, isEnabled: isLive))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            } else if simPin.hasEnoughInputs() {
                                Text(NSLocalizedString("Factory_Ready", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(NSLocalizedString("Factory_Waiting_Materials", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            PulsingProgressBar(progress: 0, color: .gray, showPulse: false)
                            Text(NSLocalizedString("Factory_No_Recipe", comment: ""))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        PulsingProgressBar(progress: 0, color: .gray, showPulse: false)
                        Text(NSLocalizedString("Factory_No_Recipe", comment: ""))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
            }
        }

        // 输入和输出物品
        if let schematic = schematic {
            // 输入物品
            ForEach(Array(schematic.inputs.enumerated()), id: \.offset) { _, input in
                // 计算库存占比（在 ViewBuilder 外部计算）
                let currentAmount: Int = {
                    if let simPin = simulatedPin {
                        return Int(simPin.contents.first(where: { $0.key.id == input.typeId })?.value ?? 0)
                    } else {
                        return Int(pin.contents?.first(where: { $0.typeId == input.typeId })?.amount ?? 0)
                    }
                }()
                let requiredAmount = input.value
                let inventoryRatio = requiredAmount > 0 ? min(Double(currentAmount) / Double(requiredAmount), 1.0) : 0.0

                NavigationLink(
                    destination: ShowPlanetaryInfo(
                        itemID: input.typeId, databaseManager: DatabaseManager.shared
                    )
                ) {
                    HStack(alignment: .center, spacing: 12) {
                        // 图标容器，带背景颜色和库存占比显示
                        // 使用外层圆角作为蒙版，内部元素无需圆角
                        ZStack(alignment: .leading) {
                            // 深色底色
                            Rectangle()
                                .fill(PlanetaryFacilityColors.factoryInputIconBackgroundDark)
                                .frame(width: 32, height: 32)

                            // 浅色，根据库存占比从左向右覆盖
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(PlanetaryFacilityColors.factoryInputIconBackgroundLight)
                                    .frame(width: geometry.size.width * inventoryRatio, height: geometry.size.height)
                            }
                            .frame(width: 32, height: 32)

                            // 图标覆盖在背景上
                            Group {
                                if let iconName = typeIcons[input.typeId] {
                                    Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                } else {
                                    // 如果没有图标，显示一个占位符
                                    Image("not_found")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(
                                    NSLocalizedString("Factory_Input", comment: "")
                                        + " \(typeNames[input.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))"
                                )
                            }

                            // 显示当前存储量与需求量的比例
                            if let simPin = simulatedPin {
                                let currentAmount =
                                    simPin.contents.first(where: { $0.key.id == input.typeId })?
                                        .value ?? 0
                                Text(
                                    NSLocalizedString("Factory_Inventory", comment: "")
                                        + " \(currentAmount)/\(input.value)"
                                )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(
                                    currentAmount >= input.value
                                        ? .secondary : currentAmount > 0 ? .blue : .red
                                )
                            } else {
                                let currentAmount =
                                    pin.contents?.first(where: { $0.typeId == input.typeId })?
                                        .amount ?? 0
                                Text(
                                    NSLocalizedString("Factory_Inventory", comment: "")
                                        + " \(currentAmount)/\(input.value)"
                                )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(
                                    currentAmount >= input.value
                                        ? .secondary : currentAmount > 0 ? .blue : .red
                                )
                            }
                        }
                    }
                }
            }

            // 输出物品
            NavigationLink(
                destination: ShowPlanetaryInfo(
                    itemID: schematic.outputTypeId, databaseManager: DatabaseManager.shared
                )
            ) {
                HStack(alignment: .center, spacing: 12) {
                    if let iconName = typeIcons[schematic.outputTypeId] {
                        Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    } else {
                        // 如果没有图标，显示一个占位符
                        Image("not_found")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(
                                NSLocalizedString("Factory_Output", comment: "")
                                    + " \(typeNames[schematic.outputTypeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))"
                            )
                            Spacer()
                            Text("× \(schematic.outputValue)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// 计算工厂进度
    /// - Parameters:
    ///   - factory: 工厂设施
    ///   - currentTime: 当前时间
    /// - Returns: 进度值（0-1）
    private func calculateFactoryProgress(factory: Pin.Factory, currentTime: Date) -> Double {
        // 如果工厂没有配方或不处于活跃状态，进度为0
        guard let schematic = factory.schematic,
              factory.isActive,
              let lastCycleStartTime = factory.lastCycleStartTime
        else {
            return 0
        }

        // 计算已经过去的时间与周期时间的比例
        let elapsed = currentTime.timeIntervalSince(lastCycleStartTime)
        let progress = elapsed / schematic.cycleTime

        // 确保进度在0到1之间
        return min(max(progress, 0), 1)
    }
}
