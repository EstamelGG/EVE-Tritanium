import SwiftUI

// MARK: - 筛选面板（市场目录树导航，仅物品可多选；完成时统一应用）

/// 筛选面板紧凑行距（各层共用）
private let AssetFilterRowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

private extension AssetTypeFilterNode {
    /// 覆盖率 100%（n ≥ m 且 m > 0）
    var isFullyCovered: Bool {
        totalTypeCount > 0 && ownedTypeCount >= totalTypeCount
    }
}

/// 目录行内容：图标 + 名称，行尾覆盖率 n / m 种（100% 时绿色；0 覆盖时整体置灰，仍可进入查看）
private struct AssetFilterHierarchyRowLabel: View {
    let node: AssetTypeFilterNode
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            AssetIconView(iconName: node.iconFileName, size: CharacterAssetsIconSize.standard)
                .opacity(isEnabled ? 1 : 0.4)
            Text(node.name)
                .foregroundColor(isEnabled ? .primary : .secondary)
            Spacer(minLength: 8)
            Text(
                String(
                    format: NSLocalizedString("Assets_Filter_Coverage_Format", comment: ""),
                    node.ownedTypeCount, node.totalTypeCount
                )
            )
            .font(.caption)
            .foregroundColor(node.isFullyCovered ? .green : .secondary)
        }
    }
}

/// 物品行：图标 + 名称，右侧选中圈（未拥有时置灰且不可选中）
private struct AssetFilterItemRow: View {
    let item: AssetTypeItemFilter
    let isSelected: Bool

    var body: some View {
        HStack {
            AssetIconView(iconName: item.iconFileName, size: CharacterAssetsIconSize.standard)
                .opacity(item.isOwned ? 1 : 0.4)
            Text(item.name)
                .foregroundColor(item.isOwned ? .primary : .secondary)
            Spacer(minLength: 0)
            if item.isOwned {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 筛选面板根页：市场目录导航 + 特殊物品入口；完成时统一应用 draft，X 放弃改动
struct AssetsFilterSheet: View {
    @ObservedObject var viewModel: CharacterAssetsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftTypeIds: Set<Int>

    init(viewModel: CharacterAssetsViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _draftTypeIds = State(initialValue: viewModel.selectedTypeIds)
    }

    /// 完成：应用 draft 并关闭整个面板（各层共用）
    private var applyDraft: () -> Void {
        {
            viewModel.applyTypeFilter(draftTypeIds)
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(viewModel.marketRootFilterNodes) { node in
                        NavigationLink {
                            AssetsFilterMarketDestination(
                                node: node,
                                viewModel: viewModel,
                                draftTypeIds: $draftTypeIds,
                                onApply: applyDraft
                            )
                        } label: {
                            AssetFilterHierarchyRowLabel(
                                node: node,
                                isEnabled: node.isEnabled
                            )
                        }
                        .listRowInsets(AssetFilterRowInsets)
                    }
                } header: {
                    Text(NSLocalizedString("Assets_Filter_Category_Section", comment: ""))
                }

                Section {
                    specialLink(
                        title: NSLocalizedString("Assets_Filter_No_Market_Items", comment: ""),
                        systemIcon: "archivebox",
                        items: viewModel.filterOwnedItemsWithoutMarketGroup()
                    )
                    specialLink(
                        title: NSLocalizedString("Assets_Filter_Unpublished_Items", comment: ""),
                        systemIcon: "eye.slash",
                        items: viewModel.filterOwnedUnpublishedItems()
                    )
                } header: {
                    Text(NSLocalizedString("Assets_Filter_Other_Section", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("Assets_Filter_Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        if !draftTypeIds.isEmpty {
                            Button(NSLocalizedString("Assets_Filter_Clear", comment: "")) {
                                draftTypeIds = []
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "")) { applyDraft() }
                }
            }
        }
        // 面板只能通过"完成/关闭"退出，禁止下拉手势误关闭丢弃草稿
        .interactiveDismissDisabled(true)
    }

    /// 特殊物品入口行：系统图标 + 名称 + 物品种类数第二行
    private func specialLink(
        title: String, systemIcon: String, items: [AssetTypeItemFilter]
    ) -> some View {
        NavigationLink {
            AssetsFilterItemListView(
                title: title,
                itemsProvider: { items },
                draftTypeIds: $draftTypeIds,
                onApply: applyDraft
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemIcon)
                    .font(.system(size: 18))
                    .frame(
                        width: CharacterAssetsIconSize.standard,
                        height: CharacterAssetsIconSize.standard
                    )
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundColor(.primary)
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Assets_Filter_Type_Count_Format", comment: ""
                            ),
                            items.count
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .listRowInsets(AssetFilterRowInsets)
    }
}

/// 市场目录行目的地：叶子目录进入物品列表，否则继续下钻
struct AssetsFilterMarketDestination: View {
    let node: AssetTypeFilterNode
    @ObservedObject var viewModel: CharacterAssetsViewModel
    @Binding var draftTypeIds: Set<Int>
    let onApply: () -> Void

    var body: some View {
        if viewModel.marketGroupFilters(for: node.id).isEmpty {
            AssetsFilterItemListView(
                title: node.name,
                itemsProvider: { viewModel.marketFilterItems(for: node.id) },
                draftTypeIds: $draftTypeIds,
                onApply: onApply
            )
        } else {
            AssetsFilterMarketGroupView(
                node: node,
                viewModel: viewModel,
                draftTypeIds: $draftTypeIds,
                onApply: onApply
            )
        }
    }
}

/// 筛选面板目录层（市场视图）：子目录下钻，纯导航（0 覆盖的目录也可进入查看）
struct AssetsFilterMarketGroupView: View {
    let node: AssetTypeFilterNode
    @ObservedObject var viewModel: CharacterAssetsViewModel
    @Binding var draftTypeIds: Set<Int>
    let onApply: () -> Void

    var body: some View {
        Form {
            selectAllSection
            Section {
                ForEach(viewModel.marketGroupFilters(for: node.id)) { child in
                    NavigationLink {
                        AssetsFilterMarketDestination(
                            node: child,
                            viewModel: viewModel,
                            draftTypeIds: $draftTypeIds,
                            onApply: onApply
                        )
                    } label: {
                        AssetFilterHierarchyRowLabel(node: child, isEnabled: child.isEnabled)
                    }
                    .listRowInsets(AssetFilterRowInsets)
                }
            }
        }
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Common_Done", comment: "")) { onApply() }
            }
        }
    }

    /// "全部过滤"开关：一键选/退选子树内全部已拥有物品（子树无已拥有物品时隐藏整节）
    @ViewBuilder
    private var selectAllSection: some View {
        let ownedTypeIds = viewModel.marketOwnedTypeIds(for: node.id)
        if !ownedTypeIds.isEmpty {
            let isFullySelected = ownedTypeIds.isSubset(of: draftTypeIds)
            Section {
                Button {
                    if isFullySelected {
                        draftTypeIds.subtract(ownedTypeIds)
                    } else {
                        draftTypeIds.formUnion(ownedTypeIds)
                    }
                } label: {
                    HStack {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Assets_Filter_Select_All_In_Directory_Format", comment: ""
                                ),
                                ownedTypeIds.count
                            )
                        )
                        Spacer(minLength: 8)
                        Image(systemName: isFullySelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isFullySelected ? .accentColor : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(AssetFilterRowInsets)
            }
        }
    }
}

/// 筛选面板物品层：目录内全量物品（已拥有优先展示），多选（仅已拥有可选），header 提供"全选"
struct AssetsFilterItemListView: View {
    let title: String
    let itemsProvider: () -> [AssetTypeItemFilter]
    @Binding var draftTypeIds: Set<Int>
    let onApply: () -> Void

    var body: some View {
        let items = itemsProvider()
        Form {
            Section {
                ForEach(items) { item in
                    if item.isOwned {
                        Button {
                            if draftTypeIds.contains(item.id) {
                                draftTypeIds.remove(item.id)
                            } else {
                                draftTypeIds.insert(item.id)
                            }
                        } label: {
                            AssetFilterItemRow(
                                item: item,
                                isSelected: draftTypeIds.contains(item.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(AssetFilterRowInsets)
                    } else {
                        AssetFilterItemRow(item: item, isSelected: false)
                            .listRowInsets(AssetFilterRowInsets)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                    Spacer(minLength: 8)
                    // 切换式：已全选时变"取消全选"并清空本节，否则全选本节已拥有物品
                    let ownedIds = Set(items.filter(\.isOwned).map(\.id))
                    let allSelected = !ownedIds.isEmpty && ownedIds.isSubset(of: draftTypeIds)
                    Button {
                        if allSelected {
                            draftTypeIds.subtract(ownedIds)
                        } else {
                            draftTypeIds.formUnion(ownedIds)
                        }
                    } label: {
                        Text(
                            NSLocalizedString(
                                allSelected
                                    ? "Assets_Filter_Deselect_All_In_Section"
                                    : "Main_Market_Select_All_In_Section",
                                comment: ""
                            )
                        )
                        .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Common_Done", comment: "")) { onApply() }
            }
        }
    }
}
