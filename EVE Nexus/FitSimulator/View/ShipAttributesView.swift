import SwiftUI

struct ShipAttributesView: View {
    let attributes: SimShipOutput
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var cpuUsed: Double = 0
    @State private var pgUsed: Double = 0
    @State private var rigUsed: Double = 0
    @State private var turretHardpoints: Int = 0
    @State private var launcherHardpoints: Int = 0

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
        VStack(spacing: 12) {
            // 第一行：CPU和PG
            HStack(spacing: 8) {
                // CPU
                AttributeProgressView(
                    icon: "cpu",
                    current: cpuUsed,
                    total: attributes.attributesByName["cpuOutput"] ?? 0,
                    unit: "Tf"
                )
                .frame(maxWidth: .infinity)

                // PG
                AttributeProgressView(
                    icon: "pg",
                    current: pgUsed,
                    total: attributes.attributesByName["powerOutput"] ?? 0,
                    unit: "MW"
                )
                .frame(maxWidth: .infinity)
            }

            // 第二行：改装值、炮台数、发射器数
            HStack(spacing: 8) {
                // 改装值
                AttributeProgressView(
                    icon: "rigcost",
                    current: rigUsed,
                    total: attributes.attributesByName["upgradeCapacity"] ?? 0
                )
                .frame(maxWidth: .infinity)

                // 炮台数和发射器数
                HStack(spacing: 8) {
                    // 炮台数
                    AttributeValueView(
                        icon: "gunSlot",
                        current: turretUsed,
                        total: turretHardpoints
                    )
                    .frame(maxWidth: .infinity)

                    // 发射器数
                    AttributeValueView(
                        icon: "missSlot",
                        current: launcherUsed,
                        total: launcherHardpoints
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
        .onReceive(viewModel.$simulationOutput) { output in
            updateResourceUsage(output: output)
        }
    }

    /// 更新资源使用情况
    private func updateResourceUsage(output: SimulationOutput?) {
        // 计算已使用的CPU和电力
        var cpuTotal: Double = 0
        var pgTotal: Double = 0
        var rigTotal: Double = 0

        // 使用计算后的属性值，从simulationOutput中获取
        if let output {
            Logger.info("使用计算后的属性值计算资源使用情况")
            // 获取计算后的挂点数
            turretHardpoints = Int(output.ship.attributesByName["turretSlotsLeft"] ?? 0)
            launcherHardpoints = Int(output.ship.attributesByName["launcherSlotsLeft"] ?? 0)

            for module in output.modules {
                // 只计算在线状态（status >= 1）的装备的资源消耗
                if module.status >= 1 {
                    // 使用计算后的属性值
                    cpuTotal += module.attributesByName["cpu"] ?? 0
                    pgTotal += module.attributesByName["power"] ?? 0
                    rigTotal += module.attributesByName["upgradeCost"] ?? 0
                }
            }
        } else {
            // 如果没有计算结果，回退到使用原始值
            Logger.info("没有计算结果，回退到使用原始值计算资源使用情况")
            // 获取原始挂点数
            turretHardpoints = Int(
                viewModel.simulationInput.ship.baseAttributesByName["turretSlotsLeft"] ?? 0
            )
            launcherHardpoints = Int(
                viewModel.simulationInput.ship.baseAttributesByName["launcherSlotsLeft"] ?? 0
            )

            for module in viewModel.simulationInput.modules {
                // 只计算在线状态（status >= 1）的装备的资源消耗
                if module.status >= 1 {
                    cpuTotal += module.attributesByName["cpu"] ?? 0
                    pgTotal += module.attributesByName["power"] ?? 0
                    rigTotal += module.attributesByName["upgradeCost"] ?? 0
                }
            }
        }

        // 更新状态
        cpuUsed = cpuTotal
        pgUsed = pgTotal
        rigUsed = rigTotal
    }
}

/// 带进度条的属性视图
struct AttributeProgressView: View {
    let icon: String
    let current: Double
    let total: Double
    let unit: String

    init(icon: String, current: Double, total: Double, unit: String = "") {
        self.icon = icon
        self.current = current
        self.total = total
        self.unit = unit
    }

    private func formatLong(_ value: Double) -> String {
        return FormatUtil.formatForUI(value, maxFractionDigits: 2)
    }

    private var progress: Double {
        guard total > 0 else {
            if total <= 0 && current > 0 {
                return -1
            }
            return 0
        }
        return current / total
    }

    private var isOverLimit: Bool {
        progress > 1 || progress == -1
    }

    private var progressColor: Color {
        if isOverLimit {
            return Color(red: 176 / 255, green: 53 / 255, blue: 50 / 255) // 红色
        } else {
            return Color(red: 74 / 255, green: 128 / 255, blue: 192 / 255) // 浅蓝色
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            IconManager.shared.loadImage(for: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景进度条
                    Rectangle()
                        .fill(progressColor)
                        .overlay(Color.black.opacity(0.3))
                        .frame(height: 16)

                    // 前景进度条
                    Rectangle()
                        .fill(progressColor)
                        .saturation(1.2)
                        .brightness(0.1)
                        .frame(height: 16)
                        .frame(width: geometry.size.width * min(1.0, isOverLimit ? 1.0 : progress))

                    // 数值文本
                    Text(
                        "\(formatLong(current))/\(formatLong(total))\(unit.isEmpty ? "" : " \(unit)")"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 16)
        }
    }
}

/// 纯数值属性视图
struct AttributeValueView: View {
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
            Spacer()
        }
    }
}
