import Foundation
import SwiftUI

/// 市场物品选择器视图
struct MarketItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    // 全选等批量添加时使用；为 `nil` 时仍逐条调用 `onItemSelected`
    var onBatchItemsSelected: (([DatabaseListItem]) -> Void)? = nil
    let onItemDeselected: (DatabaseListItem) -> Void
    let showSelected: Bool
    let allowTypeIDs: Set<Int>? // 新增：物品ID白名单
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MarketItemSelectorIntegratedView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Market_Watch_List_Add_Item", comment: ""),
                allowedMarketGroups: [], // 空集表示允许所有市场分组
                allowTypeIDs: allowTypeIDs, // 传递物品ID白名单
                existingItems: existingItems,
                onItemSelected: onItemSelected,
                onBatchItemsSelected: onBatchItemsSelected,
                onItemDeselected: onItemDeselected,
                onDismiss: { dismiss() },
                showSelected: showSelected
            )
        }
    }
}

/// 市场物品选择器组视图
struct MarketItemSelectorGroupView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let group: MarketGroup
    let tree: MarketTree
    let validGroups: Set<Int> // 有效的组ID集合
    let allowTypeIDs: Set<Int>? // 物品ID白名单
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    var onBatchItemsSelected: (([DatabaseListItem]) -> Void)? = nil
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    var body: some View {
        MarketBaseView(
            databaseManager: databaseManager,
            title: group.name,
            content: {
                ForEach(getValidSubGroups()) { subGroup in
                    MarketItemSelectorGroupRow(
                        group: subGroup,
                        tree: tree,
                        validGroups: validGroups,
                        allowTypeIDs: allowTypeIDs,
                        databaseManager: databaseManager,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onBatchItemsSelected: onBatchItemsSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            },
            searchFilter: { text in
                // 范围集合一次性计算，谓词内只做 O(1) 判断
                let groupIDs = tree.allSubGroupIDs(from: group.id)
                let whitelist = allowTypeIDs
                return { typeID, info in
                    guard let marketGroupID = info.marketGroupID, groupIDs.contains(marketGroupID) else {
                        return false
                    }
                    // 如果有物品ID白名单，添加物品ID筛选条件
                    if let whitelist, !whitelist.isEmpty, !whitelist.contains(typeID) {
                        return false
                    }
                    return info.names.matchesSearch(text)
                }
            },
            searchResultRowBuilder: { item in
                AnyView(
                    Button {
                        if existingItems.contains(item.id) {
                            onItemDeselected(item)
                        } else {
                            onItemSelected(item)
                        }
                    } label: {
                        HStack {
                            DatabaseListItemView(item: item, showDetails: true)
                            Spacer()
                            if showSelected {
                                Image(
                                    systemName: existingItems.contains(item.id)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundColor(
                                    existingItems.contains(item.id)
                                        ? .accentColor : .secondary
                                )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                )
            },
            sectionBatchAction: onBatchItemsSelected != nil ? { items in
                let toAdd = items.filter { !existingItems.contains($0.id) }
                guard !toAdd.isEmpty else { return }
                onBatchItemsSelected?(toAdd)
            } : nil,
            onDismiss: onDismiss
        )
    }

    /// 获取有效的子组
    private func getValidSubGroups() -> [MarketGroup] {
        let subGroups = tree.children(of: group.id)

        // 如果没有物品ID白名单，或者白名单为空，或者有效组ID列表为空，则返回所有子组
        if allowTypeIDs == nil || allowTypeIDs!.isEmpty || validGroups.isEmpty {
            return subGroups
        }

        // 否则只返回在有效组ID列表中的子组
        return subGroups.filter { validGroups.contains($0.id) }
    }
}

/// 市场物品选择器组行视图
struct MarketItemSelectorGroupRow: View {
    let group: MarketGroup
    let tree: MarketTree
    let validGroups: Set<Int> // 有效的组ID集合
    let allowTypeIDs: Set<Int>? // 物品ID白名单
    let databaseManager: DatabaseManager
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    var onBatchItemsSelected: (([DatabaseListItem]) -> Void)? = nil
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    var body: some View {
        if shouldShowGroup() {
            if tree.isLeaf(group) {
                // 最后一级目录，显示物品列表
                NavigationLink {
                    MarketItemSelectorItemListView(
                        databaseManager: databaseManager,
                        marketGroupID: group.id,
                        allowTypeIDs: allowTypeIDs,
                        title: group.name,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onBatchItemsSelected: onBatchItemsSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                } label: {
                    MarketGroupLabel(group: group)
                }
            } else {
                // 非最后一级目录，显示子目录
                NavigationLink {
                    MarketItemSelectorGroupView(
                        databaseManager: databaseManager,
                        group: group,
                        tree: tree,
                        validGroups: validGroups,
                        allowTypeIDs: allowTypeIDs,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onBatchItemsSelected: onBatchItemsSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                } label: {
                    MarketGroupLabel(group: group)
                }
            }
        }
    }

    /// 判断是否应该显示该组
    private func shouldShowGroup() -> Bool {
        if allowTypeIDs == nil || allowTypeIDs!.isEmpty || validGroups.isEmpty {
            return true
        }
        return validGroups.contains(group.id)
    }
}

/// 市场物品选择器物品列表视图
struct MarketItemSelectorItemListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    let allowTypeIDs: Set<Int>? // 新增：物品ID白名单
    let title: String
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    var onBatchItemsSelected: (([DatabaseListItem]) -> Void)? = nil
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]

    var groupedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        let unpublishedItems = items.filter { !$0.published }

        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []

        // 按科技等级分组
        var techLevelGroups: [Int?: [DatabaseListItem]] = [:]
        for item in publishedItems {
            let techLevel = item.metaGroupID
            if techLevelGroups[techLevel] == nil {
                techLevelGroups[techLevel] = []
            }
            techLevelGroups[techLevel]?.append(item)
        }

        // 添加已发布物品组
        for (techLevel, items) in techLevelGroups.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) {
            if let techLevel = techLevel {
                let name =
                    metaGroupNames[techLevel]
                        ?? NSLocalizedString("Main_Database_base", comment: "基础物品")
                result.append((id: techLevel, name: name, items: items))
            }
        }

        // 添加未分组的物品
        if let ungroupedItems = techLevelGroups[nil], !ungroupedItems.isEmpty {
            result.append(
                (
                    id: -2, name: NSLocalizedString("Main_Database_ungrouped", comment: "未分组"),
                    items: ungroupedItems
                )
            )
        }

        // 添加未发布物品组
        if !unpublishedItems.isEmpty {
            result.append(
                (
                    id: -1, name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"),
                    items: unpublishedItems
                )
            )
        }

        return result
    }

    var body: some View {
        MarketBaseView(
            databaseManager: databaseManager,
            title: title,
            content: {
                ForEach(groupedItems, id: \.id) { group in
                    Section {
                        ForEach(group.items) { item in
                            Button {
                                if existingItems.contains(item.id) {
                                    onItemDeselected(item)
                                } else {
                                    onItemSelected(item)
                                }
                            } label: {
                                HStack {
                                    DatabaseListItemView(
                                        item: item,
                                        showDetails: true
                                    )
                                    Spacer(minLength: 0)

                                    if showSelected {
                                        Image(
                                            systemName: existingItems.contains(item.id)
                                                ? "checkmark.circle.fill" : "circle"
                                        )
                                        .foregroundColor(
                                            existingItems.contains(item.id)
                                                ? .accentColor : .secondary
                                        )
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.name)
                            // 「全选」按钮仅与多选功能绑定：未提供批量回调（单选场景）时不显示
                            if let batch = onBatchItemsSelected {
                                Spacer(minLength: 8)
                                Button {
                                    let toAdd = group.items.filter { !existingItems.contains($0.id) }
                                    guard !toAdd.isEmpty else { return }
                                    batch(toAdd)
                                } label: {
                                    Text(NSLocalizedString("Main_Market_Select_All_In_Section", comment: ""))
                                        .font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            },
            searchFilter: { text in
                let whitelist = allowTypeIDs
                return { typeID, info in
                    guard info.marketGroupID == marketGroupID else { return false }
                    // 如果有物品ID白名单，添加物品ID筛选条件
                    if let whitelist, !whitelist.isEmpty, !whitelist.contains(typeID) {
                        return false
                    }
                    return info.names.matchesSearch(text)
                }
            },
            searchResultRowBuilder: { item in
                AnyView(
                    Button {
                        if existingItems.contains(item.id) {
                            onItemDeselected(item)
                        } else {
                            onItemSelected(item)
                        }
                    } label: {
                        HStack {
                            DatabaseListItemView(item: item, showDetails: true)
                            Spacer()
                            if showSelected {
                                Image(
                                    systemName: existingItems.contains(item.id)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundColor(
                                    existingItems.contains(item.id)
                                        ? .accentColor : .secondary
                                )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                )
            },
            sectionBatchAction: onBatchItemsSelected != nil ? { items in
                let toAdd = items.filter { !existingItems.contains($0.id) }
                guard !toAdd.isEmpty else { return }
                onBatchItemsSelected?(toAdd)
            } : nil
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onAppear {
            loadItems()
        }
    }

    private func loadItems() {
        let whitelist = allowTypeIDs
        items = databaseManager.searchItemsMemory(filter: { typeID, info in
            guard info.marketGroupID == marketGroupID else { return false }
            // 如果有物品ID白名单，添加物品ID筛选条件
            if let whitelist, !whitelist.isEmpty, !whitelist.contains(typeID) {
                return false
            }
            return true
        })

        // 加载科技等级名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
    }
}

struct MarketItemSelectorIntegratedView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let allowedMarketGroups: Set<Int>
    let allowTypeIDs: Set<Int>? // 新增：物品ID白名单
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    var onBatchItemsSelected: (([DatabaseListItem]) -> Void)? = nil
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void
    let showSelected: Bool

    /// 一次性构建的目录树索引：所有子节点查找/叶子判断/子树 ID 枚举均通过它 O(1) 完成
    @State private var marketTree: MarketTree = .init([])
    @State private var validMarketGroups: Set<Int> = [] // 缓存有效的市场组ID

    var body: some View {
        MarketBaseView(
            databaseManager: databaseManager,
            title: title,
            content: {
                ForEach(
                    getFilteredRootGroups()
                ) { group in
                    MarketItemSelectorGroupRow(
                        group: group,
                        tree: marketTree,
                        validGroups: validMarketGroups, // 传递有效组ID
                        allowTypeIDs: allowTypeIDs, // 传递物品ID白名单
                        databaseManager: databaseManager,
                        existingItems: existingItems,
                        onItemSelected: onItemSelected,
                        onBatchItemsSelected: onBatchItemsSelected,
                        onItemDeselected: onItemDeselected,
                        onDismiss: onDismiss,
                        showSelected: showSelected
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            },
            searchFilter: { text in
                // 通过索引树一次性枚举所有允许的市场组（含子孙），限定搜索范围
                let groupIDs = marketTree.allSubGroupIDs(
                    fromRoots: allowedMarketGroups.isEmpty ? [] : allowedMarketGroups
                )
                let restrictToGroups = !groupIDs.isEmpty
                let whitelist = allowTypeIDs
                let numericID = Int(text)
                return { typeID, info in
                    guard let marketGroupID = info.marketGroupID else { return false }
                    if restrictToGroups, !groupIDs.contains(marketGroupID) {
                        return false
                    }
                    // 如果有物品ID白名单，添加物品ID筛选条件
                    if let whitelist, !whitelist.isEmpty, !whitelist.contains(typeID) {
                        return false
                    }
                    return info.names.matchesSearch(text) || numericID == typeID
                }
            },
            searchTree: marketTree,
            searchResultRowBuilder: { item in
                AnyView(
                    Button {
                        if existingItems.contains(item.id) {
                            onItemDeselected(item)
                        } else {
                            onItemSelected(item)
                        }
                    } label: {
                        HStack {
                            DatabaseListItemView(item: item, showDetails: true)
                            Spacer()
                            if showSelected {
                                Image(
                                    systemName: existingItems.contains(item.id)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundColor(
                                    existingItems.contains(item.id)
                                        ? .accentColor : .secondary
                                )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                )
            },
            sectionBatchAction: onBatchItemsSelected != nil ? { items in
                let toAdd = items.filter { !existingItems.contains($0.id) }
                guard !toAdd.isEmpty else { return }
                onBatchItemsSelected?(toAdd)
            } : nil
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onAppear {
            // 一次性加载所有市场组并构建索引树；后续导航不再触碰 SQL
            marketTree = MarketManager.shared.buildTree(
                from: MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
            )

            // 如果有typeID白名单，计算有效的市场组
            if let typeIDs = allowTypeIDs, !typeIDs.isEmpty {
                Task {
                    validMarketGroups = await calculateValidMarketGroups(typeIDs: typeIDs)
                }
            }
        }
    }

    /// 根据筛选条件获取根目录
    private func getFilteredRootGroups() -> [MarketGroup] {
        // 通过索引树按白名单筛选根组（白名单为空时取所有顶级根组）
        let initialRootGroups = marketTree.filter(byIDs: allowedMarketGroups)

        // 如果有物品ID白名单且有效组ID已计算，过滤出有效的根目录
        let validRootGroups: [MarketGroup]
        if allowTypeIDs != nil, !validMarketGroups.isEmpty {
            validRootGroups = initialRootGroups.filter { validMarketGroups.contains($0.id) }
        } else {
            validRootGroups = initialRootGroups
        }

        // 应用剪枝逻辑，压缩只有单个子节点的顶层路径
        return pruneTopLevelPath(validRootGroups)
    }

    /// 剪枝函数：仅压缩顶层单一路径，直接返回最后一个分支的子节点
    private func pruneTopLevelPath(_ groups: [MarketGroup]) -> [MarketGroup] {
        // 如果有多个根组，则不需要剪枝
        if groups.count > 1 {
            return groups
        }

        // 空组直接返回
        if groups.isEmpty {
            return []
        }

        // 获取当前唯一根节点
        let currentGroup = groups[0]

        // 获取子节点（通过索引树 O(1) 查找）
        let subGroups = marketTree.children(of: currentGroup.id)

        // 过滤有效的子组（如果存在物品白名单）
        let validSubGroups: [MarketGroup]
        if allowTypeIDs != nil, !validMarketGroups.isEmpty {
            validSubGroups = subGroups.filter { validMarketGroups.contains($0.id) }
        } else {
            validSubGroups = subGroups
        }

        // 如果没有子节点，返回当前节点
        if validSubGroups.isEmpty {
            return [currentGroup]
        }

        // 如果只有一个子节点，继续沿着单一路径向下剪枝
        if validSubGroups.count == 1 {
            return pruneTopLevelPath(validSubGroups)
        }

        // 有多个子节点，表示到达分支点，返回所有子节点而不是当前节点
        return validSubGroups
    }

    /// 计算有效的市场组ID（有物品在allowTypeIDs中的组）
    private func calculateValidMarketGroups(typeIDs: Set<Int>) async -> Set<Int> {
        guard !typeIDs.isEmpty else { return Set() }

        let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")

        // 查询所有在白名单中的物品及其市场组ID
        let query = """
            SELECT DISTINCT marketGroupID
            FROM types
            WHERE type_id IN (\(typeIDsString))
            AND marketGroupID IS NOT NULL
        """

        var validGroupIDs = Set<Int>()

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let groupID = row["marketGroupID"] as? Int {
                    validGroupIDs.insert(groupID)

                    // 添加所有父级组ID
                    var currentGroup = marketTree.group(byID: groupID)
                    while let group = currentGroup, let parentID = group.parentGroupID {
                        validGroupIDs.insert(parentID)
                        currentGroup = marketTree.group(byID: parentID)
                    }
                }
            }
        }

        return validGroupIDs
    }
}
