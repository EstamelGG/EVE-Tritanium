import SwiftUI

/// 物品选择器 - 选择有技能依赖的物品
struct ItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var allowedTypeIDs: [Int] = []
    @State private var marketGroupTree: [MarketGroupNode] = []
    @State private var lastVisitedGroupID: Int? = nil
    @State private var lastSearchKeyword: String? = nil
    @State private var hasSelectedItem: Bool = false
    @Environment(\.dismiss) private var dismiss

    let onSelect: (DatabaseListItem) -> Void

    init(databaseManager: DatabaseManager, onSelect: @escaping (DatabaseListItem) -> Void) {
        self.databaseManager = databaseManager
        self.onSelect = onSelect
        let itemData = loadItemData(databaseManager: databaseManager)
        _allowedTypeIDs = State(initialValue: itemData.map { $0.typeId })

        // 初始化市场组目录树 - 从根节点开始（marketGroupID = NULL的顶级节点）
        let builder = MarketItemGroupTreeBuilder(
            databaseManager: databaseManager,
            allowedTypeIDs: Set(itemData.map { $0.typeId }),
            parentGroupId: nil // 从根节点开始，包含所有有技能依赖的物品
        )
        let tree = builder.buildGroupTree()
        _marketGroupTree = State(initialValue: tree)

        // 从 UserDefaults 加载上次访问的组ID
        if let savedGroupID = UserDefaults.standard.object(forKey: "LastVisitedItemGroupID") as? Int {
            Logger.info("从 UserDefaults 加载到之前保存的物品目录ID: \(savedGroupID)")
            _lastVisitedGroupID = State(initialValue: savedGroupID)
        } else {
            Logger.info("未找到保存的物品目录ID")
            _lastVisitedGroupID = State(initialValue: nil)
        }

        // 从 UserDefaults 加载上次搜索关键词
        if let savedKeyword = UserDefaults.standard.string(forKey: "LastItemSearchKeyword") {
            Logger.info("从 UserDefaults 加载到上次搜索关键词: \(savedKeyword)")
            _lastSearchKeyword = State(initialValue: savedKeyword)
        } else {
            Logger.info("未找到保存的搜索关键词")
            _lastSearchKeyword = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
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
                    title: NSLocalizedString("Main_Skills_Plan_Add_Item", comment: ""),
                    marketGroupTree: marketGroupTree,
                    allowTypeIDs: Set(allowedTypeIDs),
                    existingItems: Set(),
                    onItemSelected: { item in
                        // 标记已选择物品
                        hasSelectedItem = true
                        dismiss()
                        onSelect(item)
                    },
                    onItemDeselected: { _ in
                        // 不需要处理取消选择的逻辑
                    },
                    onDismiss: { groupID, searchText in
                        // 处理搜索关键词
                        Logger.info(
                            "onDismiss回调收到：groupID=\(groupID != nil ? String(groupID!) : "nil"), searchText=\(searchText != nil ? "\"\(searchText!)\"" : "nil")"
                        )

                        if let searchText = searchText, !searchText.isEmpty {
                            Logger.info("保存物品搜索关键词到UserDefaults: \"\(searchText)\"")
                            UserDefaults.standard.set(searchText, forKey: "LastItemSearchKeyword")
                            lastSearchKeyword = searchText
                            UserDefaults.standard.synchronize()
                            Logger.info("搜索关键词保存完成")
                        } else if hasSelectedItem || searchText == nil {
                            // 用户选择了物品或明确清空搜索
                            Logger.info(
                                "清空保存的搜索关键词，hasSelectedItem=\(hasSelectedItem), searchText为\(searchText == nil ? "nil" : "空字符串")"
                            )
                            UserDefaults.standard.removeObject(forKey: "LastItemSearchKeyword")
                            lastSearchKeyword = nil
                            UserDefaults.standard.synchronize()
                        }

                        // 如果没有选择物品，清空保存的导航目录ID
                        if !hasSelectedItem {
                            Logger.info("用户未选择物品，清空保存的导航目录ID")
                            UserDefaults.standard.removeObject(forKey: "LastVisitedItemGroupID")
                            lastVisitedGroupID = nil
                            UserDefaults.standard.synchronize()
                        }
                        Logger.info("关闭选择器")
                        dismiss()
                    },
                    lastVisitedGroupID: nil,
                    initialSearchText: nil
                )
                .interactiveDismissDisabled()
                .onAppear {
                    Logger.info(
                        "物品选择器显示，lastSearchKeyword: \(lastSearchKeyword != nil ? "\"\(lastSearchKeyword!)\"" : "nil")"
                    )
                    // 重置选择状态
                    hasSelectedItem = false
                }
                .onDisappear {
                    // 视图消失时检查最后状态
                    Logger.info(
                        "物品选择器消失，hasSelectedItem: \(hasSelectedItem), lastSearchKeyword: \(lastSearchKeyword != nil ? "\"\(lastSearchKeyword!)\"" : "nil")"
                    )
                    // 再次检查UserDefaults中保存的值
                    if let savedKeyword = UserDefaults.standard.string(forKey: "LastItemSearchKeyword") {
                        Logger.info("UserDefaults中保存的搜索关键词: \"\(savedKeyword)\"")
                    } else {
                        Logger.info("UserDefaults中没有保存搜索关键词")
                    }
                }
            }
        }
    }

    /// 加载有技能依赖的物品信息
    private func loadItemData(databaseManager: DatabaseManager) -> [SkillDependentItem] {
        let query = """
            SELECT DISTINCT ta.type_id, t.marketGroupID
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            JOIN types t ON ta.type_id = t.type_id 
            WHERE da.categoryID = 8 
            AND t.published = 1 
            AND t.categoryID != 16
            AND ta.attribute_id != 1927 
            ORDER BY ta.type_id
        """

        var itemInfos: [SkillDependentItem] = []

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int {
                    let marketGroupId = row["marketGroupID"] as? Int
                    itemInfos.append(
                        SkillDependentItem(typeId: typeId, marketGroupId: marketGroupId)
                    )
                }
            }
            Logger.info("加载了 \(itemInfos.count) 个有技能依赖的物品")
        } else {
            Logger.error("加载物品信息失败")
        }

        return itemInfos
    }
}

/// 有技能依赖的物品信息结构体
private struct SkillDependentItem: Identifiable {
    let id: Int
    let typeId: Int
    let marketGroupId: Int?

    init(typeId: Int, marketGroupId: Int?) {
        id = typeId
        self.typeId = typeId
        self.marketGroupId = marketGroupId
    }
}
