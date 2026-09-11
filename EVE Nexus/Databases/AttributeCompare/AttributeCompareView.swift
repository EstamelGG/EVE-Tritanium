import SwiftUI

/// 属性对比物品选择器视图（使用过滤的顶级市场分组）
struct AttributeItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showSelected = true
    let allowedTopMarketGroupIDs: Set<Int>
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MarketItemSelectorIntegratedView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Attribute_Compare_Add_Item", comment: ""),
                allowedMarketGroups: allowedTopMarketGroupIDs,
                allowTypeIDs: [],
                existingItems: existingItems,
                onItemSelected: onItemSelected,
                onItemDeselected: onItemDeselected,
                onDismiss: { dismiss() },
                showSelected: showSelected
            )
        }
    }
}

/// 属性对比列表主视图
struct AttributeCompareView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var compares: [AttributeCompare] = []
    @State private var isShowingAddAlert = false
    @State private var tempCompareName = "" // 临时变量，用于接收用户输入
    @State private var searchText = ""
    @State private var isShowingRenameAlert = false
    @State private var renameCompare: AttributeCompare?
    @State private var renameCompareName = ""
    /// 新建列表后自动导航进入该列表（非 nil 时触发 push 详情页）
    @State private var autoNavigateCompareID: UUID?

    private var filteredCompares: [AttributeCompare] {
        if searchText.isEmpty {
            return compares
        } else {
            return compares.filter { compare in
                compare.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        compareList
            .searchable(
                text: $searchText,
                prompt: NSLocalizedString("Main_Database_Search", comment: "")
            )
            .navigationDestination(item: $autoNavigateCompareID) { id in
                if let compare = compares.first(where: { $0.id == id }) {
                    AttributeCompareDetailView(
                        databaseManager: databaseManager,
                        compare: compare
                    )
                }
            }
            .navigationTitle(NSLocalizedString("Main_Attribute_Compare", comment: ""))
            .toolbar {
                if #available(iOS 26.0, *) {
                    // iOS 26：搜索框与添加按钮共处底部同一 Liquid Glass 行（搜索框左、+ 右）
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        addCompareButton
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        addCompareButton
                    }
                }
            }
            .alert(
                NSLocalizedString("Main_Attribute_Compare_Add", comment: ""),
                isPresented: $isShowingAddAlert
            ) {
                TextField(
                    NSLocalizedString("Main_Attribute_Compare_Name", comment: ""),
                    text: $tempCompareName
                )

                Button(NSLocalizedString("Misc_Done", comment: "")) {
                    Logger.info("用户新增对比列表: \(tempCompareName)")
                    if !tempCompareName.isEmpty {
                        let newCompare = AttributeCompare(
                            name: tempCompareName,
                            items: []
                        )
                        compares.append(newCompare)
                        AttributeCompareManager.shared.saveCompare(newCompare)
                        tempCompareName = ""
                        // 新建成功后自动进入该列表
                        autoNavigateCompareID = newCompare.id
                    }
                }
                .disabled(tempCompareName.isEmpty)

                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                    tempCompareName = ""
                }
            }
            .alert(NSLocalizedString("Misc_Rename", comment: ""), isPresented: $isShowingRenameAlert) {
                TextField(NSLocalizedString("Misc_Name", comment: ""), text: $renameCompareName)

                Button(NSLocalizedString("Misc_Done", comment: "")) {
                    if let compare = renameCompare, !renameCompareName.isEmpty {
                        if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                            compares[index].name = renameCompareName
                            AttributeCompareManager.shared.saveCompare(compares[index])
                        }
                    }
                    renameCompare = nil
                    renameCompareName = ""
                }
                .disabled(renameCompareName.isEmpty)

                Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                    renameCompare = nil
                    renameCompareName = ""
                }
            }
            .task {
                compares = AttributeCompareManager.shared.loadCompares()
            }
    }

    /// 列表主体：长按拖动排序（onMove），导航/滑动/长按菜单
    private var compareList: some View {
        List {
            if filteredCompares.isEmpty {
                if searchText.isEmpty {
                    Text(NSLocalizedString("Main_Attribute_Compare_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                } else {
                    Text(String.localizedStringWithFormat(NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            } else {
                ForEach(filteredCompares) { compare in
                    NavigationLink {
                        AttributeCompareDetailView(
                            databaseManager: databaseManager,
                            compare: compare
                        )
                    } label: {
                        compareRowView(compare)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                                deleteCompare(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }

                        Button {
                            renameCompare = compare
                            renameCompareName = compare.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            renameCompare = compare
                            renameCompareName = compare.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                                deleteCompare(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .onMove(perform: moveCompares)
            }
        }
    }

    /// 添加对比列表按钮（iOS 26 位于底部搜索栏右侧，旧系统位于右上角）
    private var addCompareButton: some View {
        Button {
            tempCompareName = ""
            isShowingAddAlert = true
        } label: {
            Image(systemName: "plus")
        }
    }

    private func compareRowView(_ compare: AttributeCompare) -> some View {
        HStack {
            if !compare.items.isEmpty, let firstItem = compare.items.first {
                let icon = getItemIcon(typeID: firstItem.typeID)
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            } else {
                Image("Folder")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            }

            Text(compare.name)
                .lineLimit(1)
            Spacer()
            Text(
                String(
                    format: NSLocalizedString("Main_Attribute_Compare_Items", comment: ""),
                    compare.items.count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 获取物品图标
    private func getItemIcon(typeID: Int) -> UIImage {
        let iconFileName = ItemInfoMap.iconFilename(for: typeID)
        return IconManager.shared.loadUIImage(for: iconFileName)
    }

    private func deleteCompare(at offsets: IndexSet) {
        let comparesToDelete = offsets.map { filteredCompares[$0] }
        for compare in comparesToDelete {
            AttributeCompareManager.shared.deleteCompare(compare)
            if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                compares.remove(at: index)
            }
        }
    }

    /// 拖动排序：先在（可能被搜索过滤的）显示数组内移动，再映射回全量数组；未过滤时等价于直接移动
    private func moveCompares(from source: IndexSet, to destination: Int) {
        let filtered = filteredCompares
        guard !filtered.isEmpty else { return }

        var newFiltered = filtered
        newFiltered.move(fromOffsets: source, toOffset: destination)

        var filteredIterator = newFiltered.makeIterator()
        let filteredIDs = Set(filtered.map(\.id))
        var reordered: [AttributeCompare] = []
        reordered.reserveCapacity(compares.count)
        for compare in compares {
            if filteredIDs.contains(compare.id), let moved = filteredIterator.next() {
                reordered.append(moved)
            } else {
                reordered.append(compare)
            }
        }

        compares = reordered
        AttributeCompareManager.shared.saveManualOrder(compares)
    }
}
