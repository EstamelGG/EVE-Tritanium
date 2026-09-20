import Foundation
import SwiftUI

extension DatabaseManager {
    func loadCategories() -> ([Category], [Category]) {
        var published: [Category] = []
        var unpublished: [Category] = []
        for category in SDEMemoryStore.categories.values.sorted(by: { $0.id < $1.id }) {
            let item = Category(
                id: category.id,
                name: category.name,
                enName: category.enName,
                published: category.published,
                iconID: category.id,
                iconFileNew: category.iconFilename
            )
            if category.published {
                published.append(item)
            } else {
                unpublished.append(item)
            }
        }
        return (published, unpublished)
    }

    /// 加载组
    func loadGroups(for categoryID: Int) -> ([TypeGroup], [TypeGroup]) {
        var published: [TypeGroup] = []
        var unpublished: [TypeGroup] = []
        for group in SDEMemoryStore.groups(inCategory: categoryID) {
            let item = TypeGroup(
                id: group.id,
                name: group.name,
                enName: group.enName,
                iconID: group.id,
                categoryID: group.categoryID,
                published: group.published,
                icon_filename: group.iconFilename
            )
            if group.published {
                published.append(item)
            } else {
                unpublished.append(item)
            }
        }
        return (published, unpublished)
    }

    /// 加载物品（按 metaGroupID、名称排序）
    func loadItems(for groupID: Int, groupName: String) -> ([DatabaseListItem], [Int: String]) {
        let metaGroupNames = SDEMemoryStore.localizedMetaGroupNames

        let query = """
            SELECT t.type_id, t.name, t.en_name, t.icon_filename, t.published, t.metaGroupID, t.categoryID,
                   t.pg_need, t.cpu_need, t.rig_cost, 
                   t.em_damage, t.them_damage, t.kin_damage, t.exp_damage,
                   t.high_slot, t.mid_slot, t.low_slot, t.rig_slot, t.gun_slot, t.miss_slot
            FROM types t
            WHERE t.groupID = ?
            ORDER BY t.name ASC
        """

        let result = executeQuery(query, parameters: [groupID])

        var items: [DatabaseListItem] = []

        switch result {
        case let .success(rows):
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let name = row["name"] as? String,
                      let enName = row["en_name"] as? String,
                      let metaGroupId = row["metaGroupID"] as? Int,
                      let categoryId = row["categoryID"] as? Int,
                      let isPublished = row["published"] as? Int
                else {
                    Logger.warning("物品基础数据不完整: \(row)")
                    continue
                }

                let iconFilename = (row["icon_filename"] as? String) ?? ""

                items.append(
                    DatabaseListItem(
                        id: typeId,
                        name: name,
                        enName: enName,
                        iconFileName: iconFilename.isEmpty
                            ? IconManager.defaultItemIcon : iconFilename,
                        published: isPublished != 0,
                        categoryID: categoryId,
                        groupID: groupID,
                        groupName: groupName,
                        pgNeed: row["pg_need"] as? Double,
                        cpuNeed: row["cpu_need"] as? Double,
                        rigCost: row["rig_cost"] as? Int,
                        emDamage: row["em_damage"] as? Double
                            ?? (row["em_damage"] as? Int).map { Double($0) },
                        themDamage: row["them_damage"] as? Double
                            ?? (row["them_damage"] as? Int).map { Double($0) },
                        kinDamage: row["kin_damage"] as? Double
                            ?? (row["kin_damage"] as? Int).map { Double($0) },
                        expDamage: row["exp_damage"] as? Double
                            ?? (row["exp_damage"] as? Int).map { Double($0) },
                        highSlot: row["high_slot"] as? Int,
                        midSlot: row["mid_slot"] as? Int,
                        lowSlot: row["low_slot"] as? Int,
                        rigSlot: row["rig_slot"] as? Int,
                        gunSlot: row["gun_slot"] as? Int,
                        missSlot: row["miss_slot"] as? Int,
                        metaGroupID: metaGroupId,
                        navigationDestination: ItemInfoMap.getItemInfoView(
                            itemID: typeId,
                            databaseManager: self
                        )
                    )
                )
            }

        case let .error(error):
            Logger.error("加载物品失败: \(error)")
        }

        // 按 metaGroupID、名称排序
        items.sort {
            if $0.metaGroupID != $1.metaGroupID {
                return ($0.metaGroupID ?? -1) < ($1.metaGroupID ?? -1)
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return (items, metaGroupNames)
    }

    /// 加载 MetaGroup 名称
    func loadMetaGroupNames(for metaGroupIDs: [Int]) -> [Int: String] {
        if metaGroupIDs.isEmpty {
            return [:]
        }
        var names: [Int: String] = [:]
        for id in metaGroupIDs {
            if let name = SDEMemoryStore.metaGroupName(for: id) {
                names[id] = name
            }
        }
        return names
    }

    func getCategoryID(for typeID: Int) -> Int? {
        SDEMemoryStore.type(for: typeID)?.categoryID
    }

    /// 获取物品详情（描述文本来自 texts.zip / ItemTextStore）
    func getItemDetails(for typeID: Int) -> ItemDetails? {
        // 从 SDEMemoryStore 内存索引获取，避免每次打开物品详情都执行一次重 SQL
        guard let info = SDEMemoryStore.type(for: typeID) else { return nil }
        let groupName = info.groupID.flatMap { SDEMemoryStore.group(for: $0)?.name } ?? ""
        let categoryName = SDEMemoryStore.category(for: info.categoryID)?.name ?? ""
        let description = ItemTextStore.shared.text(for: info.descID)

        return ItemDetails(
            name: info.name,
            en_name: info.enName,
            description: description,
            iconFileName: info.iconFilename,
            groupName: groupName,
            categoryID: info.categoryID,
            categoryName: categoryName,
            roleBonuses: nil,
            typeBonuses: nil,
            typeId: typeID,
            groupID: info.groupID,
            volume: info.volume,
            repackagedVolume: info.repackagedVolume,
            capacity: info.capacity,
            mass: info.mass,
            marketGroupID: info.marketGroupID
        )
    }

    func loadGroupNames(for groupIDs: [Int]) -> [Int: String] {
        var groupNames: [Int: String] = [:]
        for id in groupIDs {
            if let name = SDEMemoryStore.group(for: id)?.name {
                groupNames[id] = name
            }
        }
        return groupNames
    }

    func getItemIconFileName(for typeID: Int) -> String? {
        ItemInfoMap.iconFilename(for: typeID)
    }

    /// 内存搜索：对 SDEMemoryStore 全量 types 应用调用方过滤闭包（迁移自 loadMarketItems 的搜索路径）。
    /// 排序与旧 SQL 一致：精确匹配（任意语种全等）优先，其后按 metaGroupID 升序（nil 最前）。
    func searchItemsMemory(
        filter: (Int, SDEMemoryStore.TypeInfo) -> Bool,
        eligibleMarketGroupIDs: Set<Int>? = nil,
        exactMatchText: String? = nil
    ) -> [DatabaseListItem] {
        var matches: [(item: DatabaseListItem, exact: Bool)] = []
        for (typeID, info) in SDEMemoryStore.types where filter(typeID, info) {
            guard let item = DatabaseListItem(
                typeID: typeID, databaseManager: self, eligibleMarketGroupIDs: eligibleMarketGroupIDs
            ) else { continue }
            let exact = exactMatchText.map { info.names.matchesExact($0) } ?? false
            matches.append((item, exact))
        }
        return matches.sorted { a, b in
            if a.exact != b.exact {
                return a.exact
            }
            let metaA = a.item.metaGroupID ?? -1
            let metaB = b.item.metaGroupID ?? -1
            if metaA != metaB {
                return metaA < metaB
            }
            return a.item.id < b.item.id
        }
        .map(\.item)
    }
}
