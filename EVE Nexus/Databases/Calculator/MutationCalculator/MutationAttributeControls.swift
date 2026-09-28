import Foundation
import SwiftUI

// MARK: - 突变属性滑块（共享组件，提取自突变计算器 UI）

/// 以“左差右好”为交互轴的突变进度条，避免根据 highIsGood 和原始值正负反转拖动方向。
///
/// - 交互模式（`isInteractive == true`）：可水平拖动调整倍率，步进 0.1%，并限制在 `[minValue, maxValue]`。
/// - 只读模式（`isInteractive == false`）：仅展示当前倍率对应的进度。
struct MutationAttributeSliderView: View {
    @Binding var multiplier: Double
    let minValue: Double
    let maxValue: Double
    let highIsGood: Bool
    /// 物品原始属性值：其符号决定“变好/变差”的拖动方向（原始值为负时方向反转）
    let originalValue: Double
    /// 是否可交互（只读模式仅显示进度）
    var isInteractive: Bool = true

    private let trackHeight: CGFloat = 6
    private let percentageStep = 0.1

    private var thumbSize: CGFloat {
        isInteractive ? 16 : 7
    }

    private enum FillDirection {
        case left
        case right
    }

    private struct BarState {
        let progress: Double
        let color: Color
        let direction: FillDirection
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let centerX = width / 2
            let centerY = geometry.size.height / 2
            let state = barState(for: multiplier)
            let thumbOffset = centerX * state.progress
            let thumbX = state.direction == .right
                ? centerX + thumbOffset
                : centerX - thumbOffset

            ZStack {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: width, height: trackHeight)
                    .position(x: centerX, y: centerY)

                if state.progress > 0 {
                    Capsule()
                        .fill(state.color)
                        .frame(width: max(abs(thumbX - centerX), 3), height: trackHeight)
                        .position(x: (centerX + thumbX) / 2, y: centerY)
                }

                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color(uiColor: .systemGray3), lineWidth: 1)
                    )
                    .position(x: centerX, y: centerY)

                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(
                                state.progress > 0 ? state.color : Color(uiColor: .systemGray3),
                                lineWidth: isInteractive ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isInteractive ? .black.opacity(0.12) : .clear,
                        radius: isInteractive ? 1 : 0,
                        y: isInteractive ? 1 : 0
                    )
                    .position(x: thumbX, y: centerY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateMultiplier(locationX: value.location.x, width: width)
                    }
            )
            .allowsHitTesting(isInteractive)
        }
        .frame(height: isInteractive ? 26 : 8)
    }

    // MARK: - 内部计算

    /// “变好”方向的端点倍率
    private var goodMutator: Double {
        let minScore = improvementScore(for: minValue)
        let maxScore = improvementScore(for: maxValue)
        guard abs(maxScore - minScore) > 0.000_001 else {
            return highIsGood ? maxValue : minValue
        }
        return maxScore > minScore ? maxValue : minValue
    }

    /// “变差”方向的端点倍率
    private var badMutator: Double {
        goodMutator == minValue ? maxValue : minValue
    }

    private func improvementScore(for value: Double) -> Double {
        let difference = originalValue * (value - 1)
        return highIsGood ? difference : -difference
    }

    private func barState(for value: Double) -> BarState {
        let score = improvementScore(for: value)
        guard abs(score) > 0.000_001, abs(value - 1) > 0.000_001 else {
            return BarState(progress: 0, color: .clear, direction: .right)
        }

        if score > 0 {
            return BarState(
                progress: progress(from: value, toward: goodMutator),
                color: .green,
                direction: .right
            )
        }
        return BarState(
            progress: progress(from: value, toward: badMutator),
            color: .red,
            direction: .left
        )
    }

    private func progress(from value: Double, toward endpoint: Double) -> Double {
        let range = abs(endpoint - 1)
        guard range > 0.000_001 else { return 0 }
        return min(max(abs(value - 1) / range, 0), 1)
    }

    private func updateMultiplier(locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }

        let centerX = width / 2
        let progress = min(max(abs(locationX - centerX) / centerX, 0), 1)
        let endpoint = locationX >= centerX ? goodMutator : badMutator
        let targetMultiplier = 1 + (endpoint - 1) * progress

        let percentage = (targetMultiplier - 1) * 100
        let steppedPercentage = (percentage / percentageStep).rounded() * percentageStep
        multiplier = min(max(1 + steppedPercentage / 100, minValue), maxValue)
    }
}

// MARK: - 突变属性行（共享组件，提取自突变计算器 UI）

/// 统一的突变属性编辑行：图标 + 名称 + 「原始值 → 当前值」 + 可拖动进度条 + 百分比。
///
/// 拖动时仅修改 `multiplier`，当前值由 `originalValue * multiplier` 实时推导；
/// 是否触发装配模拟重算由调用方决定（例如只在点击保存后）。
struct MutationAttributeControlRow: View {
    let name: String
    let iconFileName: String?
    let attributeID: Int
    let unitID: Int?
    let originalValue: Double
    let minValue: Double
    let maxValue: Double
    let highIsGood: Bool
    @Binding var multiplier: Double
    /// 属性换算所需的完整属性表（行内会以自身数值覆盖对应属性）
    var referenceAttributes: [Int: Double] = [:]
    /// 当前值换算所需的属性表；为 nil 时复用 `referenceAttributes`
    var currentReferenceAttributes: [Int: Double]? = nil
    /// 是否可拖动
    var isInteractive: Bool = true
    /// 点击百分比按钮时的回调；为 nil 时仅显示只读百分比
    var onEdit: (() -> Void)? = nil

    /// 当前属性值（基于原始值实时推导）
    private var currentValue: Double {
        originalValue * multiplier
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            iconView

            VStack(alignment: .leading, spacing: 8) {
                titleRow
                sliderRow
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 子视图

    @ViewBuilder
    private var iconView: some View {
        if let iconFileName, !iconFileName.isEmpty {
            IconManager.shared.loadImage(for: iconFileName)
                .resizable()
                .frame(width: 32, height: 32)
        } else {
            Image("not_found")
                .resizable()
                .frame(width: 32, height: 32)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(formattedValue(originalValue, in: referenceAttributes))
                    .foregroundColor(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formattedValue(currentValue, in: currentReferenceAttributes ?? referenceAttributes))
                    .foregroundColor(valueColor)
            }
            .font(.body)
            .layoutPriority(1)
        }
    }

    private var sliderRow: some View {
        HStack(spacing: 10) {
            MutationAttributeSliderView(
                multiplier: $multiplier,
                minValue: minValue,
                maxValue: maxValue,
                highIsGood: highIsGood,
                originalValue: originalValue,
                isInteractive: isInteractive
            )

            percentageLabel
        }
    }

    @ViewBuilder
    private var percentageLabel: some View {
        if let onEdit {
            Button(action: onEdit) {
                HStack(spacing: 3) {
                    Text(formattedPercentage)
                    Image(systemName: "pencil")
                        .font(.caption2)
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(valueColor)
                .frame(width: 68, alignment: .trailing)
            }
            .buttonStyle(.plain)
        } else {
            Text(formattedPercentage)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(valueColor)
                .frame(width: 68, alignment: .trailing)
        }
    }

    // MARK: - 格式化

    private var formattedPercentage: String {
        MutationValueFormatter.signedPercentage((multiplier - 1) * 100)
    }

    private var valueColor: Color {
        MutationValueFormatter.valueColor(
            originalValue: originalValue,
            multiplier: multiplier,
            highIsGood: highIsGood
        )
    }

    private func formattedValue(_ value: Double, in attributes: [Int: Double]) -> String {
        var values = attributes
        values[attributeID] = value

        let result = AttributeDisplayConfig.transformValue(
            attributeID,
            allAttributes: values,
            unitID: unitID
        )

        switch result {
        case let .number(transformedValue, unit):
            return unit.map { "\(FormatUtil.format(transformedValue))\($0)" }
                ?? FormatUtil.format(transformedValue)
        case let .text(text):
            return text
        case .resistance:
            return FormatUtil.format(value)
        }
    }
}

// MARK: - 突变数值公共格式化

/// 突变数值的公共格式化与配色逻辑，供共享组件与各调用方复用。
enum MutationValueFormatter {
    /// 带符号的百分比文本，例如 `+12.5%` / `-3%`
    static func signedPercentage(_ percentage: Double) -> String {
        let normalized = abs(percentage) < 0.000_001 ? 0 : percentage
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        let formatted = formatter.string(from: NSNumber(value: normalized))
            ?? String(format: "%.2f", normalized)
        return normalized > 0 ? "+\(formatted)%" : "\(formatted)%"
    }

    /// 突变数值配色：变好为绿色，变差为红色，无变化为次级色
    static func valueColor(originalValue: Double, multiplier: Double, highIsGood: Bool) -> Color {
        let difference = originalValue * multiplier - originalValue
        guard abs(difference) > 0.000_001 else { return .secondary }
        let improved = highIsGood ? difference > 0 : difference < 0
        return improved ? .green : .red
    }
}
