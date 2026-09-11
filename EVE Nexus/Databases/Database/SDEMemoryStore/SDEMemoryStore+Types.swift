import Foundation
import SQLite3

/// types / categories / groups / metaGroups / marketGroups 加载与查询
extension SDEMemoryStore {
    /// types 全量加载（5.3 万行 × 35 列，启动最大热点）。
    /// 直读 + 按名解析列索引：绕过行字典与 Any 装箱，取值与 SELECT 列顺序解耦。
    static func loadTypes(_ db: DatabaseManager) {
        let query = """
            SELECT type_id, categoryID, groupID, metaGroupID, marketGroupID, published,
                   icon_filename, bpc_icon_filename, volume, capacity, mass,
                   repackaged_volume, desc_id, variationParentTypeID,
                   pg_need, cpu_need, rig_cost,
                   em_damage, them_damage, kin_damage, exp_damage,
                   high_slot, mid_slot, low_slot, rig_slot, gun_slot, miss_slot,
                   \(nameColumns)
            FROM types
        """

        var cache: [Int: TypeInfo] = [:]
        cache.reserveCapacity(65536)

        db.executeQueryMapped(query, context: "types") { resolve in
            let iID = resolve.index("type_id")
            let iCategory = resolve.index("categoryID")
            let iGroup = resolve.index("groupID")
            let iMeta = resolve.index("metaGroupID")
            let iMarket = resolve.index("marketGroupID")
            let iPublished = resolve.index("published")
            let iIcon = resolve.index("icon_filename")
            let iBPC = resolve.index("bpc_icon_filename")
            let (iVolume, iCapacity, iMass) = (
                resolve.index("volume"), resolve.index("capacity"), resolve.index("mass")
            )
            let iRepackaged = resolve.index("repackaged_volume")
            let iDesc = resolve.index("desc_id")
            let iParent = resolve.index("variationParentTypeID")
            let (iPG, iCPU, iRigCost) = (
                resolve.index("pg_need"), resolve.index("cpu_need"), resolve.index("rig_cost")
            )
            let (iEM, iThem, iKin, iExp) = (
                resolve.index("em_damage"), resolve.index("them_damage"),
                resolve.index("kin_damage"), resolve.index("exp_damage")
            )
            let (iHigh, iMid, iLow, iRig, iGun, iMiss) = (
                resolve.index("high_slot"), resolve.index("mid_slot"), resolve.index("low_slot"),
                resolve.index("rig_slot"), resolve.index("gun_slot"), resolve.index("miss_slot")
            )
            let iNames = localizedIndexes(resolve)

            return { stmt in
                guard sqlite3_column_type(stmt, iID) != SQLITE_NULL,
                      sqlite3_column_type(stmt, iCategory) != SQLITE_NULL
                else { return }
                let typeID = Int(sqlite3_column_int64(stmt, iID))

                let rawIcon = directText(stmt, iIcon)
                let rawBpc = directText(stmt, iBPC)
                let rawDesc = directText(stmt, iDesc)

                cache[typeID] = TypeInfo(
                    categoryID: Int(sqlite3_column_int64(stmt, iCategory)),
                    groupID: directIntOrNil(stmt, iGroup),
                    metaGroupID: directIntOrNil(stmt, iMeta),
                    marketGroupID: directIntOrNil(stmt, iMarket),
                    published: sqlite3_column_int64(stmt, iPublished) == 1,
                    names: localizedText(stmt, iNames),
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultItemIcon : rawIcon,
                    bpcIconFilename: rawBpc.isEmpty ? nil : rawBpc,
                    volume: directDoubleOrNil(stmt, iVolume) ?? 0,
                    capacity: directDoubleOrNil(stmt, iCapacity) ?? 0,
                    mass: directDoubleOrNil(stmt, iMass) ?? 0,
                    repackagedVolume: directDoubleOrNil(stmt, iRepackaged),
                    descID: rawDesc.isEmpty ? nil : rawDesc,
                    variationParentTypeID: directIntOrNil(stmt, iParent),
                    pgNeed: directDoubleOrNil(stmt, iPG),
                    cpuNeed: directDoubleOrNil(stmt, iCPU),
                    rigCost: directIntOrNil(stmt, iRigCost),
                    emDamage: directDoubleOrNil(stmt, iEM),
                    themDamage: directDoubleOrNil(stmt, iThem),
                    kinDamage: directDoubleOrNil(stmt, iKin),
                    expDamage: directDoubleOrNil(stmt, iExp),
                    highSlot: directIntOrNil(stmt, iHigh),
                    midSlot: directIntOrNil(stmt, iMid),
                    lowSlot: directIntOrNil(stmt, iLow),
                    rigSlot: directIntOrNil(stmt, iRig),
                    gunSlot: directIntOrNil(stmt, iGun),
                    missSlot: directIntOrNil(stmt, iMiss)
                )
            }
        }
        types = cache

        // 构建变体反向索引：parentTypeID → [子 typeID]
        var reverse: [Int: [Int]] = [:]
        reverse.reserveCapacity(cache.count / 4)
        for (typeID, info) in cache {
            if let parentID = info.variationParentTypeID {
                reverse[parentID, default: []].append(typeID)
            }
        }
        variationsByParent = reverse
    }

    static func loadCategories(_ db: DatabaseManager) {
        let query = """
            SELECT category_id, published, icon_filename, \(nameColumns)
            FROM categories
        """
        var cache: [Int: CategoryInfo] = [:]
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let id = row["category_id"] as? Int else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                cache[id] = CategoryInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    published: (row["published"] as? Int ?? 0) != 0,
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultIcon : rawIcon
                )
            }
        }
        categories = cache
    }

    static func loadGroups(_ db: DatabaseManager) {
        let query = """
            SELECT group_id, categoryID, published, icon_filename, \(nameColumns)
            FROM groups
        """
        var cache: [Int: GroupInfo] = [:]
        var byCategory: [Int: [GroupInfo]] = [:]
        db.executeQueryMapped(query, context: "groups") { resolve in
            let (iID, iCategory, iPublished, iIcon) = (
                resolve.index("group_id"), resolve.index("categoryID"),
                resolve.index("published"), resolve.index("icon_filename")
            )
            let iNames = localizedIndexes(resolve)
            return { stmt in
                guard let id = directIntOrNil(stmt, iID),
                      let categoryID = directIntOrNil(stmt, iCategory)
                else { return }
                let rawIcon = directText(stmt, iIcon)
                let info = GroupInfo(
                    id: id,
                    names: localizedText(stmt, iNames),
                    categoryID: categoryID,
                    published: (directIntOrNil(stmt, iPublished) ?? 0) != 0,
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultIcon : rawIcon
                )
                cache[id] = info
                byCategory[categoryID, default: []].append(info)
            }
        }
        for key in byCategory.keys {
            byCategory[key]?.sort { $0.id < $1.id }
        }
        groups = cache
        groupsByCategory = byCategory
    }

    static func loadMetaGroups(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "metaGroups", idColumn: "metagroup_id", into: &metaGroupNames)
    }

    static func loadMarketGroups(_ db: DatabaseManager) {
        let query = """
            SELECT group_id, icon_name, parentgroup_id, show, \(nameColumns)
            FROM marketGroups
        """
        var cache: [Int: MarketGroupInfo] = [:]
        db.executeQueryMapped(query, context: "marketGroups") { resolve in
            let (iID, iIcon, iParent) = (
                resolve.index("group_id"), resolve.index("icon_name"), resolve.index("parentgroup_id")
            )
            let (iShow, iNames) = (resolve.index("show"), localizedIndexes(resolve))
            return { stmt in
                guard let id = directIntOrNil(stmt, iID) else { return }
                // show 为 NULL 时默认 1（与原物化版语义一致）
                let show = sqlite3_column_type(stmt, iShow) == SQLITE_NULL
                    ? 1 : Int(sqlite3_column_int64(stmt, iShow))
                cache[id] = MarketGroupInfo(
                    id: id,
                    names: localizedText(stmt, iNames),
                    iconName: directText(stmt, iIcon),
                    parentGroupID: directIntOrNil(stmt, iParent),
                    show: show != 0
                )
            }
        }
        marketGroups = cache
    }

    /// 预计算可模拟装配的飞船 typeID 集合：market group 4「Ships」子树（仅 show=true）下的物品
    static func loadSimulatableShips(_: DatabaseManager) {
        let shipMarketGroupIDs = marketSubgroupIDs(rootID: 4)
        simulatableShipTypeIDs = Set(
            types.compactMap { typeID, info in
                guard let marketGroupID = info.marketGroupID,
                      shipMarketGroupIDs.contains(marketGroupID)
                else { return nil }
                return typeID
            }
        )
    }

    /// 递归收集根分组及其全部子孙分组 ID（仅 show=true）
    private static func marketSubgroupIDs(rootID: Int) -> Set<Int> {
        var result: Set<Int> = [rootID]
        for group in marketGroups.values where group.show && group.parentGroupID == rootID {
            result.formUnion(marketSubgroupIDs(rootID: group.id))
        }
        return result
    }

    // MARK: - Lookups

    static func type(for typeID: Int) -> TypeInfo? {
        types[typeID]
    }

    /// 判断 typeID 是否为可模拟装配的飞船（market group 4 子树）
    static func isSimulatableShip(_ typeID: Int) -> Bool {
        simulatableShipTypeIDs.contains(typeID)
    }

    /// 解析变体树顶层父物品 ID（无父物品时返回自身）
    static func resolveVariationParent(for typeID: Int) -> Int {
        var currentID = typeID
        var seen = Set<Int>() // 防御循环引用
        while let info = type(for: currentID),
              let parentID = info.variationParentTypeID,
              !seen.contains(currentID)
        {
            seen.insert(currentID)
            currentID = parentID
        }
        return currentID
    }

    /// 变体数量（含自身），O(1) 字典查找
    static func variationsCount(for typeID: Int) -> Int {
        let parentID = resolveVariationParent(for: typeID)
        let childCount = variationsByParent[parentID]?.count ?? 0
        return childCount + 1
    }

    static func category(for id: Int) -> CategoryInfo? {
        categories[id]
    }

    static func group(for id: Int) -> GroupInfo? {
        groups[id]
    }

    static func groups(inCategory categoryID: Int) -> [GroupInfo] {
        groupsByCategory[categoryID] ?? []
    }

    static func metaGroupName(for id: Int) -> String? {
        metaGroupNames[id]?.resolvedNonEmpty()
    }

    /// Catalog 等需要完整 meta 名字典时按当前语言物化
    static var localizedMetaGroupNames: [Int: String] {
        Dictionary(uniqueKeysWithValues: metaGroupNames.compactMap { id, text in
            let name = text.resolved()
            return name.isEmpty ? nil : (id, name)
        })
    }

    /// 按衍生等级（metaGroup）分组并命名：0 = 基础物品，其余取本地化 meta 名（缺省回退 "MetaGroup N"）
    /// 数据浏览叶子页与专精飞船列表共用
    static func metaGroupSections<T>(
        _ items: [T], metaGroupID: (T) -> Int
    ) -> [(id: Int, name: String, items: [T])] {
        var grouped: [Int: [T]] = [:]
        for item in items {
            grouped[metaGroupID(item), default: []].append(item)
        }
        let names = localizedMetaGroupNames
        return grouped.sorted { $0.key < $1.key }.map { metaGroupID, groupItems in
            let name: String
            if metaGroupID == 0 {
                name = NSLocalizedString("Main_Database_base", comment: "基础物品")
            } else if let metaName = names[metaGroupID] {
                name = metaName
            } else {
                name = "MetaGroup \(metaGroupID)"
            }
            return (id: metaGroupID, name: name, items: groupItems)
        }
    }

    static func marketGroup(for id: Int) -> MarketGroupInfo? {
        marketGroups[id]
    }
}
