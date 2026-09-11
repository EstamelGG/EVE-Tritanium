import SwiftUI

// MARK: - 工具类

enum MarketItemGrouper {
    /// 复用 MarketManager 中的统一定义，避免多处重复硬编码
    static let categoryPriority = MarketManager.categoryPriority

    static func groupSearchResults(_ items: [DatabaseListItem]) -> [SearchResultSection<DatabaseListItem>] {
        guard !items.isEmpty else { return [] }

        var groupedByCategory: [Int: [(groupID: Int, name: String, items: [DatabaseListItem])]] =
            [:]

        for item in items {
            let categoryID = item.categoryID ?? 0
            let groupID = item.groupID ?? 0
            let groupName = item.groupName ?? "Unknown Group"

            if groupedByCategory[categoryID] == nil {
                groupedByCategory[categoryID] = []
            }

            if let index = groupedByCategory[categoryID]?.firstIndex(where: {
                $0.groupID == groupID
            }) {
                groupedByCategory[categoryID]?[index].items.append(item)
            } else {
                groupedByCategory[categoryID]?.append(
                    (groupID: groupID, name: groupName, items: [item])
                )
            }
        }

        var result: [SearchResultSection<DatabaseListItem>] = []

        // 优先级分类 + 其他分类
        let allCategories =
            categoryPriority + groupedByCategory.keys.filter { !categoryPriority.contains($0) }

        for categoryID in allCategories {
            if let groups = groupedByCategory[categoryID] {
                for group in groups.sorted(by: { $0.groupID < $1.groupID }) {
                    let sortedItems = group.items.sorted { item1, item2 in
                        if item1.metaGroupID != item2.metaGroupID {
                            return (item1.metaGroupID ?? -1) < (item2.metaGroupID ?? -1)
                        }
                        return item1.name.localizedCaseInsensitiveCompare(item2.name)
                            == .orderedAscending
                    }
                    result.append(
                        SearchResultSection(identity: .group(group.groupID), name: group.name, items: sortedItems)
                    )
                }
            }
        }

        return result
    }
}

// MARK: - 主视图

struct MarketItemTreeSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let marketGroupTree: [MarketGroupNode]
    let allowTypeIDs: Set<Int>
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: (_ lastVisitedGroupID: Int?, _ searchText: String?) -> Void
    let lastVisitedGroupID: Int?
    let initialSearchText: String?

    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var searchResults: [DatabaseListItem] = []
    @State private var isLoading = false
    @State private var currentGroupID: Int?
    @State private var navigationPath = NavigationPath()
    @State private var hasNavigated = false
    @StateObject private var searchController = SearchController()

    var groupedSearchResults: [SearchResultSection<DatabaseListItem>] {
        MarketItemGrouper.groupSearchResults(searchResults)
    }

    /// 获取当前市场树的所有市场组ID（递归）
    private var allowedMarketGroupIDs: Set<Int> {
        var groupIDs = Set<Int>()

        func collectGroupIDs(_ nodes: [MarketGroupNode]) {
            for node in nodes {
                groupIDs.insert(node.id)
                collectGroupIDs(node.children)
            }
        }

        collectGroupIDs(marketGroupTree)
        return groupIDs
    }

    /// 内建搜索方法，限制在当前市场树范围内
    private func performTreeConstrainedSearch(with keyword: String) -> [DatabaseListItem] {
        Logger.info("开始树限制搜索，关键词: \"\(keyword)\"")
        let startTime = Date()

        let marketGroupIDs = allowedMarketGroupIDs

        // 如果没有允许的市场组ID，返回空数组
        if marketGroupIDs.isEmpty {
            Logger.warning("没有允许的市场组ID，返回空结果")
            return []
        }

        let numericID = Int(keyword)
        let results = databaseManager.searchItemsMemory { typeID, info in
            guard let mg = info.marketGroupID, marketGroupIDs.contains(mg) else { return false }
            if !allowTypeIDs.isEmpty, !allowTypeIDs.contains(typeID) { return false }
            return info.names.matchesSearch(keyword) || numericID == typeID
        }

        Logger.info(
            "树限制搜索找到 \(results.count) 个匹配项，耗时: \(Date().timeIntervalSince(startTime) * 1000)ms"
        )

        return Array(results.prefix(100))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if isSearchActive && !searchText.isEmpty {
                    searchResultsContent
                } else {
                    marketTreeContent
                }
            }
            .navigationTitle(title)
            .navigationDestination(for: MarketNodeSubViewDestination.self) { destination in
                MarketNodeSubView(
                    databaseManager: databaseManager,
                    group: destination.group,
                    allowTypeIDs: allowTypeIDs,
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: { groupID, searchText in
                        currentGroupID = groupID
                        onDismiss(groupID, searchText)
                    },
                    updateCurrentGroup: { currentGroupID = $0 }
                )
            }
            .navigationDestination(for: MarketNodeItemsViewDestination.self) { destination in
                MarketNodeItemsView(
                    databaseManager: databaseManager,
                    group: destination.group,
                    allowTypeIDs: allowTypeIDs,
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: { groupID, searchText in
                        currentGroupID = groupID
                        onDismiss(groupID, searchText)
                    }
                )
            }
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                // placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(NSLocalizedString("Main_Database_Search", comment: "搜索"))
            )
            .onChange(of: searchText) { _, newValue in
                handleSearchTextChange(newValue)
            }
            .onChange(of: isSearchActive) { _, newValue in
                Logger.info("搜索激活状态变化: \(newValue ? "激活" : "取消激活")")
                if !newValue && !searchText.isEmpty {
                    Logger.info("搜索被关闭时的搜索文本: \"\(searchText)\"")
                }
            }
            .onAppear {
                setupSearch()
                handleInitialState()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "完成")) {
                        handleDismiss()
                    }
                }
            }
        }
        .onDisappear {
            handleViewDisappear()
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private var searchResultsContent: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding()
        } else if searchResults.isEmpty {
            Text(NSLocalizedString("Misc_Not_Found", comment: "未找到结果"))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            ForEach(groupedSearchResults, id: \.id) { group in
                Section(
                    header: Text(group.name)
                ) {
                    ForEach(group.items) { item in
                        ItemNodeRow(
                            item: item,
                            onSelect: {
                                if existingItems.contains(item.id) {
                                    onItemDeselected(item)
                                } else {
                                    onItemSelected(item)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var marketTreeContent: some View {
        if marketGroupTree.isEmpty {
            Text(NSLocalizedString("Misc_No_Data", comment: "无数据"))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            ForEach(marketGroupTree) { group in
                MarketGroupNodeRow(
                    group: group,
                    databaseManager: databaseManager,
                    allowTypeIDs: allowTypeIDs,
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: { groupID, searchText in
                        currentGroupID = groupID
                        onDismiss(groupID, searchText)
                    },
                    updateCurrentGroup: { currentGroupID = $0 }
                )
            }
        }
    }

    // MARK: - 私有方法

    private func setupSearch() {
        searchController.debouncedSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { query in
                guard !searchText.isEmpty else { return }
                performSearch(with: query)
            }
            .store(in: &searchController.cancellables)
    }

    private func performSearch(with text: String) {
        isLoading = true
        Logger.info("执行树限制搜索: \"\(text)\"")

        DispatchQueue.global(qos: .userInitiated).async {
            let results = performTreeConstrainedSearch(with: text)

            DispatchQueue.main.async {
                searchResults = results
                Logger.info("搜索结果数量: \(results.count)")
                isLoading = false
            }
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        Logger.info("搜索文本变化: \"\(newValue)\"")
        if newValue.isEmpty {
            searchResults = []
            isLoading = false
        } else {
            isLoading = true
            searchController.processSearchInput(newValue)
        }
    }

    private func handleInitialState() {
        if let initialText = initialSearchText, !initialText.isEmpty {
            Logger.info("使用上次的搜索关键词：\(initialText)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchText = initialText
                isSearchActive = true
            }
        } else if !hasNavigated, let lastVisitedGroupID = lastVisitedGroupID, lastVisitedGroupID > 0 {
            Logger.info("准备导航到上次访问的目录：ID=\(lastVisitedGroupID)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                navigateToGroup(id: lastVisitedGroupID)
                hasNavigated = true
            }
        }
    }

    private func navigateToGroup(id: Int) {
        Logger.info("开始直接导航到指定目录：ID=\(id)")

        // 清空当前路径
        navigationPath.removeLast(navigationPath.count)

        // 查找目标节点的完整路径
        let nodePath = findNodePath(id: id, in: marketGroupTree)

        if !nodePath.isEmpty {
            // 构建完整的导航路径（跳过根节点）
            let pathToNavigate = nodePath.dropFirst()
            Logger.info("找到路径，直接导航到：\(nodePath.map { $0.name }.joined(separator: " -> "))")

            // 一次性构建完整的NavigationPath，避免逐级跳转动画
            var newPath = NavigationPath()
            for (index, node) in pathToNavigate.enumerated() {
                if node.children.isEmpty || index == pathToNavigate.count - 1 {
                    // 最后一级或叶子节点 - 物品列表
                    newPath.append(MarketNodeItemsViewDestination(group: node))
                } else {
                    // 中间节点 - 子目录
                    newPath.append(MarketNodeSubViewDestination(group: node))
                }
            }

            // 一次性设置完整路径，实现直接跳转
            navigationPath = newPath
            currentGroupID = id

        } else if let node = findNodeById(marketGroupTree, id: id) {
            Logger.info("在顶层找到目标节点：\(node.name)")
            var newPath = NavigationPath()
            if node.children.isEmpty {
                newPath.append(MarketNodeItemsViewDestination(group: node))
            } else {
                newPath.append(MarketNodeSubViewDestination(group: node))
            }
            navigationPath = newPath
            currentGroupID = id
        } else {
            Logger.warning("未找到ID为\(id)的节点")
        }
    }

    private func findNodePath(id: Int, in nodes: [MarketGroupNode]) -> [MarketGroupNode] {
        for node in nodes {
            if node.id == id {
                return [node]
            }
            let pathInChildren = findNodePath(id: id, in: node.children)
            if !pathInChildren.isEmpty {
                return [node] + pathInChildren
            }
        }
        return []
    }

    private func findNodeById(_ nodes: [MarketGroupNode], id: Int) -> MarketGroupNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let found = findNodeById(node.children, id: id) {
                return found
            }
        }
        return nil
    }

    private func handleDismiss() {
        let finalSearchText = searchText.isEmpty ? nil : searchText
        if let text = finalSearchText {
            Logger.info("准备传递搜索关键词：\(text)")
        }
        Logger.info("关闭视图，返回当前浏览目录ID: \(currentGroupID?.description ?? "nil")")
        onDismiss(currentGroupID, finalSearchText)
    }

    private func handleViewDisappear() {
        Logger.info(
            "视图消失，搜索文本: \(searchText.isEmpty ? "空" : "\"\(searchText)\""), 搜索状态: \(isSearchActive ? "激活" : "未激活")"
        )

        if !searchText.isEmpty {
            Logger.info("视图消失时保存搜索文本: \"\(searchText)\"")
            onDismiss(currentGroupID, searchText)
        }
    }
}

// MARK: - 导航目标

struct MarketNodeSubViewDestination: Hashable {
    let group: MarketGroupNode

    static func == (lhs: MarketNodeSubViewDestination, rhs: MarketNodeSubViewDestination) -> Bool {
        lhs.group.id == rhs.group.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(group.id)
    }
}

struct MarketNodeItemsViewDestination: Hashable {
    let group: MarketGroupNode

    static func == (lhs: MarketNodeItemsViewDestination, rhs: MarketNodeItemsViewDestination)
        -> Bool
    {
        lhs.group.id == rhs.group.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(group.id)
    }
}

// MARK: - 组件视图

struct ItemNodeRow: View {
    let item: DatabaseListItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                DatabaseListItemView(item: item, showDetails: true)
            }
        }
        .foregroundColor(.primary)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

struct MarketGroupNodeRow: View {
    let group: MarketGroupNode
    let databaseManager: DatabaseManager
    let allowTypeIDs: Set<Int>
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: (Int?, String?) -> Void
    let updateCurrentGroup: (Int) -> Void

    var body: some View {
        NavigationLink {
            if group.children.isEmpty {
                MarketNodeItemsView(
                    databaseManager: databaseManager,
                    group: group,
                    allowTypeIDs: allowTypeIDs,
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: onDismiss
                )
            } else {
                MarketNodeSubView(
                    databaseManager: databaseManager,
                    group: group,
                    allowTypeIDs: allowTypeIDs,
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: onDismiss,
                    updateCurrentGroup: updateCurrentGroup
                )
            }
        } label: {
            HStack {
                Image(uiImage: IconManager.shared.loadUIImage(for: group.iconName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)

                Text(group.name)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .onAppear {
            if group.children.isEmpty {
                Logger.info("访问物品列表目录：\(group.name)，ID: \(group.id)")
            }
            updateCurrentGroup(group.id)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

struct MarketNodeSubView: View {
    let databaseManager: DatabaseManager
    let group: MarketGroupNode
    let allowTypeIDs: Set<Int>
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: (Int?, String?) -> Void
    let updateCurrentGroup: (Int) -> Void

    var body: some View {
        List {
            ForEach(group.children) { subGroup in
                MarketGroupNodeRow(
                    group: subGroup,
                    databaseManager: databaseManager,
                    allowTypeIDs: allowTypeIDs,
                    existingItems: existingItems,
                    onItemSelected: onItemSelected,
                    onItemDeselected: onItemDeselected,
                    onDismiss: onDismiss,
                    updateCurrentGroup: updateCurrentGroup
                )
            }
        }
        .navigationTitle(group.name)
        .onAppear {
            Logger.info("打开子目录视图：\(group.name)，ID: \(group.id)，子节点数: \(group.children.count)")
            updateCurrentGroup(group.id)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Misc_Done", comment: "完成")) {
                    onDismiss(group.id, nil)
                }
            }
        }
    }
}

struct MarketNodeItemsView: View {
    let databaseManager: DatabaseManager
    let group: MarketGroupNode
    let allowTypeIDs: Set<Int>
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    let onDismiss: (Int?, String?) -> Void

    @State private var items: [DatabaseListItem] = []
    @State private var isLoading = true
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

        // 添加各种分组
        for (techLevel, items) in techLevelGroups.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) {
            if let techLevel = techLevel {
                let name =
                    metaGroupNames[techLevel]
                        ?? NSLocalizedString("Main_Database_base", comment: "基础物品")
                result.append((id: techLevel, name: name, items: items))
            }
        }

        if let ungroupedItems = techLevelGroups[nil], !ungroupedItems.isEmpty {
            result.append(
                (
                    id: -2, name: NSLocalizedString("Main_Database_ungrouped", comment: "未分组"),
                    items: ungroupedItems
                )
            )
        }

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
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if items.isEmpty {
                Text(NSLocalizedString("Misc_No_Data", comment: "无数据"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(groupedItems, id: \.id) { group in
                    Section(
                        header: Text(group.name)
                    ) {
                        ForEach(group.items) { item in
                            ItemNodeRow(
                                item: item,
                                onSelect: {
                                    Logger.info(
                                        "用户在目录 \(self.group.name)(ID: \(self.group.id)) 中选择了装备 \(item.name)(ID: \(item.id))"
                                    )
                                    if existingItems.contains(item.id) {
                                        onItemDeselected(item)
                                    } else {
                                        onItemSelected(item)
                                        onDismiss(self.group.id, nil)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .onAppear {
            Logger.info("打开物品列表视图：\(group.name)，ID: \(group.id)")
            loadItems()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Misc_Done", comment: "完成")) {
                    onDismiss(group.id, nil)
                }
            }
        }
    }

    private func loadItems() {
        isLoading = true

        items = databaseManager.searchItemsMemory { typeID, info in
            guard info.marketGroupID == group.id else { return false }
            if !allowTypeIDs.isEmpty, !allowTypeIDs.contains(typeID) { return false }
            return true
        }

        // 加载科技等级名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))

        isLoading = false
    }
}
