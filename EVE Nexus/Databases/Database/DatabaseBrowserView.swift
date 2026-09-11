import SwiftUI

/// 浏览层级
enum BrowserLevel: Hashable {
    case categories
    case groups(categoryID: Int, categoryName: String)
    case items(groupID: Int, groupName: String)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .categories:
            hasher.combine(0)
        case let .groups(categoryID, _):
            hasher.combine(1)
            hasher.combine(categoryID)
        case let .items(groupID, _):
            hasher.combine(2)
            hasher.combine(groupID)
        }
    }
}

struct DatabaseBrowserView: View {
    private typealias CachePayload = ([DatabaseListItem], [Int: String], [Int: String])

    @ObservedObject var databaseManager: DatabaseManager
    let level: BrowserLevel

    private var groupingType: GroupingType {
        switch level {
        case .categories, .groups: .publishedOnly
        case .items: .metaGroups
        }
    }

    private var title: String {
        switch level {
        case .categories:
            NSLocalizedString("Main_Database_title", comment: "")
        case let .groups(_, categoryName):
            categoryName
        case let .items(_, groupName):
            groupName
        }
    }

    var body: some View {
        NavigationStack {
            DatabaseListView(
                databaseManager: databaseManager,
                title: title,
                groupingType: groupingType,
                loadData: { dbManager in
                    let data = loadDataForLevel(dbManager)
                    return (data.0, data.1)
                },
                searchData: { dbManager, searchText in
                    let (items, metaGroupNames, _) = searchItems(dbManager, searchText)
                    return (Self.sortedByMetaThenName(items), metaGroupNames, [:])
                },
                searchTreeContent: directoryContentProvider
            )
        }
    }

    /// 目录模式内容（结果数超阈值时）：类目/分组层提供层级目录，物品层无更深层级故平铺
    private var directoryContentProvider: (([DatabaseListItem]) -> AnyView)? {
        switch level {
        case .categories:
            return { items in
                AnyView(
                    DatabaseSearchCategoryRows(items: items, databaseManager: databaseManager)
                )
            }
        case let .groups(categoryID, _):
            return { items in
                AnyView(
                    DatabaseSearchGroupRows(
                        items: items, categoryID: categoryID, databaseManager: databaseManager
                    )
                )
            }
        case .items:
            return nil
        }
    }

    // MARK: - Load

    private func loadDataForLevel(_ dbManager: DatabaseManager) -> CachePayload {
        let data = loadDataFromDatabase(dbManager)

        if case .categories = level {
            IconManager.shared.preloadCommonIcons(icons: data.0.map(\.iconFileName))
        }
        return data
    }

    private func searchItems(
        _ dbManager: DatabaseManager, _ searchText: String
    ) -> CachePayload {
        // 始终全库搜索，不再按当前浏览层级限定 categoryID/groupID
        let items = dbManager.searchItemsMemory(
            filter: { typeID, info in
                info.names.matchesSearch(searchText) || Int(searchText) == typeID
            },
            exactMatchText: searchText
        )
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        let metaGroupNames = dbManager.loadMetaGroupNames(for: Array(metaGroupIDs))
        return (items, metaGroupNames, [:])
    }

    private func loadDataFromDatabase(_ dbManager: DatabaseManager) -> CachePayload {
        switch level {
        case .categories:
            let (published, unpublished) = dbManager.loadCategories()
            let items = (published + unpublished).map { category in
                DatabaseListItem(
                    id: category.id,
                    name: category.name,
                    enName: category.enName,
                    iconFileName: category.iconFileNew,
                    published: category.published,
                    navigationDestination: AnyView(
                        DatabaseBrowserView(
                            databaseManager: databaseManager,
                            level: .groups(
                                categoryID: category.id,
                                categoryName: category.name
                            )
                        )
                    )
                )
            }
            return (items, [:], [:])

        case let .groups(categoryID, _):
            let (published, unpublished) = dbManager.loadGroups(for: categoryID)
            let items = (published + unpublished).map { group in
                DatabaseListItem(
                    id: group.id,
                    name: group.name,
                    enName: group.enName,
                    iconFileName: group.icon_filename,
                    published: group.published,
                    categoryID: group.categoryID,
                    groupID: group.id,
                    groupName: group.name,
                    navigationDestination: AnyView(
                        DatabaseBrowserView(
                            databaseManager: databaseManager,
                            level: .items(groupID: group.id, groupName: group.name)
                        )
                    )
                )
            }
            return (items, [:], [:])

        case let .items(groupID, groupName):
            let (items, metaGroupNames) = dbManager.loadItems(for: groupID, groupName: groupName)
            return (items, metaGroupNames, [:])
        }
    }

    private static func sortedByMetaThenName(_ items: [DatabaseListItem]) -> [DatabaseListItem] {
        items.sorted { a, b in
            let metaA = a.metaGroupID ?? -1
            let metaB = b.metaGroupID ?? -1
            if metaA != metaB { return metaA < metaB }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

// MARK: - 搜索目录模式（结果数超阈值时：与原浏览一致的层级下钻，仅保留含命中的分支）

/// 目录行：图标 + 名称 + 命中数，样式与浏览列表行一致
private struct DatabaseSearchDirectoryRow: View {
    let iconFileName: String
    let name: String
    let count: Int

    var body: some View {
        HStack {
            Image(uiImage: IconManager.shared.loadUIImage(for: iconFileName))
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            Text(name)
                .foregroundColor(.primary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// 类目层目录行集合（类目按 EVE 客户端优先级排序，已发布/未发布分 section）
private struct DatabaseSearchCategoryRows: View {
    let items: [DatabaseListItem]
    let databaseManager: DatabaseManager

    private var countByCategory: [Int: Int] {
        var counts: [Int: Int] = [:]
        for item in items {
            counts[item.categoryID ?? 0, default: 0] += 1
        }
        return counts
    }

    private var sortedCategoryIDs: [Int] {
        countByCategory.keys.sorted { a, b in
            let indexA = MarketManager.categoryPriority.firstIndex(of: a) ?? Int.max
            let indexB = MarketManager.categoryPriority.firstIndex(of: b) ?? Int.max
            return indexA == indexB ? a < b : indexA < indexB
        }
    }

    private var publishedCategoryIDs: [Int] {
        sortedCategoryIDs.filter { SDEMemoryStore.category(for: $0)?.published == true }
    }

    private var unpublishedCategoryIDs: [Int] {
        sortedCategoryIDs.filter { SDEMemoryStore.category(for: $0)?.published == false }
    }

    var body: some View {
        if !publishedCategoryIDs.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_published", comment: "已发布"))
            ) {
                categoryRows(for: publishedCategoryIDs)
            }
        }
        if !unpublishedCategoryIDs.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布"))
            ) {
                categoryRows(for: unpublishedCategoryIDs)
            }
        }
    }

    private func categoryRows(for ids: [Int]) -> some View {
        ForEach(ids, id: \.self) { categoryID in
            let info = SDEMemoryStore.category(for: categoryID)
            NavigationLink {
                DatabaseSearchGroupsView(
                    categoryID: categoryID,
                    categoryName: info?.name ?? "Category \(categoryID)",
                    items: items,
                    databaseManager: databaseManager
                )
            } label: {
                DatabaseSearchDirectoryRow(
                    iconFileName: info?.iconFilename ?? IconManager.defaultIcon,
                    name: info?.name ?? "Category \(categoryID)",
                    count: countByCategory[categoryID] ?? 0
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

/// 类目下钻页：该类目中含命中的分组列表
private struct DatabaseSearchGroupsView: View {
    let categoryID: Int
    let categoryName: String
    let items: [DatabaseListItem]
    let databaseManager: DatabaseManager

    var body: some View {
        List {
            DatabaseSearchGroupRows(
                items: items, categoryID: categoryID, databaseManager: databaseManager
            )
        }
        .navigationTitle(categoryName)
    }
}

/// 分组层目录行集合（限定类目，分组按 groupID 排序，已发布/未发布分 section）
private struct DatabaseSearchGroupRows: View {
    let items: [DatabaseListItem]
    let categoryID: Int
    let databaseManager: DatabaseManager

    private var itemsByGroup: [Int: [DatabaseListItem]] {
        Dictionary(grouping: items.filter { ($0.categoryID ?? 0) == categoryID }) { $0.groupID ?? 0 }
    }

    private var sortedGroupIDs: [Int] {
        itemsByGroup.keys.sorted()
    }

    private var publishedGroupIDs: [Int] {
        sortedGroupIDs.filter { SDEMemoryStore.group(for: $0)?.published == true }
    }

    private var unpublishedGroupIDs: [Int] {
        sortedGroupIDs.filter { SDEMemoryStore.group(for: $0)?.published == false }
    }

    var body: some View {
        if !publishedGroupIDs.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_published", comment: "已发布"))
            ) {
                groupRows(for: publishedGroupIDs)
            }
        }
        if !unpublishedGroupIDs.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布"))
            ) {
                groupRows(for: unpublishedGroupIDs)
            }
        }
    }

    private func groupRows(for ids: [Int]) -> some View {
        ForEach(ids, id: \.self) { groupID in
            let groupItems = itemsByGroup[groupID] ?? []
            let info = SDEMemoryStore.group(for: groupID)
            NavigationLink {
                DatabaseSearchItemsView(
                    groupName: info?.name ?? "Group \(groupID)",
                    items: groupItems
                )
            } label: {
                DatabaseSearchDirectoryRow(
                    iconFileName: info?.iconFilename ?? IconManager.defaultIcon,
                    name: info?.name ?? "Group \(groupID)",
                    count: groupItems.count
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

/// 叶子页：某分组下的全部命中物品（已发布按 metaGroup 分组 + 未发布独立 section）
private struct DatabaseSearchItemsView: View {
    let groupName: String
    let items: [DatabaseListItem]

    private var publishedItems: [DatabaseListItem] {
        items.filter(\.published)
    }

    private var unpublishedItems: [DatabaseListItem] {
        items.filter { !$0.published }
    }

    private var itemsByMetaGroup: [(id: Int, name: String, items: [DatabaseListItem])] {
        SDEMemoryStore.metaGroupSections(publishedItems) { $0.metaGroupID ?? 0 }
    }

    var body: some View {
        List {
            // 已发布物品按 metaGroup 分组
            ForEach(itemsByMetaGroup, id: \.id) { group in
                Section(
                    header: Text(group.name)
                ) {
                    ForEach(group.items) { item in
                        NavigationLink(destination: item.navigationDestination) {
                            DatabaseListItemView(item: item, showDetails: true)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
            // 未发布物品
            if !unpublishedItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_Database_unpublished", comment: "未发布"))
                ) {
                    ForEach(unpublishedItems) { item in
                        NavigationLink(destination: item.navigationDestination) {
                            DatabaseListItemView(item: item, showDetails: true)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(groupName)
    }
}

// MARK: - List Item Row

struct DatabaseListItemView: View {
    private enum CategoryID {
        static let ship = 6
        static let module = 7
        static let charge = 8
        static let drone = 18
        static let structureModule = 66
    }

    let item: DatabaseListItem
    let showDetails: Bool
    var showCargoIndicator: Bool = false
    var onAttributeQuickCompare: ((Int) -> Void)? = nil

    private var showsAttributeQuickCompareMenuItem: Bool {
        onAttributeQuickCompare != nil && item.attributeCompareEligible
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(item.name)
                if showCargoIndicator {
                    Image("cargo_fit")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundColor(.secondary)
                }
            }

            if showDetails, let categoryID = item.categoryID {
                detailRow(for: categoryID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contextMenu {
            if !item.name.isEmpty {
                Button {
                    UIPasteboard.general.string = item.name
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Name", comment: ""),
                        systemImage: "doc.on.doc"
                    )
                }
                if let enName = item.enName, !enName.isEmpty, enName != item.name {
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
            if showsAttributeQuickCompareMenuItem, let mg = item.marketGroupID {
                Button {
                    onAttributeQuickCompare?(mg)
                } label: {
                    Label(
                        NSLocalizedString("Main_Attribute_Quick_Compare", comment: ""),
                        systemImage: "square.split.2x1"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(for categoryID: Int) -> some View {
        switch categoryID {
        case CategoryID.module, CategoryID.structureModule:
            HStack(spacing: 8) {
                if let pgNeed = item.pgNeed {
                    IconWithValueView(iconName: "pg", numericValue: Int(pgNeed), unit: " MW")
                }
                if let cpuNeed = item.cpuNeed {
                    IconWithValueView(iconName: "cpu", numericValue: Int(cpuNeed), unit: " Tf")
                }
                if let rigCost = item.rigCost {
                    IconWithValueView(iconName: "rigcost", numericValue: rigCost)
                }
            }

        case CategoryID.charge, CategoryID.drone:
            if hasAnyDamage {
                HStack(spacing: 8) {
                    ForEach(0 ..< 4, id: \.self) { index in
                        HStack(spacing: 4) {
                            Image(DamageTypePalette.damageIcons[index])
                                .resizable()
                                .frame(width: 18, height: 18)
                            DamageBarView(
                                percentage: damagePercentage(at: index),
                                color: DamageTypePalette.colors[index]
                            )
                        }
                    }
                }
            }

        case CategoryID.ship:
            HStack(spacing: 8) {
                ForEach(shipSlotEntries, id: \.icon) { entry in
                    IconWithValueView(iconName: entry.icon, numericValue: entry.value)
                }
            }

        default:
            EmptyView()
        }
    }

    private var shipSlotEntries: [(icon: String, value: Int)] {
        [
            ("highSlot", item.highSlot),
            ("midSlot", item.midSlot),
            ("lowSlot", item.lowSlot),
            ("rigSlot", item.rigSlot),
            ("gunSlot", item.gunSlot),
            ("missSlot", item.missSlot),
        ]
        .compactMap { icon, value in
            guard let value, value != 0 else { return nil }
            return (icon, value)
        }
    }

    private var damageValues: [Double?] {
        [item.emDamage, item.themDamage, item.kinDamage, item.expDamage]
    }

    private var hasAnyDamage: Bool {
        let values = damageValues
        guard values.allSatisfy({ $0 != nil }) else { return false }
        return values.compactMap { $0 }.contains { $0 > 0 }
    }

    private func damagePercentage(at index: Int) -> Int {
        let damages = damageValues.compactMap { $0 }
        let total = damages.reduce(0, +)
        guard total > 0, index < damages.count else { return 0 }
        return Int(round((damages[index] / total) * 100))
    }
}

/// 图标和数值的组合
struct IconWithValueView: View {
    let iconName: String
    let value: String

    init(iconName: String, numericValue: Int, unit: String? = nil) {
        self.iconName = iconName
        value = unit.map { "\(FormatUtil.format(Double(numericValue)))\($0)" }
            ?? FormatUtil.format(Double(numericValue))
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(iconName)
                .resizable()
                .frame(width: 18, height: 18)
            Text(value)
        }
    }
}
