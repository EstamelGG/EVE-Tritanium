import Combine
import SwiftUI

/// 分组类型
enum GroupingType {
    /// Categories / Groups：只分已发布与未发布
    case publishedOnly
    /// Items：按 metaGroup 分组，外加未发布组
    case metaGroups
}

/// 统一的列表视图
struct DatabaseListView: View {
    @ObservedObject var databaseManager: DatabaseManager

    let title: String
    let groupingType: GroupingType
    let loadData: (DatabaseManager) -> ([DatabaseListItem], [Int: String])
    let searchData: ((DatabaseManager, String) -> ([DatabaseListItem], [Int: String], [Int: String]))?
    /// 搜索结果数超过阈值时，由宿主构建目录结构内容（逐级下钻）；为 nil 时一律平铺
    var searchTreeContent: (([DatabaseListItem]) -> AnyView)? = nil

    /// 结果数超过该阈值时使用目录模式，否则平铺
    private static let directoryModeThreshold = 50

    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    @State private var groupNames: [Int: String] = [:]
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var lastSearchResults: ([DatabaseListItem], [Int: String], [Int: String])?
    @State private var isShowingSearchResults = false
    @State private var isSearchActive = false

    private var publishedItemsView: some View {
        ForEach(groupedPublishedItems, id: \.id) { group in
            Section(
                header: Text(group.name)
            ) {
                ForEach(group.items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private var unpublishedItemsView: some View {
        Section(
            header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布"))
        ) {
            ForEach(items.filter { !$0.published }) { item in
                itemRow(item)
            }
        }
    }

    private func itemRow(_ item: DatabaseListItem) -> some View {
        NavigationLink(destination: item.navigationDestination) {
            DatabaseListItemView(
                item: item,
                showDetails: groupingType == .metaGroups || isShowingSearchResults
            )
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            Color(.systemBackground)
                .ignoresSafeArea()
                .overlay {
                    VStack {
                        ProgressView()
                        Text(NSLocalizedString("Main_Database_Searching", comment: ""))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
        } else if items.isEmpty && isShowingSearchResults {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("Misc_Not_Found", comment: ""),
                    systemImage: "magnifyingglass"
                )
            }
        } else if searchText.isEmpty && isSearchActive {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    isSearchActive = false
                }
        }
    }

    var body: some View {
        List {
            let publishedItems = items.filter(\.published)
            let unpublishedItems = items.filter { !$0.published }
            if isShowingSearchResults, items.count > Self.directoryModeThreshold,
               let searchTreeContent
            {
                // 目录模式：与浏览一致的层级结构，仅保留含命中的分支
                searchTreeContent(items)
            } else if isShowingSearchResults {
                // 平铺模式：已发布物品按 类目 > 分组 分 section
                if !publishedItems.isEmpty {
                    ForEach(groupItemsByGroup(publishedItems), id: \.id) { group in
                        Section(
                            header: Text(group.name)
                        ) {
                            ForEach(group.items) { item in
                                itemRow(item)
                            }
                        }
                    }
                }
                // 未发布物品单独 section
                if !unpublishedItems.isEmpty {
                    unpublishedItemsView
                }
            } else if !publishedItems.isEmpty {
                publishedItemsView
            }

            // 仅在非搜索态显示未发布物品分组（搜索态已集成到目录/分组结构）
            if !isShowingSearchResults, !unpublishedItems.isEmpty {
                unpublishedItemsView
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onSubmit(of: .search) {
            if !searchText.isEmpty {
                performSearch(with: searchText)
            }
        }
        .navigationBarBackButtonHidden(isShowingSearchResults)
        .toolbar {
            if isShowingSearchResults {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        searchText = ""
                        isSearchActive = false
                        loadInitialData()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(NSLocalizedString("Misc_back", comment: ""))
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                loadInitialData()
                isLoading = false
                lastSearchResults = nil
            }
        }
        .overlay(loadingOverlay)
        .navigationTitle(title)
        .onAppear {
            if let lastResults = lastSearchResults {
                items = lastResults.0
                metaGroupNames = lastResults.1
                groupNames = lastResults.2
            } else {
                loadInitialData()
            }
        }
    }

    private func loadInitialData() {
        let (loadedItems, loadedMetaGroupNames) = loadData(databaseManager)
        items = loadedItems
        metaGroupNames = loadedMetaGroupNames
        isShowingSearchResults = false
        lastSearchResults = nil
    }

    private func performSearch(with text: String) {
        guard let searchData else { return }

        isLoading = true

        DispatchQueue.main.async {
            let (searchResults, searchMetaGroupNames, searchGroupNames) = searchData(
                databaseManager, text
            )

            items = searchResults

            if searchMetaGroupNames.isEmpty {
                let metaGroupIDs = Set(searchResults.compactMap(\.metaGroupID))
                metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
            } else {
                metaGroupNames = searchMetaGroupNames
            }

            if searchGroupNames.isEmpty {
                let groupIDs = Set(searchResults.compactMap(\.groupID))
                groupNames = databaseManager.loadGroupNames(for: Array(groupIDs))
            } else {
                groupNames = searchGroupNames
            }

            lastSearchResults = (searchResults, metaGroupNames, groupNames)
            isShowingSearchResults = true
            isLoading = false
        }
    }

    /// 已发布物品的分组（非搜索态）
    private var groupedPublishedItems: [SearchResultSection<DatabaseListItem>] {
        let publishedItems = items.filter(\.published)

        if groupingType == .metaGroups {
            return groupItemsByMetaGroup(publishedItems)
        }

        return [
            SearchResultSection(
                identity: .group(0),
                name: NSLocalizedString("Main_Database_published", comment: ""),
                items: publishedItems
            ),
        ]
    }

    // MARK: - 搜索结果平铺分组

    /// 按 类目 > 分组 分 section（类目按 EVE 客户端优先级排序，物品保持搜索结果的 meta/名称序）
    private func groupItemsByGroup(
        _ items: [DatabaseListItem]
    ) -> [SearchResultSection<DatabaseListItem>] {
        var groupedByCategory: [Int: [(groupID: Int, items: [DatabaseListItem])]] = [:]

        for item in items {
            let categoryID = item.categoryID ?? 0
            let groupID = item.groupID ?? 0

            if groupedByCategory[categoryID] == nil {
                groupedByCategory[categoryID] = []
            }

            if let index = groupedByCategory[categoryID]?.firstIndex(where: { $0.groupID == groupID }) {
                groupedByCategory[categoryID]?[index].items.append(item)
            } else {
                groupedByCategory[categoryID]?.append((groupID: groupID, items: [item]))
            }
        }

        let sortedCategories = groupedByCategory.keys.sorted { cat1, cat2 in
            let index1 = MarketManager.categoryPriority.firstIndex(of: cat1) ?? Int.max
            let index2 = MarketManager.categoryPriority.firstIndex(of: cat2) ?? Int.max
            return index1 == index2 ? cat1 < cat2 : index1 < index2
        }

        var result: [SearchResultSection<DatabaseListItem>] = []
        for categoryID in sortedCategories {
            guard let categoryGroups = groupedByCategory[categoryID] else { continue }
            for group in categoryGroups.sorted(by: { $0.groupID < $1.groupID }) {
                let name = groupNames[group.groupID]
                    ?? SDEMemoryStore.group(for: group.groupID)?.name
                    ?? "Group \(group.groupID)"
                result.append(
                    SearchResultSection(identity: .group(group.groupID), name: name, items: group.items)
                )
            }
        }

        return result.filter { !$0.items.isEmpty }
    }

    private func groupItemsByMetaGroup(
        _ items: [DatabaseListItem]
    ) -> [SearchResultSection<DatabaseListItem>] {
        var grouped: [Int: [DatabaseListItem]] = [:]

        for item in items {
            let metaGroupID = item.metaGroupID ?? 0
            if grouped[metaGroupID] == nil {
                grouped[metaGroupID] = []
            }
            grouped[metaGroupID]?.append(item)
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { metaGroupID, items in
                if metaGroupID == 0 {
                    return SearchResultSection(
                        identity: .group(0),
                        name: NSLocalizedString("Main_Database_base", comment: "基础物品"),
                        items: items
                    )
                }
                if let groupName = metaGroupNames[metaGroupID] {
                    return SearchResultSection(identity: .group(metaGroupID), name: groupName, items: items)
                }
                Logger.warning("MetaGroupID \(metaGroupID) 没有对应的名称")
                return SearchResultSection(
                    identity: .group(metaGroupID), name: "MetaGroup \(metaGroupID)", items: items
                )
            }
            .filter { !$0.items.isEmpty }
    }
}

/// 搜索控制器（防抖处理，供其他仍需要自动搜索的视图使用）
class SearchController: ObservableObject {
    private let searchSubject = PassthroughSubject<String, Never>()
    private let debounceInterval: TimeInterval = 0.5
    var cancellables = Set<AnyCancellable>()

    /// 防抖处理后的搜索
    var debouncedSearchPublisher: AnyPublisher<String, Never> {
        searchSubject
            .map { text -> String? in
                text.isEmpty ? nil : text
            }
            .debounce(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    func processSearchInput(_ query: String) {
        searchSubject.send(query)
    }
}
