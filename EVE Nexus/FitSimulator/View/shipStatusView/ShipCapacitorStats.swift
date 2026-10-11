import SwiftUI

struct ShipCapacitorStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    var body: some View {
        if let ship = viewModel.simulationOutput?.ship {
            let capCapacity = ship.attributesByName["capacitorCapacity"] ?? 0

            // 获取电容抗性
            let energyWarfareResistance =
                (1 - (ship.attributesByName["energyWarfareResistance"] ?? 0)) * 100

            // 计算电容稳定性
            let stats = viewModel.capacitorStatistics
            let isCapStable = stats?.isStable ?? false
            let stableLevel = stats?.stableLevel ?? 0
            let lastsTime = stats?.lastsTime ?? 0
            let delta = stats?.delta ?? 0

            Section {
                HStack {
                    // 左侧：容量和稳定性
                    HStack {
                        IconManager.shared.loadImage(for: "capacitor")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading) {
                            HStack {
                                Text(
                                    NSLocalizedString("Fitting_cap_capacity", comment: "总容量") + ":"
                                )
                                Text(formatCapacitor(capCapacity, unit: "GJ"))
                            }
                            Divider()
                            HStack {
                                if isCapStable {
                                    Text(
                                        NSLocalizedString("Fitting_cap_stable", comment: "稳定在")
                                            + ":"
                                    )
                                    Text(FormatUtil.formatForUI(stableLevel * 100) + "%")
                                        .foregroundColor(.green)
                                } else {
                                    Text(NSLocalizedString("Fitting_cap_time", comment: "持续") + ":")
                                    Text((stats?.reachedLimit == true ? "≥ " : "") + formatTime(lastsTime))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 右侧：电容抗性和增减率
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(NSLocalizedString("Fitting_cap_delta", comment: "增减率") + ":")
                                Text(
                                    "\(delta > 0 ? "+" : "")\(formatCapacitor(delta, unit: "GJ/s"))"
                                )
                                .foregroundColor(delta >= 0 ? .green : .red)
                            }
                            Divider()
                            HStack {
                                Text(
                                    NSLocalizedString("Fitting_cap_resistance", comment: "电容抗性")
                                        + ":"
                                )
                                Text(FormatUtil.formatForUI(energyWarfareResistance) + "%")
                            }
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .lineLimit(1)
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text(NSLocalizedString("Fitting_stat_capacitor", comment: "电容"))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .font(.system(size: 18))
                    Spacer()
                }
            }
        }
    }

    /// 格式化电容值
    private func formatCapacitor(_ value: Double, unit: String) -> String {
        return FormatUtil.formatForUI(value, maxFractionDigits: 2) + " " + unit
    }

    /// 格式化时间
    private func formatTime(_ seconds: Double) -> String {
        if seconds == Double.infinity {
            return "∞"
        }

        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%dm %02ds", minutes, remainingSeconds)
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return String(format: "%dh %02dm", hours, minutes)
        }
    }
}
