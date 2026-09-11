import SwiftUI

struct BlueprintSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager

    let onBlueprintSelected: (DatabaseListItem) -> Void
    let onDismiss: () -> Void

    /// 蓝图分类ID
    private let blueprintCategoryId = 9

    var body: some View {
        NavigationStack {
            DatabaseBlueprintBrowserView(
                databaseManager: databaseManager,
                categoryId: blueprintCategoryId,
                onBlueprintSelected: onBlueprintSelected
            )
            .navigationTitle(
                NSLocalizedString("Blueprint_Calculator_Select_Blueprint", comment: "选择蓝图")
            )
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Misc_Cancel", comment: "取消")) {
                        onDismiss()
                    }
                }
            }
        }
    }
}

/// 重构后的蓝图数据库浏览器视图
struct DatabaseBlueprintBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let categoryId: Int
    let onBlueprintSelected: (DatabaseListItem) -> Void

    @State private var navigationPath = NavigationPath()
    @State private var allBlueprints: [DatabaseListItem] = []
    @State private var blueprintGroups: [BlueprintGroup] = []
    @State private var reactionMarketGroups: Set<Int> = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack(path: $navigationPath) {
            if isLoading {
                ProgressView(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BlueprintGroupsListView(
                    databaseManager: databaseManager,
                    categoryId: categoryId,
                    navigationPath: $navigationPath,
                    onBlueprintSelected: onBlueprintSelected,
                    allBlueprints: allBlueprints,
                    blueprintGroups: blueprintGroups,
                    reactionMarketGroups: reactionMarketGroups
                )
                .navigationDestination(for: BlueprintGroup.self) { group in
                    BlueprintItemsListView(
                        databaseManager: databaseManager,
                        group: group,
                        onBlueprintSelected: onBlueprintSelected,
                        allBlueprints: allBlueprints.filter { $0.groupID == group.id },
                        reactionMarketGroups: reactionMarketGroups
                    )
                }
            }
        }
        .onAppear {
            if allBlueprints.isEmpty {
                loadAllBlueprintData()
            }
        }
    }

    private func loadAllBlueprintData() {
        isLoading = true

        Task {
            await MainActor.run {
                // 1. 获取反应市场组
                reactionMarketGroups = getReactionMarketGroups()
                Logger.info("加载了 \(reactionMarketGroups.count) 个反应市场组")

                // 2. 加载所有蓝图物品
                let blueprints = loadAllBlueprints()
                Logger.info("加载了 \(blueprints.count) 个蓝图物品")

                // 3. 构建组结构
                let groups = buildGroupsFromBlueprints(blueprints)
                Logger.info("构建了 \(groups.count) 个蓝图组")

                allBlueprints = blueprints
                blueprintGroups = groups
                isLoading = false
            }
        }
    }

    /// 获取反应市场组集合 - 内存索引展开子树
    private func getReactionMarketGroups() -> Set<Int> {
        let tree = MarketManager.shared.buildTree(
            from: MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
        )
        return Set(tree.allSubGroupIDs(from: 1849))
    }

    /// 加载所有蓝图物品
    private func loadAllBlueprints() -> [DatabaseListItem] {
        let blueprints = databaseManager.searchItemsMemory { _, info in
            info.categoryID == categoryId && info.published
        }

        // 使用localizedCompare对蓝图进行排序
        return blueprints.sorted { blueprint1, blueprint2 in
            // 首先按组ID排序
            let groupId1 = blueprint1.groupID ?? -1
            let groupId2 = blueprint2.groupID ?? -1
            if groupId1 != groupId2 {
                return groupId1 < groupId2
            }
            // 然后按名称排序
            return blueprint1.name.localizedCompare(blueprint2.name) == .orderedAscending
        }
    }

    /// 从蓝图列表构建组结构
    private func buildGroupsFromBlueprints(_ blueprints: [DatabaseListItem]) -> [BlueprintGroup] {
        // 按组ID分组
        let groupedBlueprints = Dictionary(grouping: blueprints) { $0.groupID ?? -1 }

        // 构建组列表
        var groups: [BlueprintGroup] = []

        for (groupId, groupBlueprints) in groupedBlueprints {
            guard groupId != -1, let firstBlueprint = groupBlueprints.first else { continue }

            // 加载组信息
            if let groupInfo = loadGroupInfo(groupId: groupId) {
                let group = BlueprintGroup(
                    id: groupId,
                    name: groupInfo.name,
                    iconFileName: groupInfo.iconFileName,
                    published: groupInfo.published
                )
                groups.append(group)
            } else {
                // 如果无法加载组信息，使用第一个蓝图的组名
                let group = BlueprintGroup(
                    id: groupId,
                    name: firstBlueprint.groupName ?? "not_found",
                    iconFileName: "not_found",
                    published: true
                )
                groups.append(group)
            }
        }

        // 排序：已发布的在前，然后按名称排序
        return groups.sorted { group1, group2 in
            if group1.published != group2.published {
                return group1.published && !group2.published
            }
            return group1.name.localizedCompare(group2.name) == .orderedAscending
        }
    }

    /// 加载组信息（内存索引）
    private func loadGroupInfo(groupId: Int) -> (
        name: String, iconFileName: String, published: Bool
    )? {
        guard let group = SDEMemoryStore.group(for: groupId) else { return nil }
        return (name: group.name, iconFileName: group.iconFilename, published: group.published)
    }
}

/// 蓝图组数据模型
struct BlueprintGroup: Hashable, Identifiable {
    let id: Int
    let name: String
    let iconFileName: String
    let published: Bool
}

/// 蓝图组列表视图
struct BlueprintGroupsListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let categoryId: Int
    @Binding var navigationPath: NavigationPath
    let onBlueprintSelected: (DatabaseListItem) -> Void
    let allBlueprints: [DatabaseListItem]
    let blueprintGroups: [BlueprintGroup]
    let reactionMarketGroups: Set<Int>

    @State private var searchText = ""
    @State private var isSearching = false

    var body: some View {
        List {
            if isSearching && !searchText.isEmpty {
                // 搜索结果显示
                ForEach(searchResults, id: \.id) { blueprint in
                    BlueprintSearchResultRow(
                        blueprint: blueprint,
                        reactionMarketGroups: reactionMarketGroups,
                        onSelected: onBlueprintSelected
                    )
                }
            } else {
                // 组列表显示
                ForEach(filteredGroups) { group in
                    HStack {
                        // 组图标
                        Image(uiImage: IconManager.shared.loadUIImage(for: group.iconFileName))
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            // 组名称
                            Text(group.name)
                                .foregroundColor(.primary)
                                .font(.body)

                            // 显示该组中的蓝图数量和反应蓝图数量
                            let groupBlueprints = allBlueprints.filter { $0.groupID == group.id }
                            let reactionCount = groupBlueprints.filter { blueprint in
                                if let marketGroupID = blueprint.marketGroupID {
                                    return reactionMarketGroups.contains(marketGroupID)
                                }
                                return false
                            }.count

                            HStack(spacing: 8) {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Blueprint_Calculator_Blueprints_Count",
                                            comment: "%d 个蓝图"
                                        ), groupBlueprints.count
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)

                                if reactionCount > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Blueprint_Calculator_Reactions_Count",
                                                comment: "其中 %d 个反应"
                                            ), reactionCount
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(4)
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        navigationPath.append(group)
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearching,
            prompt: NSLocalizedString("Main_Database_search_placeholder", comment: "搜索")
        )
        .navigationTitle(NSLocalizedString("Main_Database_Blueprints", comment: "蓝图"))
        .navigationBarTitleDisplayMode(.large)
    }

    private var filteredGroups: [BlueprintGroup] {
        if searchText.isEmpty {
            return blueprintGroups
        } else {
            // 当有搜索文本时，只显示包含匹配蓝图的组
            let matchingGroupIds = Set(searchResults.compactMap { $0.groupID })
            return blueprintGroups.filter { matchingGroupIds.contains($0.id) }
        }
    }

    private var searchResults: [DatabaseListItem] {
        guard !searchText.isEmpty else { return [] }

        return allBlueprints.filter { blueprint in
            SDEMemoryStore.type(for: blueprint.id)?.names.matchesSearch(searchText) == true
                || blueprint.groupName?.localizedCaseInsensitiveContains(searchText) == true
        }.sorted { blueprint1, blueprint2 in
            // 优先显示名称匹配的
            let name1Match =
                SDEMemoryStore.type(for: blueprint1.id)?.names.matchesSearch(searchText) == true
            let name2Match =
                SDEMemoryStore.type(for: blueprint2.id)?.names.matchesSearch(searchText) == true

            if name1Match != name2Match {
                return name1Match
            }

            // 然后按名称排序
            return blueprint1.name.localizedCompare(blueprint2.name) == .orderedAscending
        }
    }
}

/// 蓝图搜索结果行视图
struct BlueprintSearchResultRow: View {
    let blueprint: DatabaseListItem
    let reactionMarketGroups: Set<Int>
    let onSelected: (DatabaseListItem) -> Void

    private var isReaction: Bool {
        if let marketGroupID = blueprint.marketGroupID {
            return reactionMarketGroups.contains(marketGroupID)
        }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            // 蓝图图标
            Image(uiImage: IconManager.shared.loadUIImage(for: blueprint.iconFileName))
                .resizable()
                .frame(width: 40, height: 40)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(blueprint.name)
                        .foregroundColor(.primary)
                        .font(.body)

                    if isReaction {
                        Text(
                            NSLocalizedString("Blueprint_Calculator_Reaction_Label", comment: "反应")
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                    }
                }

                if let groupName = blueprint.groupName {
                    Text(groupName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelected(blueprint)
        }
    }
}

/// 蓝图物品列表视图
struct BlueprintItemsListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let group: BlueprintGroup
    let onBlueprintSelected: (DatabaseListItem) -> Void
    let allBlueprints: [DatabaseListItem]
    let reactionMarketGroups: Set<Int>

    @State private var metaGroupNames: [Int: String] = [:]
    @State private var searchText = ""

    /// 使用传入的蓝图数据而不是重新加载
    private var items: [DatabaseListItem] {
        return allBlueprints
    }

    var body: some View {
        List {
            if !searchText.isEmpty {
                // 搜索结果
                ForEach(filteredItems) { item in
                    BlueprintItemRowView(
                        item: item,
                        metaGroupNames: metaGroupNames,
                        reactionMarketGroups: reactionMarketGroups,
                        onSelected: { selectedItem in
                            onBlueprintSelected(selectedItem)
                        }
                    )
                }
            } else {
                // 按MetaGroup分组显示
                ForEach(groupedItems, id: \.id) { group in
                    Section(
                        header: Text(group.name)
                    ) {
                        ForEach(group.items) { item in
                            BlueprintItemRowView(
                                item: item,
                                metaGroupNames: metaGroupNames,
                                reactionMarketGroups: reactionMarketGroups,
                                onSelected: { selectedItem in
                                    onBlueprintSelected(selectedItem)
                                }
                            )
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            prompt: NSLocalizedString("Main_Database_search_placeholder", comment: "搜索")
        )
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            // 加载科技等级名称
            let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
            metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
        }
    }

    private var filteredItems: [DatabaseListItem] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var groupedItems: [ItemGroup] {
        // 按MetaGroup分组
        let publishedItems = items.filter { $0.published }
        let unpublishedItems = items.filter { !$0.published }

        var groups: [ItemGroup] = []

        // 处理已发布物品
        let publishedGrouped = Dictionary(grouping: publishedItems) { item in
            item.metaGroupID ?? -1
        }

        for (metaGroupId, groupItems) in publishedGrouped.sorted(by: { $0.key < $1.key }) {
            let groupName =
                metaGroupNames[metaGroupId]
                    ?? NSLocalizedString("Main_Database_unknown_meta_group", comment: "未知科技组")
            groups.append(
                ItemGroup(
                    id: metaGroupId,
                    name: groupName,
                    items: groupItems.sorted {
                        $0.name.localizedCompare($1.name) == .orderedAscending
                    }
                )
            )
        }

        // 处理未发布物品
        if !unpublishedItems.isEmpty {
            groups.append(
                ItemGroup(
                    id: -999,
                    name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"),
                    items: unpublishedItems.sorted {
                        $0.name.localizedCompare($1.name) == .orderedAscending
                    }
                )
            )
        }

        return groups
    }
}

/// 物品组数据模型
struct ItemGroup {
    let id: Int
    let name: String
    let items: [DatabaseListItem]
}

/// 蓝图物品行视图
struct BlueprintItemRowView: View {
    let item: DatabaseListItem
    let metaGroupNames: [Int: String]
    let reactionMarketGroups: Set<Int>
    let onSelected: (DatabaseListItem) -> Void

    private var isReaction: Bool {
        if let marketGroupID = item.marketGroupID {
            return reactionMarketGroups.contains(marketGroupID)
        }
        return false
    }

    var body: some View {
        HStack {
            // 蓝图图标
            Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                // 蓝图名称和反应标识
                HStack {
                    Text(item.name)
                        .foregroundColor(.primary)
                        .font(.body)
                        .multilineTextAlignment(.leading)

                    if isReaction {
                        Text(
                            NSLocalizedString("Blueprint_Calculator_Reaction_Label", comment: "反应")
                        )
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                    }

                    Spacer()
                }

                // MetaGroup信息
                if let metaGroupId = item.metaGroupID,
                   let metaGroupName = metaGroupNames[metaGroupId]
                {
                    Text(metaGroupName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelected(item)
        }
        .contextMenu {
            if !item.name.isEmpty {
                Button {
                    UIPasteboard.general.string = item.name
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc"
                    )
                }
                if let enName = item.enName, !enName.isEmpty && enName != item.name {
                    Button {
                        UIPasteboard.general.string = enName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Trans", comment: ""),
                            systemImage: "translate"
                        )
                    }
                }
            }
        }
    }
}
