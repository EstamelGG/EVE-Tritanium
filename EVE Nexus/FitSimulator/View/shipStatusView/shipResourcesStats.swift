import SwiftUI

struct ShipResourcesStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var slotsValues: [String: Int] = [:]
    @State private var resourceValues: [String: Double] = [:]

    /// 计算当前已安装的炮台数量
    private var turretUsed: Int {
        var count = 0
        for module in viewModel.simulationInput.modules {
            if module.effects.contains(42) { // 炮台效果
                count += 1
            }
        }
        return count
    }

    /// 计算当前已安装的发射器数量
    private var launcherUsed: Int {
        var count = 0
        for module in viewModel.simulationInput.modules {
            if module.effects.contains(40) { // 发射器效果
                count += 1
            }
        }
        return count
    }

    var body: some View {
        Section {
            VStack(spacing: 4) {
                // 第一行：炮台、发射器、改装值、无人机数量
                HStack(spacing: 8) {
                    Spacer(minLength: 8)

                    // 炮台数
                    StatsAttributeValueView(
                        icon: "gunSlot",
                        current: turretUsed,
                        total: slotsValues["turretSlotsLeft"] ?? 0
                    )

                    Spacer()

                    // 发射器数
                    StatsAttributeValueView(
                        icon: "missSlot",
                        current: launcherUsed,
                        total: slotsValues["launcherSlotsLeft"] ?? 0
                    )

                    Spacer()

                    // 改装值
                    let rigUsed = viewModel.simulationInput.modules.reduce(0.0) { sum, module in
                        sum
                            + (module.status >= 1
                                ? (module.attributesByName["upgradeCost"] ?? 0) : 0)
                    }
                    StatsAttributeValueView(
                        icon: "rigcost",
                        current: Int(rigUsed),
                        total: slotsValues["upgradeCapacity"] ?? 0
                    )

                    Spacer()

                    // 无人机在线数
                    StatsAttributeValueView(
                        icon: "drone_online",
                        current: viewModel.droneAttributes.activeDronesCount,
                        total: viewModel.maxActiveDrones
                    )

                    Spacer(minLength: 8)
                }

                Divider()

                // 第二行：CPU、无人机舱
                HStack(spacing: 8) {
                    // CPU使用情况
                    AttributeProgressView(
                        icon: "cpu",
                        current: resourceValues["cpuUsed"] ?? 0,
                        total: resourceValues["cpuTotal"] ?? 0,
                        unit: "Tf"
                    )
                    .frame(maxWidth: .infinity)

                    // 无人机舱容量
                    AttributeProgressView(
                        icon: "drone_cargo",
                        current: viewModel.droneAttributes.capacity.current,
                        total: viewModel.droneAttributes.capacity.total,
                        unit: "m³"
                    )
                    .frame(maxWidth: .infinity)
                }

                // 第三行：PG、无人机带宽
                HStack(spacing: 8) {
                    // 电力使用情况
                    AttributeProgressView(
                        icon: "pg",
                        current: resourceValues["pgUsed"] ?? 0,
                        total: resourceValues["pgTotal"] ?? 0,
                        unit: "MW"
                    )
                    .frame(maxWidth: .infinity)

                    // 无人机带宽
                    AttributeProgressView(
                        icon: "drone_band",
                        current: viewModel.droneAttributes.bandwidth.current,
                        total: viewModel.droneAttributes.bandwidth.total,
                        unit: "Mbps"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .lineLimit(1)
            .padding(.vertical, 4)
        } header: {
            HStack {
                Text(NSLocalizedString("Fitting_stat_shipresource", comment: ""))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .font(.system(size: 18))
                Spacer()
            }
        }
        .onReceive(viewModel.$simulationOutput) { output in
            updateValues(output: output)
        }
    }

    /// 更新所有数值
    private func updateValues(output: SimulationOutput?) {
        updateSlotValues(output: output)
        updateResourceValues(output: output)
    }

    /// 更新槽位数值
    private func updateSlotValues(output: SimulationOutput?) {
        if let output {
            Logger.info("使用计算后的属性值更新槽位数")
            slotsValues["turretSlotsLeft"] = Int(
                output.ship.attributesByName["turretSlotsLeft"] ?? 0
            )
            slotsValues["launcherSlotsLeft"] = Int(
                output.ship.attributesByName["launcherSlotsLeft"] ?? 0
            )
            slotsValues["upgradeCapacity"] = Int(
                output.ship.attributesByName["upgradeCapacity"] ?? 0
            )
        } else {
            Logger.info("没有计算结果，使用基础属性值更新槽位数")
            slotsValues["turretSlotsLeft"] = Int(
                viewModel.simulationInput.ship.baseAttributesByName["turretSlotsLeft"] ?? 0
            )
            slotsValues["launcherSlotsLeft"] = Int(
                viewModel.simulationInput.ship.baseAttributesByName["launcherSlotsLeft"] ?? 0
            )
            slotsValues["upgradeCapacity"] = Int(
                viewModel.simulationInput.ship.baseAttributesByName["upgradeCapacity"] ?? 0
            )
        }
    }

    /// 更新资源数值
    private func updateResourceValues(output: SimulationOutput?) {
        // 计算CPU和电力使用情况
        var cpuUsed: Double = 0
        var pgUsed: Double = 0

        if let output {
            // CPU和PG总量
            resourceValues["cpuTotal"] = output.ship.attributesByName["cpuOutput"] ?? 0
            resourceValues["pgTotal"] = output.ship.attributesByName["powerOutput"] ?? 0

            // 计算已使用的CPU和电力
            for module in output.modules {
                if module.status >= 1 {
                    cpuUsed += module.attributesByName["cpu"] ?? 0
                    pgUsed += module.attributesByName["power"] ?? 0
                }
            }
        } else {
            // 使用基础值
            resourceValues["cpuTotal"] =
                viewModel.simulationInput.ship.baseAttributesByName["cpuOutput"] ?? 0
            resourceValues["pgTotal"] =
                viewModel.simulationInput.ship.baseAttributesByName["powerOutput"] ?? 0

            // 计算已使用的CPU和电力
            for module in viewModel.simulationInput.modules {
                if module.status >= 1 {
                    cpuUsed += module.attributesByName["cpu"] ?? 0
                    pgUsed += module.attributesByName["power"] ?? 0
                }
            }
        }

        resourceValues["cpuUsed"] = cpuUsed
        resourceValues["pgUsed"] = pgUsed
    }
}

/// 纯数值属性视图
struct StatsAttributeValueView: View {
    let icon: String
    let current: Int
    let total: Int

    var body: some View {
        HStack {
            IconManager.shared.loadImage(for: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            Text("\(current)/\(total)")
                .font(.caption)
                .foregroundColor(current > total ? .red : .secondary)
        }
    }
}
