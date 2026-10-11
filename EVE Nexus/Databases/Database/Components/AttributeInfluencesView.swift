import SwiftUI

private func hasAttributeChange(from before: Double, to after: Double) -> Bool {
    before.isFinite && after.isFinite
        && abs(after - before) > 1e-9 * max(1, abs(before), abs(after))
}

private struct FittingAttributeContextKey: EnvironmentKey {
    static let defaultValue: FittingAttributeContext? = nil
}

extension EnvironmentValues {
    var fittingAttributeContext: FittingAttributeContext? {
        get { self[FittingAttributeContextKey.self] }
        set { self[FittingAttributeContextKey.self] = newValue }
    }
}

private struct AttributeInfluencesModifier: ViewModifier {
    let attributeIDs: [Int]
    @Environment(\.fittingAttributeContext) private var context

    private var changedIDs: [Int] {
        attributeIDs.filter { id in
            guard let context, let trace = context.traces[context.instanceID]?[id] else { return false }
            return hasAttributeChange(from: trace.baseValue, to: trace.finalValue)
                && trace.steps.contains { hasAttributeChange(from: $0.before, to: $0.after) }
        }
    }

    func body(content: Content) -> some View {
        if !changedIDs.isEmpty, let context {
            NavigationLink {
                AttributeInfluencesView(context: context, attributeIDs: attributeIDs)
                    .onAppear {
                        let names = attributeIDs.map { AttributeInfluenceSection.attributeName($0) }.joined(separator: "、")
                        Logger.info("查看影响因素：\(context.itemName)，属性：\(names)")
                    }
            } label: {
                content
                    .foregroundStyle(.primary)
            }
        } else {
            content
        }
    }
}

extension View {
    func attributeInfluences(_ attributeIDs: [Int]) -> some View {
        modifier(AttributeInfluencesModifier(attributeIDs: attributeIDs))
    }
}

/// Displays the exact ordered calculation steps; no second calculation or attribution by subtraction.
struct AttributeInfluencesView: View {
    let context: FittingAttributeContext
    let attributeIDs: [Int]

    var body: some View {
        List {
            ForEach(attributeIDs, id: \.self) { id in
                AttributeInfluenceSection(context: context, attributeID: id)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(attributeIDs.count == 1
            ? AttributeInfluenceSection.attributeName(attributeIDs[0])
            : NSLocalizedString("Fitting_Influences_Title", comment: "影响因素"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AttributeInfluenceSection: View {
    let context: FittingAttributeContext
    let attributeID: Int

    private var trace: AttributeTrace {
        context.traces[context.instanceID]?[attributeID] ?? AttributeTrace(
            baseValue: context.baseAttributes[attributeID] ?? 0, steps: [],
            finalValue: context.finalAttributes[attributeID] ?? context.baseAttributes[attributeID] ?? 0
        )
    }

    private var visibleSteps: [AttributeTraceStep] {
        trace.steps.filter {
            hasAttributeChange(from: $0.before, to: $0.after)
                && formatted($0.before) != formatted($0.after)
        }
    }

    private var highIsGood: Bool {
        AttributeDisplayConfig.isResistanceAttribute(attributeID)
            ? false : (SDEMemoryStore.dogmaAttribute(for: attributeID)?.highIsGood ?? true)
    }

    static func attributeName(_ id: Int) -> String {
        let attribute = SDEMemoryStore.dogmaAttribute(for: id)
        return attribute?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? attribute?.name ?? "\(id)"
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                summaryValue(title: NSLocalizedString("Fitting_Influences_Base", comment: "基础值"),
                             value: trace.baseValue, color: .secondary, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                summaryValue(title: NSLocalizedString("Fitting_Influences_Final", comment: "最终值"),
                             value: trace.finalValue, color: changeColor(from: trace.baseValue, to: trace.finalValue),
                             alignment: .trailing)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18))
            ForEach(Array(visibleSteps.enumerated()), id: \.offset) { _, step in
                stepRow(step)
                    .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
            }
            if visibleSteps.isEmpty {
                Text(NSLocalizedString("Fitting_Influences_Unchanged", comment: "无生效的影响因素"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 6) {
                if let attribute = SDEMemoryStore.dogmaAttribute(for: attributeID), attribute.iconID != 0 {
                    IconManager.shared.loadImage(for: attribute.iconFilename)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                }
                Text(Self.attributeName(attributeID))
            }
        }
    }

    private func summaryValue(title: String, value: Double, color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(formatted(value))
                .font(.body.weight(.medium))
                .foregroundStyle(color)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func stepRow(_ step: AttributeTraceStep) -> some View {
        HStack(spacing: 8) {
            sourceIcon(step)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(sourceName(step))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if step.modifier?.effectCategory == EffectCategory.overload.rawValue {
                        IconManager.shared.loadImage(for: "overheating")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .accessibilityLabel(Text(NSLocalizedString("Module_Status_Overload", comment: "超载")))
                    }
                }
                (Text(formatted(step.before)).foregroundColor(.secondary)
                    + Text(" → ").foregroundColor(.secondary)
                    + Text(formatted(step.after) + differenceText(step))
                    .foregroundColor(changeColor(from: step.before, to: step.after)))
                    .font(.caption)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func changeColor(from before: Double, to after: Double) -> Color {
        guard hasAttributeChange(from: before, to: after),
              SDEMemoryStore.dogmaAttribute(for: attributeID) != nil
        else { return .secondary }

        // Resistances display (1 - resonance) × 100; lower internal resonance is better.
        let improved = highIsGood ? after > before : after < before
        return improved ? .green : .red
    }

    private func number(_ value: Double) -> String {
        FormatUtil.formatForUI(value, maxFractionDigits: 2)
    }

    private func differenceText(_ step: AttributeTraceStep) -> String {
        let unitID = SDEMemoryStore.dogmaAttribute(for: attributeID)?.unitID
        let delta: Double
        let suffix: String
        switch unitID {
        case 109:
            delta = (step.after - step.before) * 100
            suffix = "%"
        case 3:
            delta = step.after - step.before
            suffix = "s"
        case 101:
            let milliseconds = step.after - step.before
            delta = abs(milliseconds) < 1000 ? milliseconds : milliseconds / 1000
            suffix = abs(milliseconds) < 1000 ? "ms" : "s"
        default:
            // Subtract displayed numeric values, including unit conversions and resistance inversion.
            // Text mappings (booleans, sizes, genders, etc.) have no numeric difference.
            guard case let .number(before, unit) = AttributeDisplayConfig.transformValue(
                attributeID, allAttributes: [attributeID: step.before], unitID: unitID, applyCalculations: false
            ),
                case let .number(after, _) = AttributeDisplayConfig.transformValue(
                    attributeID, allAttributes: [attributeID: step.after], unitID: unitID, applyCalculations: false
                )
            else { return "" }
            delta = after - before
            suffix = unit ?? ""
        }
        let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "")
        return " (\(sign)\(number(abs(delta)))\(suffix))"
    }

    private func formatted(_ value: Double) -> String {
        if AttributeDisplayConfig.isResistanceAttribute(attributeID) {
            return "\(number((1 - value) * 100))%"
        }
        let unit = SDEMemoryStore.dogmaAttribute(for: attributeID)?.unitID
        // These units otherwise return preformatted text with their own decimal precision.
        if unit == 109 {
            let percent = (value - 1) * 100
            return (percent > 0 ? "+" : "") + number(percent) + "%"
        }
        if unit == 3 {
            return number(value) + "s"
        }
        if unit == 101 {
            return abs(value) < 1000 ? number(value) + "ms" : number(value / 1000) + "s"
        }
        switch AttributeDisplayConfig.transformValue(attributeID, allAttributes: [attributeID: value], unitID: unit, applyCalculations: false) {
        case let .number(value, unit): return number(value) + (unit ?? "")
        case let .text(text): return text
        case .resistance: return number(value)
        }
    }

    private func sourceIcon(_ step: AttributeTraceStep) -> Image {
        if let id = step.modifier?.sourceInstanceId, let asset = context.sourceAssetIcons[id] {
            return Image(asset)
        }
        if step.operation == "Mutation", let icon = context.mutationIcon {
            return IconManager.shared.loadImage(for: icon)
        }
        if let id = step.modifier?.sourceInstanceId, let icon = context.sourceIcons[id] {
            return IconManager.shared.loadImage(for: icon)
        }
        if let typeID = step.modifier?.sourceTypeID,
           let icon = DatabaseManager.shared.getItemIconFileName(for: typeID)
        {
            return IconManager.shared.loadImage(for: icon)
        }
        if step.operation == "Mutation" {
            return Image(systemName: "wand.and.stars")
        }
        return Image(systemName: "function")
    }

    private func sourceName(_ step: AttributeTraceStep) -> String {
        switch step.operation {
        case "Mutation": return NSLocalizedString("Fitting_Influences_Mutation", comment: "突变")
        case "Spool": return NSLocalizedString("Fitting_Influences_Spool", comment: "完全预热")
        default:
            if let id = step.modifier?.sourceInstanceId, let label = context.sourceLabels[id] {
                return label
            }
            return step.modifier?.sourceName ?? NSLocalizedString("Fitting_Influences_View", comment: "影响因素")
        }
    }
}
