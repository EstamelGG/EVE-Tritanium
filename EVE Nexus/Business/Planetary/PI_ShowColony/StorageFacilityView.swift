import SwiftUI

/// 存储设施视图
struct StorageFacilityView: View {
    let pin: PlanetaryPin
    let simulatedPin: Pin?
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let typeVolumes: [Int: Double]
    let typeGroupIds: [Int: Int] // types 表中的 groupID，用于设施图标映射
    let typeMarketGroupIds: [Int: Int] // marketGroupID，用于排序存储内容物
    let typeEnNames: [Int: String] // 添加 typeEnNames 用于图标映射
    let marketPrices: [Int: MarketPriceData] // 仓储物品单价（行星详情页一次 getMarketPrices）
    let capacity: Double
    let hourlySnapshots: [Int: Colony] // 快照数据 [分钟数: 殖民地状态]
    let selectedMinutes: Int // 当前选中的分钟数（0 = 当前时间）
    let realtimeColony: Colony? // 实时模拟的殖民地数据
    let isSnapshotsReady: Bool // 快照是否已计算完成
    let storageVolumeCache: [Int64: [Int: Double]] // 存储设施体积缓存 [pinId: [小时数: 体积]]
    let isColonyStopped: Bool // 殖民地是否已停工
    // 仅指挥中心：在类型名称右侧显示 `upgrade_level`（与殖民地列表文案一致）；非指挥中心为 `nil`
    let commandCenterUpgradeLevel: Int?
    @State private var isChartExpanded = false // 图表是否展开

    /// 检查该仓储是否有传入路由
    private var hasIncomingRoutes: Bool {
        // 优先从实时殖民地检查，如果没有则从快照检查
        if let realtimeColony = realtimeColony {
            return realtimeColony.routes.contains { $0.destinationPinId == pin.pinId }
        }
        // 如果实时殖民地不存在，从快照中检查（使用第一个可用的快照）
        if let firstSnapshot = hourlySnapshots.values.first {
            return firstSnapshot.routes.contains { $0.destinationPinId == pin.pinId }
        }
        return false
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(
                        typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: "")
                    )
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    if let level = commandCenterUpgradeLevel {
                        Spacer(minLength: 0)
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString("Planet_Colony_Upgrade_Level", comment: ""),
                                level
                            )
                        )
                        .font(.subheadline)
                        .fontWeight(.regular)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 容量进度条
                let total = calculateStorageVolume()
                let capacityRatio = capacity > 0 ? total / capacity : 0.0
                let progressColor: Color = {
                    if capacityRatio >= 1.0 {
                        return PlanetaryFacilityColors.storageProgressFull // 已满：红色
                    } else if capacityRatio >= 0.9 {
                        return PlanetaryFacilityColors.storageProgressNearFull // 接近满：橘色
                    } else {
                        return PlanetaryFacilityColors.storageProgressNormal // 正常：蓝色
                    }
                }()
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: total, total: capacity)
                        .progressViewStyle(.linear)
                        .frame(height: 6)
                        .tint(progressColor)

                    Text("\(Int(total.rounded()))m³ / \(Int(capacity))m³")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // 仓储变化图表按钮（仅当有传入路由时显示）
        if hasIncomingRoutes {
            if isSnapshotsReady {
                Button(action: {
                    withAnimation {
                        isChartExpanded.toggle()
                    }
                }) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: isChartExpanded ? "chart.bar.fill" : "chart.bar")
                            .foregroundColor(isColonyStopped ? .gray : .blue)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("Storage_Change_Chart", comment: "仓储变化图表"))
                            .font(.subheadline)
                            .foregroundColor(isColonyStopped ? .gray : .blue)
                        Spacer()
                        Image(systemName: isChartExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isColonyStopped)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            } else {
                // 快照未完成时，显示加载指示器
                HStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 32, height: 32)
                        .tint(.gray)
                    Text(NSLocalizedString("Storage_Change_Chart", comment: "仓储变化图表"))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }

        // 展开的图表
        if isChartExpanded && isSnapshotsReady {
            StorageChangeChartView(
                pinId: pin.pinId,
                selectedMinutes: selectedMinutes,
                capacity: capacity,
                storageVolumeCache: storageVolumeCache
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }

        // 存储的内容物，每个内容物单独一行
        // 按 marketGroupID 从大到小排序，typeid 为次要排序
        if let simPin = simulatedPin {
            ForEach(
                Array(simPin.contents).sorted(by: { item1, item2 in
                    let marketGroupId1 = typeMarketGroupIds[item1.key.id] ?? 0
                    let marketGroupId2 = typeMarketGroupIds[item2.key.id] ?? 0
                    if marketGroupId1 != marketGroupId2 {
                        return marketGroupId1 > marketGroupId2 // marketGroupID 从大到小
                    }
                    return item1.key.id < item2.key.id // typeid 从小到大作为次要排序
                }),
                id: \.key.id
            ) { type, amount in
                if amount > 0 {
                    NavigationLink(
                        destination: ShowPlanetaryInfo(
                            itemID: type.id, databaseManager: DatabaseManager.shared
                        )
                    ) {
                        HStack(alignment: .center, spacing: 12) {
                            if let iconName = typeIcons[type.id] {
                                Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(typeNames[type.id] ?? type.name)
                                    .font(.subheadline)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(amount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    let volume = typeVolumes[type.id] ?? type.volume
                                    let volumePart = "(\(Int(Double(amount) * volume))m³)"
                                    let priceData = marketPrices[type.id]
                                    let unitForEstimate: Double = {
                                        guard let p = priceData else { return 0 }
                                        if p.averagePrice > 0 {
                                            return p.averagePrice
                                        }
                                        if p.adjustedPrice > 0 {
                                            return p.adjustedPrice
                                        }
                                        return 0
                                    }()
                                    if unitForEstimate > 0 {
                                        let estimate = unitForEstimate * Double(amount)
                                        Text("\(volumePart) (\(FormatUtil.formatISK(estimate)))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(volumePart) (—)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }

    /// 计算存储设施的总体积
    private func calculateStorageVolume() -> Double {
        if let simPin = simulatedPin {
            let simContents = simPin.contents.map {
                PlanetaryContent(amount: $0.value, typeId: $0.key.id)
            }
            return calculateTotalVolume(contents: simContents)
        }
        return calculateTotalVolume(contents: pin.contents)
    }

    /// 计算内容物的总体积
    private func calculateTotalVolume(contents: [PlanetaryContent]?) -> Double {
        guard let contents = contents else { return 0 }
        return contents.reduce(0) { sum, content in
            sum + (Double(content.amount) * (typeVolumes[content.typeId] ?? 0))
        }
    }
}
