import SwiftUI

/// 建筑插件选择器视图
struct FacilityRigSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var allowedTypeIDs: [Int] = []
    @State private var marketGroupTree: [MarketGroupNode] = []
    @Environment(\.dismiss) private var dismiss

    // 建筑ID，用于查询匹配的插件
    let facilityTypeID: Int
    let onRigSelected: ((Int) -> Void)?

    /// 初始化方法
    init(
        databaseManager: DatabaseManager,
        facilityTypeID: Int,
        onRigSelected: ((Int) -> Void)? = nil
    ) {
        self.databaseManager = databaseManager
        self.facilityTypeID = facilityTypeID
        self.onRigSelected = onRigSelected

        let equipmentData = loadEquipmentData(
            databaseManager: databaseManager, facilityTypeID: facilityTypeID
        )
        _allowedTypeIDs = State(initialValue: equipmentData.map { $0.typeId })

        // 初始化市场组目录树
        let builder = MarketItemGroupTreeBuilder(
            databaseManager: databaseManager,
            allowedTypeIDs: Set(equipmentData.map { $0.typeId }),
            parentGroupId: 2203 // 使用建筑改装件(ID: 2203)作为父节点
        )
        let tree = builder.buildGroupTree()
        _marketGroupTree = State(initialValue: tree)
    }

    var body: some View {
        NavigationStack {
            if self.allowedTypeIDs.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString(
                            "Facility_Rig_Selector_No_Compatible_Rigs", comment: "该建筑不支持插件"
                        ),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else {
                MarketItemTreeSelectorView(
                    databaseManager: databaseManager,
                    title: NSLocalizedString("Facility_Rig_Selector_Title", comment: "选择插件"),
                    marketGroupTree: marketGroupTree,
                    allowTypeIDs: Set(allowedTypeIDs),
                    existingItems: Set(),
                    onItemSelected: { item in
                        // 调用回调函数选择插件
                        Logger.info(
                            "用户选择了插件: \(item.name), ID: \(item.id), 建筑ID: \(facilityTypeID)"
                        )
                        onRigSelected?(item.id)
                        dismiss()
                    },
                    onItemDeselected: { _ in
                        // 这里暂时不需要处理
                    },
                    onDismiss: { _, _ in
                        dismiss()
                    },
                    lastVisitedGroupID: nil,
                    initialSearchText: nil
                )
                .interactiveDismissDisabled()
                .onAppear {
                    Logger.info("建筑插件选择器显示，建筑ID: \(facilityTypeID)")
                }
            }
        }
    }

    /// 加载建筑支持的插件装备的type_id及名称信息
    private func loadEquipmentData(databaseManager: DatabaseManager, facilityTypeID: Int)
        -> [EquipmentInfo]
    {
        // 获取effect_id=2663的插件装备信息，并确保是已发布的(published=1)
        // 使用单条SQL语句一次性完成查询
        let query = """
            SELECT DISTINCT te.type_id, t.name, t.en_name, t.marketGroupID
            FROM typeEffects te
            JOIN typeAttributes ta1 ON te.type_id = ta1.type_id
            JOIN types t ON te.type_id = t.type_id
            JOIN (
                SELECT value
                FROM typeAttributes
                WHERE attribute_id = 1547 AND type_id = \(facilityTypeID)
            ) facility ON ta1.value = facility.value
            WHERE te.effect_id = 2663 --- 属于插件槽位
            AND ta1.attribute_id = 1547 -- 插件尺寸
            AND t.published = 1
        """

        var equipmentInfos: [EquipmentInfo] = []

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let enName = row["en_name"] as? String
                {
                    let marketGroupId = row["marketGroupID"] as? Int

                    let info = EquipmentInfo(
                        typeId: typeId,
                        name: name,
                        enName: enName,
                        marketGroupId: marketGroupId
                    )
                    equipmentInfos.append(info)
                }
            }
            Logger.info("加载了 \(equipmentInfos.count) 个建筑支持的插件装备，建筑ID: \(facilityTypeID)")
        } else {
            Logger.error("加载建筑插件装备信息失败")
        }

        return equipmentInfos
    }
}

/// 装备信息结构体
private struct EquipmentInfo: Identifiable {
    let id: Int
    let typeId: Int
    let name: String
    let enName: String
    let marketGroupId: Int?

    init(typeId: Int, name: String, enName: String, marketGroupId: Int?) {
        id = typeId
        self.typeId = typeId
        self.name = name
        self.enName = enName
        self.marketGroupId = marketGroupId
    }
}
