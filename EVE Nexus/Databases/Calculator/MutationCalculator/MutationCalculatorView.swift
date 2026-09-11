import SwiftUI

// MARK: - 数据模型

/// 突变质体可影响的属性范围
private struct MutatorAttributeRange {
    let id: Int
    let name: String
    let iconFileName: String?
    let unitID: Int?
    let minMutator: Double
    let maxMutator: Double
    let highIsGood: Bool
}

/// 可复用的突变属性
struct MutationDisplayAttribute: Identifiable {
    let id: Int
    let name: String
    let iconFileName: String?
    let unitID: Int?
    let originalValue: Double
    let minMutator: Double
    let maxMutator: Double
    let highIsGood: Bool
    var multiplier: Double

    var currentValue: Double {
        originalValue * multiplier
    }

    var minPercent: Double {
        (minMutator - 1) * 100
    }

    var maxPercent: Double {
        (maxMutator - 1) * 100
    }
}

private struct MutaplasmidOption: Identifiable {
    let id: Int
    let name: String
    let iconFileName: String
}

// MARK: - 突变计算器

struct MutationCalculatorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    private let preselectedItemID: Int?

    @State private var selectedItem: DatabaseListItem?
    @State private var selectedMutaplasmid: MutaplasmidOption?
    @State private var mutationAttributes: [MutationDisplayAttribute] = []
    @State private var attributeValues: [Int: Double] = [:]

    @State private var isShowingItemSelector = false
    @State private var isShowingMutaplasmidSelector = false
    @State private var didAutoPresentMutaplasmidSelector = false

    @State private var editingAttributeID: Int?
    @State private var editingAttributeValue = ""
    @State private var editingValidationError: String?
    @State private var isEditingValueValid = false
    @State private var isShowingValueEditor = false

    init(databaseManager: DatabaseManager, preselectedItemID: Int? = nil) {
        self.databaseManager = databaseManager
        self.preselectedItemID = preselectedItemID
    }

    var body: some View {
        List {
            Section(header: sectionHeader(NSLocalizedString("Fitting_Setting_Module", comment: ""))) {
                Button {
                    isShowingItemSelector = true
                } label: {
                    selectionRow(
                        title: NSLocalizedString("Main_Database_Mutation_Source", comment: ""),
                        selectedName: selectedItem?.name,
                        iconFileName: selectedItem?.iconFileName,
                        placeholder: NSLocalizedString("Select_Item", comment: "")
                    )
                }
                .buttonStyle(.plain)

                if selectedItem != nil {
                    Button {
                        isShowingMutaplasmidSelector = true
                    } label: {
                        selectionRow(
                            title: NSLocalizedString("Fitting_Selected_Mutation", comment: ""),
                            selectedName: selectedMutaplasmid?.name,
                            iconFileName: selectedMutaplasmid?.iconFileName,
                            placeholder: NSLocalizedString("Misc_Null", comment: "")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(itemSectionRowInsets)

            if selectedMutaplasmid != nil {
                Section(
                    header: sectionHeader(
                        NSLocalizedString("Main_Database_Mutation_Attribute", comment: "")
                    ),
                    footer: rollFooter
                ) {
                    if mutationAttributes.isEmpty {
                        Text(NSLocalizedString("Misc_No_Data", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach($mutationAttributes) { $attribute in
                            MutationAttributeDisplayRowView(
                                attribute: $attribute,
                                originalAttributes: attributeValues,
                                currentAttributes: attributeValues
                            ) {
                                startEditing(attribute)
                            }
                        }
                    }
                }
                .listRowInsets(itemSectionRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Calculator_Mutation", comment: ""))
        .onAppear(perform: loadPreselectedItemIfNeeded)
        .sheet(isPresented: $isShowingItemSelector) {
            MutatableItemSelectorView(databaseManager: databaseManager) { item in
                if selectedItem?.id != item.id {
                    selectedItem = item
                    selectedMutaplasmid = nil
                    mutationAttributes = []
                    attributeValues = [:]
                }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingMutaplasmidSelector) {
            if let selectedItem {
                NavigationStack {
                    MutaplasmidSelectionView(
                        databaseManager: databaseManager,
                        itemTypeID: selectedItem.id,
                        onSelectMutaplasmid: selectMutaplasmid
                    )
                }
                .presentationDragIndicator(.visible)
            }
        }
        .alert(
            NSLocalizedString("Fitting_Mutation_Value_Input", comment: ""),
            isPresented: $isShowingValueEditor
        ) {
            TextField(
                NSLocalizedString("Fitting_Mutation_Value_Placeholder", comment: ""),
                text: Binding(
                    get: { editingAttributeValue },
                    set: { newValue in
                        editingAttributeValue = newValue
                        validateEditingValue(newValue)
                    }
                )
            )
            .keyboardType(.numbersAndPunctuation)

            Button(NSLocalizedString("Misc_Done", comment: "")) {
                confirmEditingValue()
            }
            .disabled(!isEditingValueValid)

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                cancelEditingValue()
            }
        } message: {
            if let attribute = editingAttribute {
                Text(editingMessage(for: attribute))
            }
        }
    }

    private var editingAttribute: MutationDisplayAttribute? {
        guard let editingAttributeID else { return nil }
        return mutationAttributes.first { $0.id == editingAttributeID }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
    }

    /// 属性 section footer：右对齐的随机 Roll 按钮（无属性数据时隐藏）
    @ViewBuilder
    private var rollFooter: some View {
        if !mutationAttributes.isEmpty {
            Button {
                rollRandomMutations()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "dice.fill")
                    Text(NSLocalizedString("Misc_Random", comment: ""))
                }
                .font(.footnote)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// 在每个属性的 [minMutator, maxMutator] 范围内随机一组 multiplier，
    /// 对齐 0.1% 步进（与进度条拖动一致）
    private func rollRandomMutations() {
        for index in mutationAttributes.indices {
            let range = mutationAttributes[index]
            let rolled = Double.random(in: range.minMutator ... range.maxMutator)
            mutationAttributes[index].multiplier = (rolled * 1000).rounded() / 1000
        }
    }

    private func selectionRow(
        title: String,
        selectedName: String?,
        iconFileName: String?,
        placeholder: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundColor(.primary)

            Spacer(minLength: 8)

            if let selectedName {
                if let iconFileName, !iconFileName.isEmpty {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .cornerRadius(4)
                }
                Text(selectedName)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(placeholder)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 选择

    private func loadPreselectedItemIfNeeded() {
        guard selectedItem == nil,
              let preselectedItemID,
              !databaseManager.getRequiredMutaplasmids(for: preselectedItemID).isEmpty,
              let item = DatabaseListItem(
                  typeID: preselectedItemID,
                  databaseManager: databaseManager
              )
        else { return }

        selectedItem = item

        guard !didAutoPresentMutaplasmidSelector else { return }
        didAutoPresentMutaplasmidSelector = true
        isShowingMutaplasmidSelector = true
    }

    private func selectMutaplasmid(_ mutaplasmidID: Int) {
        guard let selectedItem,
              let mutaplasmid = databaseManager.getRequiredMutaplasmids(for: selectedItem.id)
              .first(where: { $0.typeID == mutaplasmidID })
        else { return }

        selectedMutaplasmid = MutaplasmidOption(
            id: mutaplasmid.typeID,
            name: mutaplasmid.name,
            iconFileName: mutaplasmid.iconFileName
        )
        mutationAttributes = loadMutationAttributes(
            sourceTypeID: selectedItem.id,
            mutaplasmidID: mutaplasmidID
        )
    }

    // MARK: - 数据加载

    private func loadMutationAttributes(
        sourceTypeID: Int,
        mutaplasmidID: Int
    ) -> [MutationDisplayAttribute] {
        AttributeDisplayConfig.initializeUnits(with: databaseManager.loadAttributeUnits())

        let ranges = loadMutatorAttributeRanges(mutaplasmidID: mutaplasmidID)
        let originalValues = loadOriginalAttributeValues(sourceTypeID: sourceTypeID)
        attributeValues = originalValues

        return ranges.compactMap { range in
            guard let originalValue = originalValues[range.id] else { return nil }
            return MutationDisplayAttribute(
                id: range.id,
                name: range.name,
                iconFileName: range.iconFileName,
                unitID: range.unitID,
                originalValue: originalValue,
                minMutator: range.minMutator,
                maxMutator: range.maxMutator,
                highIsGood: range.highIsGood,
                multiplier: min(max(1.0, range.minMutator), range.maxMutator)
            )
        }
    }

    private func loadMutatorAttributeRanges(mutaplasmidID: Int) -> [MutatorAttributeRange] {
        SDEMemoryStore.dynamicItemAttributes(forTypeID: mutaplasmidID).map { info in
            MutatorAttributeRange(
                id: info.attributeID,
                name: info.name,
                iconFileName: info.iconFileName,
                unitID: info.unitID,
                minMutator: info.minValue,
                maxMutator: info.maxValue,
                highIsGood: info.highIsGood
            )
        }
    }

    private func loadOriginalAttributeValues(sourceTypeID: Int) -> [Int: Double] {
        let query = """
            SELECT attribute_id, value
            FROM typeAttributes
            WHERE type_id = ?
        """

        guard case let .success(rows) = databaseManager.executeQuery(
            query, parameters: [sourceTypeID]
        ) else { return [:] }

        return rows.reduce(into: [:]) { result, row in
            if let attributeID = row["attribute_id"] as? Int,
               let value = row["value"] as? Double
            {
                result[attributeID] = value
            }
        }
    }

    // MARK: - 手动编辑

    private func startEditing(_ attribute: MutationDisplayAttribute) {
        editingAttributeID = attribute.id
        editingAttributeValue = formatPercentageForInput((attribute.multiplier - 1) * 100)
        editingValidationError = nil
        isEditingValueValid = true
        isShowingValueEditor = true
    }

    private func validateEditingValue(_ value: String) {
        guard let attribute = editingAttribute else {
            editingValidationError = nil
            isEditingValueValid = false
            return
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespaces)
        guard !trimmedValue.isEmpty else {
            editingValidationError = nil
            isEditingValueValid = false
            return
        }

        let pattern = #"^[+-]?(\d+\.?\d*|\.\d+)$"#
        let range = NSRange(trimmedValue.startIndex..., in: trimmedValue)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.firstMatch(in: trimmedValue, range: range) != nil
        else {
            editingValidationError = NSLocalizedString(
                "Fitting_Mutation_Value_Invalid_Format", comment: ""
            )
            isEditingValueValid = false
            return
        }

        guard let percentage = Double(trimmedValue) else {
            editingValidationError = NSLocalizedString(
                "Fitting_Mutation_Value_Invalid_Number", comment: ""
            )
            isEditingValueValid = false
            return
        }

        let multiplier = 1 + percentage / 100
        let epsilon = 0.000_001
        guard multiplier + epsilon >= attribute.minMutator,
              multiplier - epsilon <= attribute.maxMutator
        else {
            editingValidationError = String(
                format: NSLocalizedString("Fitting_Mutation_Value_Out_Of_Range", comment: ""),
                formatSignedPercentage(attribute.minPercent),
                formatSignedPercentage(attribute.maxPercent)
            )
            isEditingValueValid = false
            return
        }

        editingValidationError = nil
        isEditingValueValid = true
    }

    private func confirmEditingValue() {
        guard isEditingValueValid,
              let editingAttributeID,
              let index = mutationAttributes.firstIndex(where: { $0.id == editingAttributeID }),
              let percentage = Double(editingAttributeValue.trimmingCharacters(in: .whitespaces))
        else { return }

        let multiplier = 1 + percentage / 100
        let attribute = mutationAttributes[index]
        mutationAttributes[index].multiplier = min(
            max(multiplier, attribute.minMutator), attribute.maxMutator
        )
        cancelEditingValue()
    }

    private func cancelEditingValue() {
        editingAttributeID = nil
        editingAttributeValue = ""
        editingValidationError = nil
        isEditingValueValid = false
        isShowingValueEditor = false
    }

    private func editingMessage(for attribute: MutationDisplayAttribute) -> String {
        let rangeMessage = String(
            format: NSLocalizedString("Fitting_Mutation_Value_Range", comment: ""),
            formatSignedPercentage(attribute.minPercent),
            formatSignedPercentage(attribute.maxPercent)
        )
        if let editingValidationError {
            return "\(rangeMessage)\n\(editingValidationError)"
        }
        return rangeMessage
    }

    private func formatSignedPercentage(_ percentage: Double) -> String {
        let normalizedPercentage = abs(percentage) < 0.000_001 ? 0 : percentage
        let formatted = formatDecimal(normalizedPercentage)
        return normalizedPercentage > 0 ? "+\(formatted)%" : "\(formatted)%"
    }

    private func formatPercentageForInput(_ percentage: Double) -> String {
        formatDecimal(abs(percentage) < 0.000_001 ? 0 : percentage)
    }

    private func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - 可复用突变属性行

struct MutationAttributeDisplayRowView: View {
    @Binding var attribute: MutationDisplayAttribute
    let originalAttributes: [Int: Double]
    let currentAttributes: [Int: Double]
    let onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let iconFileName = attribute.iconFileName, !iconFileName.isEmpty {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image("not_found")
                    .resizable()
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(attribute.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Text(formatValueWithUnit(attribute.originalValue, attributes: originalAttributes))
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatValueWithUnit(attribute.currentValue, attributes: currentAttributes))
                            .foregroundColor(valueColor)
                    }
                    .font(.body)
                    .layoutPriority(1)
                }

                HStack(spacing: 10) {
                    InteractiveMutationProgressBar(
                        multiplier: $attribute.multiplier,
                        minValue: attribute.minMutator,
                        maxValue: attribute.maxMutator,
                        highIsGood: attribute.highIsGood,
                        originalValue: attribute.originalValue,
                        isInteractive: onEdit != nil
                    )

                    if let onEdit {
                        Button(action: onEdit) {
                            HStack(spacing: 3) {
                                Text(formatSignedPercentage((attribute.multiplier - 1) * 100))
                                Image(systemName: "pencil")
                                    .font(.caption2)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(valueColor)
                            .frame(width: 68, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(formatSignedPercentage((attribute.multiplier - 1) * 100))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(valueColor)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var valueColor: Color {
        color(for: attribute.multiplier)
    }

    private func color(for multiplier: Double) -> Color {
        let mutatedValue = attribute.originalValue * multiplier
        let difference = mutatedValue - attribute.originalValue
        guard abs(difference) > 0.000_001 else { return .secondary }
        let improved = attribute.highIsGood ? difference > 0 : difference < 0
        return improved ? .green : .red
    }

    private func formatSignedPercentage(_ percentage: Double) -> String {
        let normalizedPercentage = abs(percentage) < 0.000_001 ? 0 : percentage
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        let formatted = formatter.string(from: NSNumber(value: normalizedPercentage))
            ?? String(format: "%.2f", normalizedPercentage)
        return normalizedPercentage > 0 ? "+\(formatted)%" : "\(formatted)%"
    }

    private func formatValueWithUnit(_ value: Double, attributes: [Int: Double]) -> String {
        var values = attributes
        values[attribute.id] = value

        let result = AttributeDisplayConfig.transformValue(
            attribute.id,
            allAttributes: values,
            unitID: attribute.unitID
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

// MARK: - 可拖动突变进度条

/// 以“左差右好”为交互轴的突变进度条，避免根据 highIsGood 和原始值正负反转拖动方向。
private struct InteractiveMutationProgressBar: View {
    @Binding var multiplier: Double
    let minValue: Double
    let maxValue: Double
    let highIsGood: Bool
    let originalValue: Double
    let isInteractive: Bool

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

    private var goodMutator: Double {
        let minScore = improvementScore(for: minValue)
        let maxScore = improvementScore(for: maxValue)
        guard abs(maxScore - minScore) > 0.000_001 else {
            return highIsGood ? maxValue : minValue
        }
        return maxScore > minScore ? maxValue : minValue
    }

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

// MARK: - 可突变物品选择器

private struct MutatableItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let onItemSelected: (DatabaseListItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var allowedTypeIDs: Set<Int>
    @State private var marketGroupTree: [MarketGroupNode]

    init(
        databaseManager: DatabaseManager,
        onItemSelected: @escaping (DatabaseListItem) -> Void
    ) {
        self.databaseManager = databaseManager
        self.onItemSelected = onItemSelected

        let typeIDs = Self.loadAllowedTypeIDs(databaseManager: databaseManager)
        _allowedTypeIDs = State(initialValue: typeIDs)
        let builder = MarketItemGroupTreeBuilder(
            databaseManager: databaseManager,
            allowedTypeIDs: typeIDs,
            parentGroupId: nil
        )
        _marketGroupTree = State(initialValue: builder.buildGroupTree())
    }

    var body: some View {
        if allowedTypeIDs.isEmpty {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("Misc_No_Data", comment: ""),
                    systemImage: "exclamationmark.triangle"
                )
            }
        } else {
            MarketItemTreeSelectorView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Select_Item", comment: ""),
                marketGroupTree: marketGroupTree,
                allowTypeIDs: allowedTypeIDs,
                existingItems: [],
                onItemSelected: { item in
                    onItemSelected(item)
                    dismiss()
                },
                onItemDeselected: { _ in },
                onDismiss: { _, _ in
                    dismiss()
                },
                lastVisitedGroupID: nil,
                initialSearchText: nil
            )
        }
    }

    private static func loadAllowedTypeIDs(databaseManager: DatabaseManager) -> Set<Int> {
        let query = """
            SELECT DISTINCT m.applicable_type AS type_id
            FROM dynamic_item_mappings m
            JOIN types t ON m.applicable_type = t.type_id
            WHERE t.published = 1 AND t.marketGroupID IS NOT NULL
        """

        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            return []
        }
        return Set(rows.compactMap { $0["type_id"] as? Int })
    }
}
