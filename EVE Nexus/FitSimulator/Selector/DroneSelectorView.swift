import SwiftUI

/// 无人机选择器
struct DroneSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager

    let onSelect: (DatabaseListItem) -> Void

    var body: some View {
        SlotEquipmentSelectorView(
            databaseManager: databaseManager,
            config: SlotEquipmentSelectorConfig(
                title: NSLocalizedString("Fitting_Select_Drone", comment: "选择无人机"),
                parentGroupId: 157, // 使用无人机(ID: 157)作为父节点
                groupIDKey: "LastVisitedDroneGroupID",
                searchKey: "LastDroneSearchKeyword",
                logTag: "无人机",
                loadAllowedTypeIDs: { databaseManager in
                    // 获取无人机(categoryID=18)的信息，并确保是已发布的(published=1)
                    SlotEquipmentSelectorQueries.loadTypeIDs(
                        databaseManager: databaseManager,
                        query: """
                            SELECT type_id, name, en_name, marketGroupID
                            FROM types
                            WHERE categoryID = 18
                            AND published = 1
                        """,
                        logTag: "无人机"
                    )
                },
                onItemSelected: onSelect,
                clearsSavedKeywordWhenDismissedWithoutSearch: true
            )
        )
        .environment(\.showDroneBaseDamage, true)
    }
}
