import Foundation
import SwiftUI

/// 突变属性编辑面板（装配模拟共享）
///
/// 使用与突变计算器一致的行 UI（`MutationAttributeControlRow`）：
/// 拖动进度条时仅修改本地倍率，当前值由「物品原始属性 × 倍率」实时推导；
/// 只有点击「保存」才会回调 `onSave`，由调用方决定何时重算装配模拟。
struct MutationEditSheetView: View {
    let mutaplasmidName: String
    let mutaplasmidIconFileName: String?
    let attributes: [MutationAttribute]
    /// 物品原始属性表（用于属性换算与显示）
    let referenceAttributes: [Int: Double]
    /// 保存回调：attributeID → 倍率（仅包含有变化的属性）
    let onSave: ([Int: Double]) -> Void

    @Environment(\.dismiss) private var dismiss

    /// 本地草稿值：attributeID → 倍率，未设置时为 1.0（即原始值）
    @State private var multipliers: [Int: Double] = [:]

    init(
        mutaplasmidName: String,
        mutaplasmidIconFileName: String?,
        attributes: [MutationAttribute],
        referenceAttributes: [Int: Double],
        onSave: @escaping ([Int: Double]) -> Void
    ) {
        self.mutaplasmidName = mutaplasmidName
        self.mutaplasmidIconFileName = mutaplasmidIconFileName
        self.attributes = attributes
        self.referenceAttributes = referenceAttributes
        self.onSave = onSave

        var initial: [Int: Double] = [:]
        for attribute in attributes {
            initial[attribute.attributeID] = attribute.currentValue ?? 1.0
        }
        _multipliers = State(initialValue: initial)
    }

    /// 按属性ID排序后的属性列表
    private var sortedAttributes: [MutationAttribute] {
        attributes.sorted { $0.attributeID < $1.attributeID }
    }

    var body: some View {
        NavigationStack {
            List {
                mutaplasmidSection
                attributeSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Fitting_Mutation_Edit", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("Misc_Cancel", comment: ""))
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text(NSLocalizedString("Misc_Save", comment: ""))
                            .bold()
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.81)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 子视图

    /// 突变质体信息
    private var mutaplasmidSection: some View {
        Section {
            HStack(spacing: 12) {
                if let iconFileName = mutaplasmidIconFileName, !iconFileName.isEmpty {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                }

                Text(mutaplasmidName)
                    .font(.body)

                Spacer()
            }
        }
    }

    /// 可突变属性（拖动实时计算）
    private var attributeSection: some View {
        Section(header: Text(NSLocalizedString("Main_Database_Mutation_Attribute", comment: ""))) {
            if sortedAttributes.isEmpty {
                Text(NSLocalizedString("Misc_No_Data", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedAttributes) { attribute in
                    row(for: attribute)
                }
            }
        }
    }

    private func row(for attribute: MutationAttribute) -> some View {
        MutationAttributeControlRow(
            name: attribute.name,
            iconFileName: attribute.iconFileName,
            attributeID: attribute.attributeID,
            unitID: attribute.unitID,
            originalValue: attribute.originalValue ?? 1,
            minValue: attribute.minValue,
            maxValue: attribute.maxValue,
            highIsGood: attribute.highIsGood,
            multiplier: multiplierBinding(for: attribute),
            referenceAttributes: referenceAttributes,
            isInteractive: true
        )
    }

    // MARK: - 数据

    private func multiplierBinding(for attribute: MutationAttribute) -> Binding<Double> {
        Binding(
            get: { multipliers[attribute.attributeID] ?? 1.0 },
            set: { multipliers[attribute.attributeID] = $0 }
        )
    }

    /// 收集发生变化的倍率（未设置或 1.0 视为未突变）
    private func collectMultipliers() -> [Int: Double] {
        var result: [Int: Double] = [:]
        for attribute in attributes {
            let value = multipliers[attribute.attributeID] ?? 1.0
            if abs(value - 1.0) > 0.000_001 {
                result[attribute.attributeID] = value
            }
        }
        return result
    }

    private func save() {
        onSave(collectMultipliers())
        dismiss()
    }
}
