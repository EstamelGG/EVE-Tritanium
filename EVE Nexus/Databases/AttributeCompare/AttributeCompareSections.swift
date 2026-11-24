import SwiftUI

private enum AttributeCompareStyle {
    static let itemColumnWidth: CGFloat = 124
    static let attributeColumnWidth: CGFloat = 104
    static let columnSpacing: CGFloat = 8
    static let itemIconSize: CGFloat = 28
    static let attributeIconSize: CGFloat = 18
}

private enum AttributeCompareLayout: String, CaseIterable, Identifiable {
    case horizontal
    case vertical
    case tiled

    var id: String {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .horizontal: return "Main_Attribute_Compare_Layout_Horizontal"
        case .vertical: return "Main_Attribute_Compare_Layout_Vertical"
        case .tiled: return "Main_Attribute_Compare_Layout_Tiled"
        }
    }
}

struct AttributeCompareLayoutPicker: View {
    @AppStorage("attributeCompareLayout") private var layoutRawValue =
        AttributeCompareLayout.horizontal.rawValue

    private var layout: Binding<AttributeCompareLayout> {
        Binding(
            get: { AttributeCompareLayout(rawValue: layoutRawValue) ?? .horizontal },
            set: { layoutRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Picker(
            NSLocalizedString("Main_Attribute_Compare_Layout", comment: ""),
            selection: layout
        ) {
            ForEach(AttributeCompareLayout.allCases) { option in
                Text(NSLocalizedString(option.titleKey, comment: ""))
                    .tag(option)
            }
        }
        .pickerStyle(.menu)
    }
}

private struct AttributeCompareAttributeHeader: View {
    let name: String
    let unit: String?
    let iconFileName: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 5) {
            if let iconFileName {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: AttributeCompareStyle.attributeIconSize,
                        height: AttributeCompareStyle.attributeIconSize
                    )
                    .foregroundStyle(.secondary)
            }

            Text(unit.map { "\(name) (\($0))" } ?? name)
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 6)
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct AttributeCompareItemCell: View {
    let item: DatabaseListItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 7) {
            Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                .resizable()
                .scaledToFit()
                .frame(
                    width: AttributeCompareStyle.itemIconSize,
                    height: AttributeCompareStyle.itemIconSize
                )
                .cornerRadius(4)

            Text(item.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.8)
        }
        .frame(
            width: width,
            height: height,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }
}

private struct AttributeCompareItemHeader: View {
    let item: DatabaseListItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                .resizable()
                .scaledToFit()
                .frame(
                    width: AttributeCompareStyle.itemIconSize,
                    height: AttributeCompareStyle.itemIconSize
                )
                .cornerRadius(4)

            Text(item.name)
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 6)
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct AttributeCompareAttributeCell: View {
    let name: String
    let unit: String?
    let iconFileName: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let iconFileName {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: AttributeCompareStyle.attributeIconSize,
                        height: AttributeCompareStyle.attributeIconSize
                    )
                    .foregroundStyle(.secondary)
            }

            Text(unit.map { "\(name) (\($0))" } ?? name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, height: height, alignment: .leading)
    }
}

private struct AttributeCompareValueCell: View {
    let itemName: String
    let attributeName: String
    let value: String
    let unit: String?
    let color: Color
    let width: CGFloat
    let height: CGFloat

    private var hasDifferenceTint: Bool {
        color != .secondary
    }

    var body: some View {
        Text(value)
            .font(.subheadline)
            .fontWeight(hasDifferenceTint ? .semibold : .regular)
            .foregroundStyle(color)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(
                width: width,
                height: height,
                alignment: .center
            )
            .background {
                if hasDifferenceTint {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.12))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(attributeName)\(unit.map { " (\($0))" } ?? ""), \(itemName): \(value)"
            )
    }
}

private struct AttributeCompareFormattedValue {
    let text: String
    let unit: String?
}

private enum AttributeCompareFormatting {
    static func displayUnit(
        attributeID: String,
        values: [String: AttributeCompareUtil.AttributeValueInfo]
    ) -> String? {
        guard let valueInfo = values.values.first else {
            return nil
        }
        return format(valueInfo, attributeID: attributeID).unit
    }

    static func formattedValue(
        for item: DatabaseListItem,
        attributeID: String,
        values: [String: AttributeCompareUtil.AttributeValueInfo]
    ) -> AttributeCompareFormattedValue {
        guard let valueInfo = values[String(item.id)] else {
            return AttributeCompareFormattedValue(text: "N/A", unit: nil)
        }
        return format(valueInfo, attributeID: attributeID)
    }

    static func format(
        _ valueInfo: AttributeCompareUtil.AttributeValueInfo,
        attributeID: String
    ) -> AttributeCompareFormattedValue {
        guard let attributeIDInt = Int(attributeID) else {
            return AttributeCompareFormattedValue(
                text: FormatUtil.format(valueInfo.value),
                unit: nil
            )
        }

        let result = AttributeDisplayConfig.transformValue(
            attributeIDInt,
            allAttributes: [attributeIDInt: valueInfo.value],
            unitID: valueInfo.unitID,
            appliesUnitFormatRules: false
        )

        switch result {
        case let .number(value, unit):
            return AttributeCompareFormattedValue(
                text: FormatUtil.format(value),
                unit: normalizedUnit(unit)
            )
        case let .text(text):
            if text.hasSuffix("%") {
                return AttributeCompareFormattedValue(
                    text: String(text.dropLast()),
                    unit: "%"
                )
            }
            return AttributeCompareFormattedValue(text: text, unit: nil)
        case let .resistance(resistances):
            return AttributeCompareFormattedValue(
                text: resistances.map { FormatUtil.format($0) }.joined(separator: ", "),
                unit: "%"
            )
        }
    }

    static func valueColor(
        for item: DatabaseListItem,
        values: [String: AttributeCompareUtil.AttributeValueInfo],
        highIsGood: Bool
    ) -> Color {
        guard let currentValue = values[String(item.id)]?.value else {
            return .secondary
        }

        let existingValues = values.values.map(\.value)
        guard existingValues.count > 1 else {
            return .secondary
        }

        let bestValue = highIsGood
            ? (existingValues.max() ?? currentValue)
            : (existingValues.min() ?? currentValue)
        let worstValue = highIsGood
            ? (existingValues.min() ?? currentValue)
            : (existingValues.max() ?? currentValue)

        guard bestValue != worstValue else {
            return .secondary
        }
        if currentValue == bestValue {
            return .green
        }
        if currentValue == worstValue {
            return .orange
        }
        return .secondary
    }

    private static func normalizedUnit(_ unit: String?) -> String? {
        guard let unit else {
            return nil
        }
        let trimmed = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 按横向或纵向布局展示完整对比矩阵。
private struct AttributeCompareMatrix: View {
    let result: AttributeCompareUtil.CompareResult
    let items: [DatabaseListItem]
    let visibleAttributeIDs: [String]
    let layout: AttributeCompareLayout

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var itemHeaderHeight = 62
    @ScaledMetric(relativeTo: .caption) private var rowHeight = 40
    @ScaledMetric(relativeTo: .caption) private var attributeColumnWidth =
        AttributeCompareStyle.attributeColumnWidth
    @ScaledMetric(relativeTo: .caption) private var itemColumnWidth =
        AttributeCompareStyle.itemColumnWidth

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityRows
        } else {
            comparisonTable
        }
    }

    @ViewBuilder
    private var comparisonTable: some View {
        switch layout {
        case .horizontal:
            horizontalTable
        case .vertical:
            verticalTable
        case .tiled:
            EmptyView()
        }
    }

    private var horizontalTable: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                Color.clear
                    .frame(
                        width: itemColumnWidth,
                        height: itemHeaderHeight
                    )

                ForEach(items) { item in
                    AttributeCompareItemCell(
                        item: item,
                        width: itemColumnWidth,
                        height: rowHeight
                    )
                }
            }
            .padding(.leading, 12)

            Divider()
                .padding(.vertical, 6)

            ScrollView(.horizontal) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: AttributeCompareStyle.columnSpacing,
                    verticalSpacing: 4
                ) {
                    GridRow {
                        ForEach(visibleAttributeIDs, id: \.self) { attributeID in
                            if let attributeName = result.publishedAttributeInfo[attributeID] {
                                AttributeCompareAttributeHeader(
                                    name: attributeName,
                                    unit: AttributeCompareFormatting.displayUnit(
                                        attributeID: attributeID,
                                        values: result.compareResult[attributeID] ?? [:]
                                    ),
                                    iconFileName: result.attributeIcons[attributeID],
                                    width: attributeColumnWidth,
                                    height: itemHeaderHeight
                                )
                            }
                        }
                    }

                    ForEach(items) { item in
                        GridRow {
                            ForEach(visibleAttributeIDs, id: \.self) { attributeID in
                                if let attributeValues = result.compareResult[attributeID],
                                   let attributeName = result.publishedAttributeInfo[attributeID]
                                {
                                    let presentation = AttributeCompareFormatting.formattedValue(
                                        for: item,
                                        attributeID: attributeID,
                                        values: attributeValues
                                    )
                                    AttributeCompareValueCell(
                                        itemName: item.name,
                                        attributeName: attributeName,
                                        value: presentation.text,
                                        unit: presentation.unit,
                                        color: AttributeCompareFormatting.valueColor(
                                            for: item,
                                            values: attributeValues,
                                            highIsGood: result.attributeHighIsGood[attributeID] ?? true
                                        ),
                                        width: attributeColumnWidth,
                                        height: rowHeight
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 6)
    }

    private var verticalTable: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                Color.clear
                    .frame(
                        width: attributeColumnWidth,
                        height: itemHeaderHeight
                    )

                ForEach(visibleAttributeIDs, id: \.self) { attributeID in
                    if let attributeValues = result.compareResult[attributeID],
                       let attributeName = result.publishedAttributeInfo[attributeID]
                    {
                        AttributeCompareAttributeCell(
                            name: attributeName,
                            unit: AttributeCompareFormatting.displayUnit(
                                attributeID: attributeID,
                                values: attributeValues
                            ),
                            iconFileName: result.attributeIcons[attributeID],
                            width: attributeColumnWidth,
                            height: rowHeight
                        )
                    }
                }
            }
            .padding(.leading, 12)

            Divider()
                .padding(.vertical, 6)

            ScrollView(.horizontal) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: AttributeCompareStyle.columnSpacing,
                    verticalSpacing: 4
                ) {
                    GridRow {
                        ForEach(items) { item in
                            AttributeCompareItemHeader(
                                item: item,
                                width: itemColumnWidth,
                                height: itemHeaderHeight
                            )
                        }
                    }

                    ForEach(visibleAttributeIDs, id: \.self) { attributeID in
                        if let attributeValues = result.compareResult[attributeID],
                           let attributeName = result.publishedAttributeInfo[attributeID]
                        {
                            GridRow {
                                ForEach(items) { item in
                                    let presentation = AttributeCompareFormatting.formattedValue(
                                        for: item,
                                        attributeID: attributeID,
                                        values: attributeValues
                                    )
                                    AttributeCompareValueCell(
                                        itemName: item.name,
                                        attributeName: attributeName,
                                        value: presentation.text,
                                        unit: presentation.unit,
                                        color: AttributeCompareFormatting.valueColor(
                                            for: item,
                                            values: attributeValues,
                                            highIsGood: result.attributeHighIsGood[attributeID] ?? true
                                        ),
                                        width: attributeColumnWidth,
                                        height: rowHeight
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 6)
    }

    private var accessibilityRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleAttributeIDs.enumerated()), id: \.element) { index, attributeID in
                if let attributeValues = result.compareResult[attributeID],
                   let attributeName = result.publishedAttributeInfo[attributeID]
                {
                    let unit = AttributeCompareFormatting.displayUnit(
                        attributeID: attributeID,
                        values: attributeValues
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let iconFileName = result.attributeIcons[attributeID] {
                                IconManager.shared.loadImage(for: iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        width: AttributeCompareStyle.attributeIconSize,
                                        height: AttributeCompareStyle.attributeIconSize
                                    )
                                    .foregroundStyle(.secondary)
                            }

                            Text(unit.map { "\(attributeName) (\($0))" } ?? attributeName)
                                .font(.headline)
                        }

                        ForEach(items) { item in
                            let value = AttributeCompareFormatting.formattedValue(
                                for: item,
                                attributeID: attributeID,
                                values: attributeValues
                            )
                            let color = AttributeCompareFormatting.valueColor(
                                for: item,
                                values: attributeValues,
                                highIsGood: result.attributeHighIsGood[attributeID] ?? true
                            )

                            HStack(spacing: 8) {
                                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .cornerRadius(4)

                                Text(item.name)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text(value.text)
                                    .font(.subheadline.weight(color == .secondary ? .regular : .semibold))
                                    .foregroundStyle(color)
                                    .multilineTextAlignment(.trailing)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(attributeName)\(value.unit.map { " (\($0))" } ?? ""), \(item.name): \(value.text)"
                            )
                        }
                    }
                    .padding(.vertical, 10)

                    if index < visibleAttributeIDs.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct AttributeCompareTiledSection: View {
    let result: AttributeCompareUtil.CompareResult
    let items: [DatabaseListItem]
    let attributeID: String

    var body: some View {
        if let attributeValues = result.compareResult[attributeID],
           let attributeName = result.publishedAttributeInfo[attributeID]
        {
            let unit = AttributeCompareFormatting.displayUnit(
                attributeID: attributeID,
                values: attributeValues
            )

            Section {
                ForEach(items) { item in
                    let value = AttributeCompareFormatting.formattedValue(
                        for: item,
                        attributeID: attributeID,
                        values: attributeValues
                    )
                    let color = AttributeCompareFormatting.valueColor(
                        for: item,
                        values: attributeValues,
                        highIsGood: result.attributeHighIsGood[attributeID] ?? true
                    )

                    HStack(spacing: 8) {
                        Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .cornerRadius(4)

                        Text(item.name)
                            .font(.subheadline)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Text(value.text)
                            .font(.subheadline.weight(color == .secondary ? .regular : .semibold))
                            .foregroundStyle(color)
                            .padding(.horizontal, color == .secondary ? 0 : 6)
                            .padding(.vertical, color == .secondary ? 0 : 3)
                            .background {
                                if color != .secondary {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(color.opacity(0.12))
                                }
                            }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(attributeName)\(unit.map { " (\($0))" } ?? ""), \(item.name): \(value.text)"
                    )
                }
            } header: {
                HStack(spacing: 6) {
                    if let iconFileName = result.attributeIcons[attributeID] {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: AttributeCompareStyle.attributeIconSize,
                                height: AttributeCompareStyle.attributeIconSize
                            )
                            .foregroundStyle(.secondary)
                    }

                    Text(unit.map { "\(attributeName) (\($0))" } ?? attributeName)
                        .font(.headline)
                }
                .padding(.horizontal, 20)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

/// 计算中 Section（带 `Misc_Calculating` header 的居中 ProgressView）
struct CalculatingSection: View {
    var body: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                    .padding()
                Spacer()
            }
        } header: {
            Text(NSLocalizedString("Misc_Calculating", comment: ""))
        }
    }
}

/// 属性对比结果：按选择的横向、纵向或平铺布局展示。
struct AttributeCompareResultSections: View {
    let result: AttributeCompareUtil.CompareResult
    let items: [DatabaseListItem]
    let showOnlyDifferences: Bool

    @AppStorage("attributeCompareLayout") private var layoutRawValue =
        AttributeCompareLayout.horizontal.rawValue

    private var layout: AttributeCompareLayout {
        get { AttributeCompareLayout(rawValue: layoutRawValue) ?? .horizontal }
        nonmutating set { layoutRawValue = newValue.rawValue }
    }

    var body: some View {
        let availableAttributeIDs = AttributeCompareUtil.visibleAttributeIDs(
            in: result,
            itemCount: items.count,
            showOnlyDifferences: showOnlyDifferences
        )

        if !availableAttributeIDs.isEmpty {
            switch layout {
            case .tiled:
                ForEach(availableAttributeIDs, id: \.self) { attributeID in
                    AttributeCompareTiledSection(
                        result: result,
                        items: items,
                        attributeID: attributeID
                    )
                }
            case .horizontal, .vertical:
                Section {
                    AttributeCompareMatrix(
                        result: result,
                        items: items,
                        visibleAttributeIDs: availableAttributeIDs,
                        layout: layout
                    )
                } header: {
                    comparisonHeader(attributeCount: availableAttributeIDs.count)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 0))
            }
        }
    }

    private func comparisonHeader(attributeCount: Int) -> some View {
        HStack {
            Text(NSLocalizedString("Main_Attribute_Compare", comment: ""))
            Spacer()
            Text("\(attributeCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
}
