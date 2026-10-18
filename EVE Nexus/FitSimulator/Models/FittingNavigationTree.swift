import Foundation

// MARK: - 预构造导航树（VM 加载时构建：分组、排序一次完成，视图纯渲染）

/// 装配行节点：与装配 ref 关联
struct FittingItemNode: Hashable, Identifiable {
    let ref: FittingRef
    let name: String
    let shipTypeId: Int

    var id: String {
        ref.debugDescription
    }

    static func == (lhs: FittingItemNode, rhs: FittingItemNode) -> Bool {
        lhs.ref == rhs.ref
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ref)
    }
}

/// 飞船节点：骨架为 typeID，携带该飞船全部装配
struct FittingShipNode: Hashable, Identifiable {
    let typeId: Int
    let shipInfo: FittingShipInfo
    let fittings: [FittingItemNode]

    var id: Int {
        typeId
    }

    static func == (lhs: FittingShipNode, rhs: FittingShipNode) -> Bool {
        lhs.typeId == rhs.typeId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(typeId)
    }
}

/// 组节点
struct FittingGroupNode: Hashable, Identifiable {
    let groupID: Int
    let groupName: String
    let firstIconFileName: String? // 组行图标：组内第一个装配的飞船图标
    let fittingCount: Int // 组内装配总数
    let children: [FittingShipNode]

    var id: Int {
        groupID
    }

    static func == (lhs: FittingGroupNode, rhs: FittingGroupNode) -> Bool {
        lhs.groupID == rhs.groupID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(groupID)
    }
}

/// 装配目录条目：本地/在线统一的扁平输入（供 `FittingTreeBuilder.catalog` 构建目录与树）
typealias FittingCatalogEntry = (ref: FittingRef, name: String, shipTypeId: Int)

/// 装配列表用的飞船展示信息（全语种可搜）
struct FittingShipInfo {
    let names: LocalizedText
    let iconFileName: String

    var name: String {
        names.resolved()
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query)
    }
}

/// 导航树构建器：本地/在线 VM 共用
enum FittingTreeBuilder {
    /// 由扁平装配条目构建目录（SDE 查询舰船信息与所属组索引）；SDE 缺失的条目返回到 skipped
    static func catalog(from entries: [FittingCatalogEntry]) -> (
        shipInfo: [Int: FittingShipInfo],
        groupByType: [Int: (groupID: Int, groupName: String)],
        items: [FittingItemNode],
        skipped: [FittingCatalogEntry]
    ) {
        var shipInfo: [Int: FittingShipInfo] = [:]
        var groupByType: [Int: (groupID: Int, groupName: String)] = [:]
        var items: [FittingItemNode] = []
        var skipped: [FittingCatalogEntry] = []

        for entry in entries {
            guard let type = SDEMemoryStore.type(for: entry.shipTypeId),
                  let groupID = type.groupID,
                  let group = SDEMemoryStore.group(for: groupID)
            else {
                skipped.append(entry)
                continue
            }

            if shipInfo[entry.shipTypeId] == nil {
                shipInfo[entry.shipTypeId] = FittingShipInfo(
                    names: type.names,
                    iconFileName: type.iconFilename
                )
                groupByType[entry.shipTypeId] = (groupID, group.name)
            }

            items.append(
                FittingItemNode(ref: entry.ref, name: entry.name, shipTypeId: entry.shipTypeId)
            )
        }

        return (shipInfo, groupByType, items, skipped)
    }

    /// 搜索：匹配飞船本地化名称 / 装配名称 / 飞船 typeID，按飞船名、装配名排序
    static func searchMatches(
        tree: [FittingGroupNode], shipInfo: [Int: FittingShipInfo], query: String
    ) -> [FittingItemNode] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        let all = tree.flatMap(\.children).flatMap(\.fittings)

        return all.filter { fitting in
            guard let info = shipInfo[fitting.shipTypeId] else { return false }
            return info.matches(query)
                || fitting.name.localizedCaseInsensitiveContains(query)
                || String(fitting.shipTypeId).contains(query)
        }
        .sorted { a, b in
            let nameA = shipInfo[a.shipTypeId]?.name ?? ""
            let nameB = shipInfo[b.shipTypeId]?.name ?? ""
            if nameA != nameB {
                return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// 由扁平装配行构建分组树：保留全部飞船节点，装配、飞船和组分别按名称排序
    static func build(
        items: [FittingItemNode],
        shipInfo: [Int: FittingShipInfo],
        groupByType: [Int: (groupID: Int, groupName: String)]
    ) -> [FittingGroupNode] {
        // 按飞船归类并生成子节点
        var groups: [Int: (name: String, children: [FittingShipNode], count: Int)] = [:]

        for (typeId, fittings) in Dictionary(grouping: items, by: \.shipTypeId) {
            guard let info = shipInfo[typeId],
                  let group = groupByType[typeId]
            else { continue }

            let sorted = fittings.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            let child = FittingShipNode(typeId: typeId, shipInfo: info, fittings: sorted)

            groups[group.groupID, default: (group.groupName, [], 0)].children.append(child)
            groups[group.groupID]!.count += sorted.count
        }

        // 组装组节点：子项按显示的飞船名排序
        return groups.map { groupID, value in
            let children = value.children.sorted { a, b in
                a.shipInfo.name
                    .localizedCaseInsensitiveCompare(b.shipInfo.name)
                    == .orderedAscending
            }
            let firstIcon = children.first?.shipInfo.iconFileName

            return FittingGroupNode(
                groupID: groupID,
                groupName: value.name,
                firstIconFileName: firstIcon,
                fittingCount: value.count,
                children: children
            )
        }
        .sorted {
            $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending
        }
    }
}

/// Selection is keyed by full fitting identity and remains independent across ship sections.
struct FittingCatalogSelection {
    var refs: Set<FittingRef> = []

    mutating func toggleAll(in fittings: [FittingItemNode]) {
        let sectionRefs = Set(fittings.map(\.ref))
        if sectionRefs.isSubset(of: refs) {
            refs.subtract(sectionRefs)
        } else {
            refs.formUnion(sectionRefs)
        }
    }

    mutating func retainVisible(_ visibleRefs: Set<FittingRef>) {
        refs.formIntersection(visibleRefs)
    }
}
