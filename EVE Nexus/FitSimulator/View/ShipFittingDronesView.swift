import SwiftUI

/// 用于无人机设置的状态类，包装 Int 使其符合 Identifiable
class DroneState: ObservableObject, Identifiable {
    var id: Int {
        droneTypeId ?? 0
    }

    @Published var droneTypeId: Int?
}

struct ShipFittingDronesView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var showingDroneSelector = false
    @State private var showingDroneSettings = false
    @StateObject private var selectedDrone = DroneState()

    /// 获取无人机的计算后属性
    private func getDroneOutput(typeId: Int) -> SimDroneOutput? {
        guard let outputDrones = viewModel.simulationOutput?.drones else {
            return nil
        }

        // 通过typeId查找匹配的无人机输出数据
        return outputDrones.first(where: { $0.typeId == typeId })
    }

    /// 格式化距离显示（与装备模块页面保持一致）
    /// 大于1000km时显示完整数字，不使用k km缩写
    private func formatDistance(_ distance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal

        if distance >= 1000 {
            // 大于等于1km时，使用km单位，保留2位小数
            let value = distance / 1000.0
            formatter.maximumFractionDigits = 2
            let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "0"
            return "\(formattedValue) km"
        } else {
            // 小于1km时，使用m单位
            formatter.maximumFractionDigits = 0
            let formattedValue = formatter.string(from: NSNumber(value: distance)) ?? "0"
            return "\(formattedValue) m"
        }
    }

    /// 格式化速度显示
    private func formatSpeed(_ speed: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: speed)) ?? "0"
    }

    /// 获取无人机的最大射程（从多个射程属性中取最大值）
    private func getDroneMaxRange(_ droneOutput: SimDroneOutput) -> Double {
        let rangeAttributes = [
            "maxRange",
            "shieldTransferRange",
        ]

        var maxRange: Double = 0
        for attribute in rangeAttributes {
            let range = droneOutput.attributesByName[attribute] ?? 0
            if range > maxRange {
                maxRange = range
            }
        }

        return maxRange
    }

    var body: some View {
        VStack(spacing: 0) {
            // 无人机属性条
            DroneAttributesView(viewModel: viewModel)

            // 无人机列表
            List {
                // 使用simulationInput中的实时无人机数据，计算后属性通过getDroneOutput获取
                ForEach(viewModel.simulationInput.drones, id: \.typeId) { drone in
                    HStack {
                        // 无人机图标（优先使用突变后的图标）
                        if let iconFileName = drone.mutatedIconFileName ?? drone.iconFileName {
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "questionmark.square")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.gray)
                        }

                        // 右侧垂直布局：无人机名称和属性信息
                        VStack(alignment: .leading, spacing: 2) {
                            // 第一行：无人机名称和数量（数量显示在名称前面）
                            Text("\(drone.quantity)× \(drone.name)")
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            // 无人机属性展示
                            if let droneOutput = getDroneOutput(typeId: drone.typeId) {
                                // 射程与失准
                                let maxRange = getDroneMaxRange(droneOutput)
                                let falloff = droneOutput.attributesByName["falloff"] ?? 0

                                if maxRange > 0 || falloff > 0 {
                                    HStack(spacing: 4) {
                                        if maxRange > 0 {
                                            // 有maxRange时使用maxRange图标
                                            IconManager.shared.loadImage(for: "target_range")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 20, height: 20)
                                        } else {
                                            // 只有falloff时使用falloff图标
                                            IconManager.shared.loadImage(for: "falloff_mod")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 20, height: 20)
                                        }

                                        HStack(spacing: 0) {
                                            if maxRange > 0 && falloff > 0 {
                                                Text(
                                                    "\(NSLocalizedString("Module_Attribute_Range", comment: ""))+\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): "
                                                )
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                Text(
                                                    "\(formatDistance(maxRange)) + \(formatDistance(falloff))"
                                                )
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                            } else if maxRange > 0 {
                                                Text(
                                                    "\(NSLocalizedString("Module_Attribute_Range", comment: "")): "
                                                )
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                Text("\(formatDistance(maxRange))")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text(
                                                    "\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): "
                                                )
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                Text("\(formatDistance(falloff))")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }

                                // 速度
                                let maxVelocity = droneOutput.attributesByName["maxVelocity"] ?? 0

                                if maxVelocity > 0 {
                                    HStack(spacing: 4) {
                                        IconManager.shared.loadImage(for: "turret_volley")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)

                                        HStack(spacing: 0) {
                                            Text(
                                                "\(NSLocalizedString("Module_Attribute_Speed", comment: "")): "
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            Text("\(formatSpeed(maxVelocity)) m/s")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        Spacer()

                        // 激活状态显示
                        if drone.activeCount > 0 {
                            // 激活数量和图标，使用水平排列并垂直居中
                            HStack(spacing: 0) {
                                // 数字右对齐
                                Text("\(drone.activeCount)×")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 14, alignment: .trailing)
                                    .alignmentGuide(VerticalAlignment.center) { d in
                                        d[VerticalAlignment.center] - 1
                                    }

                                // 小间隔
                                Spacer()
                                    .frame(width: 3)

                                // 图标
                                IconManager.shared.loadImage(for: "active")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                            }
                            .padding(.trailing, 4)
                        } else {
                            // 不激活的无人机，使用在线图标而不是离线图标
                            IconManager.shared.loadImage(for: "online")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDrone.droneTypeId = drone.typeId
                        showingDroneSettings = true
                        // Logger.info("点击了无人机: \(drone.name), ID: \(drone.typeId)")
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        if index < viewModel.simulationInput.drones.count {
                            viewModel.removeDrone(at: index)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // 添加无人机按钮
                Button(action: {
                    showingDroneSelector = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(
                                viewModel.droneAttributes.capacity.total > 0 ? .blue : .gray
                            )
                        Text(NSLocalizedString("Fitting_Add_Drones", comment: ""))
                    }
                }
                .disabled(viewModel.droneAttributes.capacity.total <= 0)
            }
        }
        .sheet(isPresented: $showingDroneSelector) {
            DroneSelectorView(
                databaseManager: viewModel.databaseManager,
                onSelect: { droneItem in
                    addDrone(droneItem)
                }
            )
        }
        .sheet(isPresented: $showingDroneSettings) {
            if let droneTypeId = selectedDrone.droneTypeId,
               let droneIndex = viewModel.simulationInput.drones.firstIndex(where: {
                   $0.typeId == droneTypeId
               })
            {
                let drone = viewModel.simulationInput.drones[droneIndex]
                DroneSettingsView(
                    drone: drone,
                    databaseManager: viewModel.databaseManager,
                    viewModel: viewModel,
                    onDelete: {
                        viewModel.removeDrone(typeId: droneTypeId)
                        showingDroneSettings = false
                    },
                    onUpdateQuantity: { newQuantity, newActiveCount in
                        viewModel.updateDroneQuantity(
                            typeId: droneTypeId, quantity: newQuantity, activeCount: newActiveCount
                        )
                    },
                    onReplaceDrone: { newTypeId in
                        viewModel.replaceDrone(oldTypeId: droneTypeId, newTypeId: newTypeId)
                        // 更新当前选中的无人机ID
                        selectedDrone.droneTypeId = newTypeId
                    }
                )
            }
        }
    }

    /// 添加无人机
    private func addDrone(_ droneItem: DatabaseListItem) {
        // 获取无人机信息
        let droneInfo = viewModel.getDroneInfo(typeId: droneItem.id)

        // 计算可用容量
        let remainingCapacity =
            viewModel.droneAttributes.capacity.total - viewModel.droneAttributes.capacity.current

        // 计算最多能添加多少个无人机
        var maxQuantity = 5 // 默认值

        if let droneVolume = droneInfo?.volume, droneVolume > 0 {
            // 根据剩余舱室容量计算最多能添加几个
            let maxByCapacity = Int(remainingCapacity / droneVolume)
            maxQuantity = min(5, maxByCapacity)
        }

        // 如果无法添加无人机，直接返回
        if maxQuantity <= 0 {
            return
        }

        // 计算可以默认激活的无人机数量
        let maxActivatable = calculateActivableDrones(typeId: droneItem.id, quantity: maxQuantity)

        // 添加无人机
        viewModel.addDrone(
            typeId: droneItem.id,
            name: droneItem.name,
            iconFileName: droneItem.iconFileName,
            quantity: maxQuantity,
            activeCount: maxActivatable
        )
    }

    /// 计算可激活的无人机数量
    private func calculateActivableDrones(typeId: Int, quantity: Int) -> Int {
        // 获取当前激活的无人机总数
        let totalActive = viewModel.droneAttributes.activeDronesCount

        // 获取最大激活数量限制
        let maxActive = viewModel.maxActiveDrones

        // 如果已经达到最大激活数量，不能再激活
        if totalActive >= maxActive {
            return 0
        }

        // 计算可用槽位
        let availableSlots = maxActive - totalActive

        // 获取无人机带宽信息
        let droneInfo = viewModel.getDroneInfo(typeId: typeId)
        let droneBandwidth = droneInfo?.bandwidth ?? 0

        // 计算剩余带宽
        let remainingBandwidth =
            viewModel.droneAttributes.bandwidth.total - viewModel.droneAttributes.bandwidth.current

        // 计算带宽允许激活的最大数量
        let maxByBandwidth = droneBandwidth > 0 ? Int(remainingBandwidth / droneBandwidth) : 0

        // 返回最小值：可用槽位、添加数量、带宽允许数量
        return min(availableSlots, quantity, maxByBandwidth)
    }
}

/// 无人机属性条视图
struct DroneAttributesView: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        VStack(spacing: 12) {
            // 无人机状态行
            HStack(spacing: 8) {
                // 无人机带宽
                AttributeProgressView(
                    icon: "drone_band",
                    current: viewModel.droneAttributes.bandwidth.current,
                    total: viewModel.droneAttributes.bandwidth.total,
                    unit: "Mbps"
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                // 无人机舱容量
                AttributeProgressView(
                    icon: "drone_cargo",
                    current: viewModel.droneAttributes.capacity.current,
                    total: viewModel.droneAttributes.capacity.total,
                    unit: "m³"
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                // 无人机在线数量
                AttributeValueView(
                    icon: "drone_online",
                    current: viewModel.droneAttributes.activeDronesCount,
                    total: viewModel.maxActiveDrones
                )
                .frame(width: 90)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }
}
