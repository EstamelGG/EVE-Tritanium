import Foundation

struct MarketGroup: Identifiable, Hashable {
    let id: Int // group_id
    let name: String // 目录名称
    let iconName: String // 图标文件名
    let parentGroupID: Int? // 父目录ID

    /// 实现Hashable协议
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// 实现Equatable协议(Hashable继承自Equatable)
    static func == (lhs: MarketGroup, rhs: MarketGroup) -> Bool {
        return lhs.id == rhs.id
    }
}

/// 市场目录树索引：扁平数组上构建父→子字典索引，使子节点查找与叶子判断从 O(n) 降为 O(1)。
final class MarketTree {
    private let childrenIndex: [Int: [MarketGroup]]
    private let groupByID: [Int: MarketGroup]
    /// 原始扁平数组（按 SDE 顺序），用于按 ID 集合过滤时保持稳定顺序
    let flat: [MarketGroup]
    let roots: [MarketGroup]

    init(_ flat: [MarketGroup]) {
        self.flat = flat
        var idx: [Int: [MarketGroup]] = [:]
        var roots: [MarketGroup] = []
        var byID: [Int: MarketGroup] = [:]
        for group in flat {
            byID[group.id] = group
            if let parentID = group.parentGroupID {
                idx[parentID, default: []].append(group)
            } else {
                roots.append(group)
            }
        }
        childrenIndex = idx
        groupByID = byID
        self.roots = roots
    }

    func children(of groupID: Int) -> [MarketGroup] {
        childrenIndex[groupID] ?? []
    }

    func isLeaf(_ group: MarketGroup) -> Bool {
        childrenIndex[group.id]?.isEmpty ?? true
    }

    func group(byID id: Int) -> MarketGroup? {
        groupByID[id]
    }

    /// 按 ID 集合过滤节点（保持 SDE 顺序，等价于旧 setRootGroups 的过滤语义）
    func filter(byIDs ids: Set<Int>) -> [MarketGroup] {
        ids.isEmpty ? roots : flat.filter { ids.contains($0.id) }
    }

    func allSubGroupIDs(from groupID: Int) -> [Int] {
        [groupID] + children(of: groupID).flatMap { allSubGroupIDs(from: $0.id) }
    }

    func allSubGroupIDs(fromRoots rootIDs: Set<Int>) -> [Int] {
        rootIDs.flatMap { allSubGroupIDs(from: $0) }
    }
}

class MarketManager {
    static let shared = MarketManager()
    private init() {}

    /// The Forge（Jita 所在星域）的 regionID，作为全应用的默认市场星域
    static let theForgeRegionID = 10_000_002

    /// PLEX（30 天欧米伽时间）的 typeID；其订单走全球市场（regionID 19000001），位置信息不可解析
    static let plexTypeID = 44992
    static let globalPlexRegionID = 19_000_001

    /// 市场搜索结果分组时的分类展示优先级（舰船、无人机、模块、弹药等），与 EVE 客户端 UI 顺序保持一致。
    /// 多处复用：MarketBrowserView / MarketWatchList / SearchResultView / MarketItemGrouper。
    static let categoryPriority = [6, 7, 32, 8, 4, 16, 18, 87, 20, 22, 9, 5]

    /// 加载市场组数据（内存索引，SDEMemoryStore 已预加载 marketGroups）
    func loadMarketGroups(databaseManager _: DatabaseManager) -> [MarketGroup] {
        SDEMemoryStore.marketGroups.values
            .filter { $0.show }
            .map {
                MarketGroup(
                    id: $0.id,
                    name: $0.name,
                    iconName: $0.iconName,
                    parentGroupID: $0.parentGroupID
                )
            }
            .sorted { $0.id < $1.id }
    }

    /// 从扁平数组构建目录树索引（O(n) 一次构建，后续所有子节点/叶子查询均为 O(1)）
    func buildTree(from groups: [MarketGroup]) -> MarketTree {
        MarketTree(groups)
    }
}
