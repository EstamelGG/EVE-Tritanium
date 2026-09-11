import SwiftUI

/// 舰载机类型枚举
enum FighterType: Int {
    case light = 840 // 轻型舰载机
    case heavy = 1310 // 重型舰载机
    case support = 2239 // 辅助舰载机
}

/// 舰载机选择器
struct FighterSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var items: [DatabaseListItem] = []
    @State private var isLoading = true
    @State private var metaGroupNames: [Int: String] = [:]
    @Environment(\.dismiss) private var dismiss

    let onSelect: (DatabaseListItem) -> Void
    let fighterType: FighterType
    let shipTypeID: Int

    init(
        databaseManager: DatabaseManager, fighterType: FighterType, shipTypeID: Int,
        onSelect: @escaping (DatabaseListItem) -> Void
    ) {
        self.databaseManager = databaseManager
        self.onSelect = onSelect
        self.fighterType = fighterType
        self.shipTypeID = shipTypeID
    }

    /// 按科技等级分组的物品
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
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label(
                            NSLocalizedString("Misc_No_Data", comment: "无数据"),
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                } else {
                    ForEach(groupedItems, id: \.id) { group in
                        Section(
                            header: Text(group.name)
                        ) {
                            ForEach(group.items) { item in
                                Button {
                                    Logger.info(
                                        "用户选择舰载机: \(item.name)(ID: \(item.id)), 类型: \(fighterType.rawValue), 飞船ID: \(shipTypeID)"
                                    )
                                    dismiss()
                                    onSelect(item)
                                } label: {
                                    HStack {
                                        DatabaseListItemView(item: item, showDetails: true)
                                    }
                                }
                                .foregroundColor(.primary)
                                .listRowInsets(
                                    EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle(getTitleForFighterType())
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadItems()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }

    /// 根据舰载机类型获取标题
    private func getTitleForFighterType() -> String {
        switch fighterType {
        case .light:
            return NSLocalizedString("Fitting_Select_Light_Fighter", comment: "选择轻型舰载机")
        case .heavy:
            return NSLocalizedString("Fitting_Select_Heavy_Fighter", comment: "选择重型舰载机")
        case .support:
            return NSLocalizedString("Fitting_Select_Support_Fighter", comment: "选择辅助舰载机")
        }
    }

    /// 加载舰载机物品数据
    private func loadItems() {
        isLoading = true
        Logger.info("开始加载全部舰载机数据")

        // 加载全部舰载机（所有三种类型）
        let allowedGroups: Set = [840, 1310, 2239]
        let allFighters = databaseManager.searchItemsMemory { _, info in
            guard let mg = info.marketGroupID else { return false }
            return allowedGroups.contains(mg) && info.published
        }

        // 根据当前舰载机类型过滤
        items = allFighters.filter { item in
            item.marketGroupID == fighterType.rawValue
        }

        // 加载科技等级名称
        let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
        metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))

        Logger.info(
            "加载完成，全部舰载机: \(allFighters.count)，当前类型(\(fighterType.rawValue)): \(items.count)"
        )
        isLoading = false
    }
}
