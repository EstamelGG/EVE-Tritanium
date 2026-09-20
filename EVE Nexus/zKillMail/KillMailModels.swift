import Foundation

// MARK: - 列表用实体（ESI + ZKB + 补充数据，无 evetools 格式）

/// 星系摘要（用于列表展示，名称从 SDEMemoryStore 动态解析以跟随语言切换）
struct KillMailSystemSummary: Codable {
    let systemId: Int
    let regionId: Int
    let security: Double

    var systemName: String {
        SDEMemoryStore.solarSystemName(for: systemId) ?? "System \(systemId)"
    }

    var regionName: String {
        SDEMemoryStore.regionName(for: regionId) ?? "Region \(regionId)"
    }
}

/// 战斗记录列表项（以 ESI 为核心，补充名称与星系）
struct KillMailListEntity: Codable, Identifiable {
    let killmailId: Int
    let timestamp: Int
    let zkb: ZKBInfo
    let victim: ESIVictim
    let names: [Int: String] // ID -> 名称（角色/军团/联盟）
    let system: KillMailSystemSummary?

    var id: Int {
        killmailId
    }

    var totalValue: Double {
        zkb.totalValueValue
    }

    /// 显示用主名称（角色 > 联盟 > 军团）
    var displayName: String {
        if let charId = victim.character_id, let name = names[charId] {
            return name
        }
        if let allyId = victim.alliance_id, allyId > 0, let name = names[allyId] {
            return name
        }
        if let name = names[victim.corporation_id] {
            return name
        }
        return NSLocalizedString("Unknown", comment: "")
    }

    var characterId: Int? {
        victim.character_id
    }

    var corporationId: Int {
        victim.corporation_id
    }

    var allianceId: Int? {
        victim.alliance_id
    }

    var shipTypeId: Int {
        victim.ship_type_id
    }
}

// MARK: - 详情用数据（ESI + ZKB + 补充数据）

/// 战斗记录详情（以 ESI 为核心，补充名称、星系等；列表单价由详情视图异步拉取）
struct KillMailDetailData {
    let killmailId: Int
    let esi: ESIKillMail
    let zkb: ZKBInfo?
    let names: [Int: String]
    let system: KillMailSystemSummary?

    var timestamp: Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: esi.killmail_time) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    var attackers: [ESIAttacker] {
        esi.attackers ?? []
    }

    func characterName(for id: Int) -> String {
        names[id] ?? "Character \(id)"
    }

    func corporationName(for id: Int) -> String {
        names[id] ?? "Corporation \(id)"
    }

    func allianceName(for id: Int) -> String {
        names[id] ?? "Alliance \(id)"
    }

    /// 用于装配视图的物品格式
    ///
    /// 装配槽位（11-34）顶层装备行：`[flag, type_id, qty_dropped, qty_destroyed, singleton, depth, charge_type_id, charge_quantity]`
    /// 其他行：`[flag, type_id, qty_dropped, qty_destroyed, singleton, depth]`
    var itemsForFitting: [[Int]] {
        guard let items = esi.victim.items else { return [] }
        return KillMailItemTreeBuilder.flattenFittingWithCharges(items)
    }

    /// 转换植入体后的装配物品（供 BRKillMailFittingView 使用）
    var convertedItemsForFitting: [[Int]] {
        BRKillMailUtils.shared.convertImplantsToFitting(
            shipId: esi.victim.ship_type_id,
            items: itemsForFitting
        )
    }

    /// 指定舱位（flag）下的展示行（含容器嵌套，深度优先；同级排序由调用方传入单价表）
    func displayRows(forFlag flag: Int, unitPriceByType: [Int: Double]) -> [KillMailDisplayRow] {
        let roots = (esi.victim.items ?? []).filter { $0.flag == flag }
        return KillMailItemTreeBuilder.displayRows(
            roots: roots,
            groupingFlag: flag,
            unitPriceByType: unitPriceByType
        )
    }

    /// 收集 victim.items 树中全部 type_id（含嵌套）
    static func allVictimItemTypeIds(from items: [ESIItem]?) -> [Int] {
        guard let items else { return [] }
        var ids = Set<Int>()
        func walk(_ list: [ESIItem]) {
            for item in list {
                ids.insert(item.item_type_id)
                if let nested = item.items {
                    walk(nested)
                }
            }
        }
        walk(items)
        return Array(ids)
    }

    /// 将 km 装配数据转为 LocalFitting（直接按 flag 映射）
    /// - Returns: 转换后的 LocalFitting，失败返回 nil
    func toLocalFitting() -> LocalFitting? {
        guard let items = esi.victim.items, !items.isEmpty else { return nil }

        // flag → FittingFlag 映射表
        let loSlotFlags: [FittingFlag] = [.loSlot0, .loSlot1, .loSlot2, .loSlot3, .loSlot4, .loSlot5, .loSlot6, .loSlot7]
        let medSlotFlags: [FittingFlag] = [.medSlot0, .medSlot1, .medSlot2, .medSlot3, .medSlot4, .medSlot5, .medSlot6, .medSlot7]
        let hiSlotFlags: [FittingFlag] = [.hiSlot0, .hiSlot1, .hiSlot2, .hiSlot3, .hiSlot4, .hiSlot5, .hiSlot6, .hiSlot7]
        let rigSlotFlags: [FittingFlag] = [.rigSlot0, .rigSlot1, .rigSlot2]
        let subSystemFlags: [FittingFlag] = [.subSystemSlot0, .subSystemSlot1, .subSystemSlot2, .subSystemSlot3]

        // 按 flag 分组：每个 flag 上的物品列表（含 categoryID，来自 SDEMemoryStore 内存缓存）
        var flagGroups: [Int: [(typeId: Int, qty: Int, isCharge: Bool)]] = [:]
        for item in items {
            let qty = (item.quantity_dropped ?? 0) + (item.quantity_destroyed ?? 0)
            guard qty > 0 else { continue }
            let isCharge = SDEMemoryStore.type(for: item.item_type_id)?.categoryID == 8
            flagGroups[item.flag, default: []].append((item.item_type_id, qty, isCharge))
        }

        var fittingItems: [LocalFittingItem] = []
        var drones: [Drone] = []
        var cargo: [CargoItem] = []
        var implants: [Int] = []

        for flag in flagGroups.keys.sorted() {
            let groupItems = flagGroups[flag]!

            switch flag {
            case 11 ... 18: // LoSlot0-7
                let (module, charge) = extractModuleAndCharge(from: groupItems)
                if let module = module, flag - 11 < loSlotFlags.count {
                    fittingItems.append(LocalFittingItem(flag: loSlotFlags[flag - 11], quantity: 1, type_id: module.typeId, charge_type_id: charge?.typeId, charge_quantity: charge?.qty))
                }
            case 19 ... 26: // MedSlot0-7
                let (module, charge) = extractModuleAndCharge(from: groupItems)
                if let module = module, flag - 19 < medSlotFlags.count {
                    fittingItems.append(LocalFittingItem(flag: medSlotFlags[flag - 19], quantity: 1, type_id: module.typeId, charge_type_id: charge?.typeId, charge_quantity: charge?.qty))
                }
            case 27 ... 34: // HiSlot0-7
                let (module, charge) = extractModuleAndCharge(from: groupItems)
                if let module = module, flag - 27 < hiSlotFlags.count {
                    fittingItems.append(LocalFittingItem(flag: hiSlotFlags[flag - 27], quantity: 1, type_id: module.typeId, charge_type_id: charge?.typeId, charge_quantity: charge?.qty))
                }
            case 92 ... 94: // RigSlot0-2
                let (module, _) = extractModuleAndCharge(from: groupItems)
                if let module = module, flag - 92 < rigSlotFlags.count {
                    fittingItems.append(LocalFittingItem(flag: rigSlotFlags[flag - 92], quantity: 1, type_id: module.typeId))
                }
            case 125 ... 128: // SubSystemSlot0-3
                let (module, _) = extractModuleAndCharge(from: groupItems)
                if let module = module, flag - 125 < subSystemFlags.count {
                    fittingItems.append(LocalFittingItem(flag: subSystemFlags[flag - 125], quantity: 1, type_id: module.typeId))
                }
            case 87: // DroneBay
                for item in groupItems where !item.isCharge {
                    drones.append(Drone(type_id: item.typeId, quantity: item.qty, active_count: 0, muta: nil))
                }
            case 89: // Implant
                for item in groupItems where !item.isCharge {
                    implants.append(item.typeId)
                }
            case 5: // Cargo
                for item in groupItems {
                    cargo.append(CargoItem(type_id: item.typeId, quantity: item.qty))
                }
            case 158 ... 163: // FighterBay(158) / FighterTube0-4(159-163)
                for item in groupItems where !item.isCharge {
                    cargo.append(CargoItem(type_id: item.typeId, quantity: item.qty))
                }
            default:
                // 其他 flag 的物品丢弃
                break
            }
        }

        guard !fittingItems.isEmpty || !drones.isEmpty || !cargo.isEmpty || !implants.isEmpty else {
            return nil
        }

        return LocalFitting(
            description: "",
            fitting_id: UUID(),
            items: fittingItems,
            name: NSLocalizedString("KillMail_Simulate_Fitting", comment: ""),
            ship_type_id: esi.victim.ship_type_id,
            drones: drones.isEmpty ? nil : drones,
            fighters: nil,
            cargo: cargo.isEmpty ? nil : cargo,
            implants: implants.isEmpty ? nil : implants,
            environment_type_id: nil
        )
    }

    /// 从同 flag 的物品列表中提取装备和弹药
    /// - Parameter groupItems: 同一个 flag 上的物品列表
    /// - Returns: (装备, 弹药)，均可能为 nil
    private func extractModuleAndCharge(
        from groupItems: [(typeId: Int, qty: Int, isCharge: Bool)]
    ) -> (module: (typeId: Int, qty: Int)?, charge: (typeId: Int, qty: Int)?) {
        var module: (typeId: Int, qty: Int)?
        var charge: (typeId: Int, qty: Int)?
        for item in groupItems {
            if item.isCharge {
                if charge == nil {
                    charge = (item.typeId, item.qty)
                }
            } else {
                if module == nil {
                    module = (item.typeId, item.qty)
                }
            }
        }
        return (module, charge)
    }
}

// MARK: - 嵌套物品展平与同级排序

/// 详情列表中的一行物品（含嵌套深度）
struct KillMailDisplayRow: Identifiable, Hashable {
    let id: String
    let flag: Int
    let typeId: Int
    let quantityDropped: Int
    let quantityDestroyed: Int
    let singleton: Int
    let depth: Int
}

enum KillMailItemTreeBuilder {
    private static let depthIndex = 5

    /// 展平 victim 物品树，装配槽位的弹药合并到对应装备行的 charge 字段
    ///
    /// 输出格式：
    /// - 装配槽位（11-34）顶层装备行：`[flag, type_id, qty_dropped, qty_destroyed, singleton, depth, charge_type_id, charge_quantity]`
    /// - 其他行：`[flag, type_id, qty_dropped, qty_destroyed, singleton, depth]`
    /// - 装配槽位弹药不作为独立行输出（合并为装备的 charge 字段）
    /// - 与装配环（BRKillMailFittingView）一致：同 flag 下取首个弹药（categoryID == 8）
    static func flattenFittingWithCharges(_ roots: [ESIItem]) -> [[Int]] {
        let fittingSlotFlags: Set<Int> = Set(11 ... 34)
        var rows: [[Int]] = []
        func flattenNested(_ items: [ESIItem], groupingFlag: Int, depth: Int) {
            for item in sortESISiblings(items, unitPriceByType: [:]) {
                rows.append([
                    groupingFlag,
                    item.item_type_id,
                    item.quantity_dropped ?? 0,
                    item.quantity_destroyed ?? 0,
                    item.singleton,
                    depth,
                ])
                if let nested = item.items, !nested.isEmpty {
                    flattenNested(nested, groupingFlag: groupingFlag, depth: depth + 1)
                }
            }
        }

        for flag in Set(roots.map(\.flag)).sorted() {
            let siblings = roots.filter { $0.flag == flag }

            guard fittingSlotFlags.contains(flag) else {
                flattenNested(siblings, groupingFlag: flag, depth: 0)
                continue
            }

            // 装配槽位：第一个非弹药=装备，第一个弹药=charge
            let sorted = sortESISiblings(siblings, unitPriceByType: [:])
            guard let module = sorted.first(where: { SDEMemoryStore.type(for: $0.item_type_id)?.categoryID != 8 }) else {
                continue
            }
            let charge = sorted.first(where: { SDEMemoryStore.type(for: $0.item_type_id)?.categoryID == 8 })
                .map { (typeId: $0.item_type_id, quantity: ($0.quantity_dropped ?? 0) + ($0.quantity_destroyed ?? 0)) }

            rows.append([
                flag,
                module.item_type_id,
                module.quantity_dropped ?? 0,
                module.quantity_destroyed ?? 0,
                module.singleton,
                0,
                charge?.typeId ?? 0,
                charge?.quantity ?? 0,
            ])
        }
        return rows
    }

    /// 某一 flag 舱位内的展示行（容器下紧跟内容物，仅同级排序）
    static func displayRows(
        roots: [ESIItem],
        groupingFlag: Int,
        unitPriceByType: [Int: Double]
    ) -> [KillMailDisplayRow] {
        var result: [KillMailDisplayRow] = []
        var counter = 0

        func walk(_ items: [ESIItem], depth: Int) {
            let sorted = sortESISiblings(items, unitPriceByType: unitPriceByType)
            for item in sorted {
                let rowId = "\(groupingFlag)-\(item.item_type_id)-\(depth)-\(counter)"
                counter += 1
                result.append(
                    KillMailDisplayRow(
                        id: rowId,
                        flag: groupingFlag,
                        typeId: item.item_type_id,
                        quantityDropped: item.quantity_dropped ?? 0,
                        quantityDestroyed: item.quantity_destroyed ?? 0,
                        singleton: item.singleton,
                        depth: depth
                    )
                )
                if let nested = item.items, !nested.isEmpty {
                    walk(nested, depth: depth + 1)
                }
            }
        }

        walk(roots, depth: 0)
        return result
    }

    /// 仅对同一父级下的兄弟节点排序（装配槽：先 flag，再非弹药优先）
    static func sortFittingSiblingRows(
        _ rows: [[Int]],
        itemInfoCache: [Int: (iconFileName: String, bpcIconFileName: String, categoryID: Int)]
    ) -> [[Int]] {
        rows.sorted { a, b in
            if a[0] != b[0] {
                return a[0] < b[0]
            }
            let aDepth = a.count > depthIndex ? a[depthIndex] : 0
            let bDepth = b.count > depthIndex ? b[depthIndex] : 0
            if aDepth != bDepth {
                return aDepth < bDepth
            }
            let aAmmo = itemInfoCache[a[1]]?.categoryID == 8
            let bAmmo = itemInfoCache[b[1]]?.categoryID == 8
            if aAmmo != bAmmo {
                return !aAmmo
            }
            return a[1] < b[1]
        }
    }

    private static func sortESISiblings(
        _ items: [ESIItem],
        unitPriceByType: [Int: Double]
    ) -> [ESIItem] {
        guard !items.isEmpty else { return items }
        let valueByType: [Int: Double] = Dictionary(grouping: items, by: \.item_type_id)
            .mapValues { group in
                group.reduce(0.0) { partial, item in
                    let qty = (item.quantity_dropped ?? 0) + (item.quantity_destroyed ?? 0)
                    let unit = unitPriceByType[item.item_type_id] ?? 0
                    return partial + Double(qty) * unit
                }
            }
        return items.sorted { lhs, rhs in
            let lhsStack = valueByType[lhs.item_type_id, default: 0]
            let rhsStack = valueByType[rhs.item_type_id, default: 0]
            if lhsStack != rhsStack {
                return lhsStack > rhsStack
            }
            if lhs.item_type_id != rhs.item_type_id {
                return lhs.item_type_id < rhs.item_type_id
            }
            let ld = lhs.quantity_dropped ?? 0
            let rd = rhs.quantity_dropped ?? 0
            if ld != rd {
                return ld > rd
            }
            return (lhs.quantity_destroyed ?? 0) > (rhs.quantity_destroyed ?? 0)
        }
    }
}
