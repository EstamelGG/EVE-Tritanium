import Foundation
import SwiftUI

/// 多人物并发加载进度
actor AssetsCharacterProgressActor {
    private var current = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

/// 带归属角色的顶层建筑位置（location_id + ownerId 唯一）
struct AssetLocationWithOwner: Identifiable {
    let ownerId: Int
    var location: AssetTreeNode

    var id: String {
        "\(ownerId)_\(location.location_id)"
    }
}

/// 合并后的地点（多人物聚合模式下，按 location_id 去重）
/// entries 只包含有匹配物品的人物（过滤器激活时），并按人物 ID 升序排列
struct MergedAssetLocation: Identifiable {
    let locationId: Int64
    let representativeLocation: AssetTreeNode
    let entries: [AssetLocationWithOwner]
    /// 所有人物在该地点的物品种类数（跨人物去重，创建时按过滤器预计算）
    let totalTypeCount: Int

    var id: Int64 {
        locationId
    }

    var ownerIds: [Int] {
        entries.map(\.ownerId).sorted()
    }
}

/// 搜索结果
struct AssetSearchResult: Identifiable {
    let ownerId: Int
    let node: AssetTreeNode
    let itemInfo: ItemInfo
    let locationPath: [AssetTreeNode]
    let containerNode: AssetTreeNode
    let totalQuantity: Int

    var id: String {
        mergeKey
    }

    var mergeKey: String {
        "\(ownerId)_\(node.type_id)_\(containerNode.item_id)_\(formattedPath.hashValue)"
    }

    /// 格式化的位置路径字符串，只显示到倒数第二级
    var formattedPath: String {
        // 如果路径少于2个节点，直接返回完整路径
        guard locationPath.count >= 2 else {
            return locationPath.map { node in
                HTMLUtils.decodeHTMLEntities(node.name ?? NSLocalizedString("Unknown_System", comment: ""))
            }.joined(separator: " > ")
        }

        // 去掉最后一个节点（当前物品），只显示到倒数第二级
        let pathToShow = locationPath.dropLast()
        return pathToShow.map { node in
            HTMLUtils.decodeHTMLEntities(node.name ?? NSLocalizedString("Unknown_System", comment: ""))
        }.joined(separator: " > ")
    }
}

/// 搜索：站内路径中的一级容器
struct AssetSearchPathSegment: Identifiable {
    let id: Int64
    let iconName: String
    let typeName: String
    let customName: String?
}

/// 搜索：某一物品在某一位置的堆叠
struct AssetSearchOccurrence: Identifiable {
    let id: String
    let ownerId: Int
    let rootLocation: AssetTreeNode
    let containerNode: AssetTreeNode
    let quantity: Int
    let innerPath: [AssetSearchPathSegment]

    static func make(from result: AssetSearchResult, itemInfoCache: [Int: ItemInfo]) -> AssetSearchOccurrence {
        AssetSearchOccurrence(
            id: result.mergeKey,
            ownerId: result.ownerId,
            rootLocation: result.locationPath.first ?? result.containerNode,
            containerNode: result.containerNode,
            quantity: result.totalQuantity,
            innerPath: buildInnerPath(path: result.locationPath, itemInfoCache: itemInfoCache)
        )
    }

    private static func buildInnerPath(
        path: [AssetTreeNode], itemInfoCache: [Int: ItemInfo]
    ) -> [AssetSearchPathSegment] {
        guard path.count > 2 else { return [] }
        let middle = Array(path.dropFirst().dropLast())
        return middle.map { node in
            let itemInfo = itemInfoCache[node.type_id]
            let customName: String? = {
                guard let name = node.name, !name.isEmpty, name != "None" else { return nil }
                return HTMLUtils.decodeHTMLEntities(name)
            }()
            return AssetSearchPathSegment(
                id: node.item_id,
                iconName: node.resolvedIconName(itemInfo: itemInfo),
                typeName: itemInfo?.name ?? String(node.type_id),
                customName: customName
            )
        }
    }
}

/// 搜索：按物品类型聚合
struct AssetSearchItemGroup: Identifiable {
    let typeId: Int
    let itemInfo: ItemInfo
    let totalQuantity: Int
    let occurrences: [AssetSearchOccurrence]

    var id: Int {
        typeId
    }

    static func build(from results: [AssetSearchResult], itemInfoCache: [Int: ItemInfo]) -> [AssetSearchItemGroup] {
        Dictionary(grouping: results, by: { $0.node.type_id })
            .map { typeId, items in
                let occurrences = items
                    .map { AssetSearchOccurrence.make(from: $0, itemInfoCache: itemInfoCache) }
                    .sorted { lhs, rhs in
                        if lhs.ownerId != rhs.ownerId {
                            return lhs.ownerId < rhs.ownerId
                        }
                        if lhs.rootLocation.location_id != rhs.rootLocation.location_id {
                            return lhs.rootLocation.location_id < rhs.rootLocation.location_id
                        }
                        return lhs.containerNode.item_id < rhs.containerNode.item_id
                    }
                let totalQuantity = items.reduce(0) { $0 + $1.totalQuantity }
                return AssetSearchItemGroup(
                    typeId: typeId,
                    itemInfo: items[0].itemInfo,
                    totalQuantity: totalQuantity,
                    occurrences: occurrences
                )
            }
            .sorted { $0.itemInfo.name.localizedCompare($1.itemInfo.name) == .orderedAscending }
    }
}

/// 资产搜索导航上下文（个人/军团共用）
struct AssetSearchNavigationContext {
    let itemInfoCache: [Int: ItemInfo]
    let stationNameCache: [Int64: String]
    let solarSystemNameCache: [Int: String]
    let dynamicResultingTypeIds: Set<Int>
    let databaseManager: DatabaseManager
    let multiCharacterMode: Bool
    let ownerName: (Int) -> String?
    let ownerPortrait: (Int) -> UIImage?
    let typeFilterContext: AssetTypeFilterContext
}

/// 物品信息结构体
struct ItemInfo {
    let names: LocalizedText
    let iconFileName: String
    let bpcIconFileName: String

    var name: String {
        names.resolved()
    }

    init(
        names: LocalizedText,
        iconFileName: String,
        bpcIconFileName: String? = nil
    ) {
        self.names = names
        self.iconFileName = iconFileName
        self.bpcIconFileName = bpcIconFileName ?? iconFileName
    }

    init(from type: SDEMemoryStore.TypeInfo) {
        names = type.names
        iconFileName = type.iconFilename
        bpcIconFileName = type.bpcIconFilename ?? type.iconFilename
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query)
    }

    func withIconFileName(_ icon: String) -> ItemInfo {
        ItemInfo(names: names, iconFileName: icon, bpcIconFileName: bpcIconFileName)
    }
}

extension AssetTreeNode {
    /// 按 type_id 从物品缓存 / 数据库解析图标（不依赖树缓存中的历史 icon 名）
    func resolvedIconName(itemInfo: ItemInfo?) -> String {
        if is_blueprint_copy == true,
           let bpc = itemInfo?.bpcIconFileName, !bpc.isEmpty
        {
            return bpc
        }
        if let icon = itemInfo?.iconFileName, !icon.isEmpty, icon != IconManager.defaultItemIcon {
            return icon
        }
        if type_id > 0,
           let fromDB = DatabaseManager.shared.getItemIconFileName(for: type_id)
        {
            return fromDB
        }
        return IconManager.defaultItemIcon
    }
}

/// 筛选目录节点（分类/组共用）：全量 SDE 目录 + 资产覆盖率数据
struct AssetTypeFilterNode: Identifiable {
    let id: Int
    let name: String
    let iconFileName: String
    /// 资产中存在的物品种数
    let ownedTypeCount: Int
    /// SDE 全量物品种数
    let totalTypeCount: Int

    /// 资产中完全没有该目录物品时行置灰（仍可进入查看）
    var isEnabled: Bool {
        ownedTypeCount > 0
    }
}

/// 目录图标回退：空文件名使用默认图标
private func assetFilterIcon(_ filename: String) -> String {
    filename.isEmpty ? IconManager.defaultIcon : filename
}

/// 筛选目录物品行（全量 SDE 物品，未拥有时置灰且不可选）
struct AssetTypeItemFilter: Identifiable {
    let id: Int
    let name: String
    let iconFileName: String
    let isOwned: Bool
}

/// 资产类型过滤上下文（主列表筛选后传入详情页）
struct AssetTypeFilterContext {
    let selectedTypeIds: Set<Int>

    static let inactive = AssetTypeFilterContext(selectedTypeIds: [])

    var isActive: Bool {
        !selectedTypeIds.isEmpty
    }

    func matches(_ typeId: Int) -> Bool {
        selectedTypeIds.isEmpty || selectedTypeIds.contains(typeId)
    }

    func filterNodesForDisplay(_ nodes: [AssetTreeNode]) -> [AssetTreeNode] {
        guard isActive else { return nodes }
        return nodes.compactMap { filterNodeForDisplay($0) }
    }

    private func filterNodeForDisplay(_ node: AssetTreeNode) -> AssetTreeNode? {
        guard isActive else { return node }

        if let items = node.items, !items.isEmpty {
            let filteredChildren = items.compactMap { filterNodeForDisplay($0) }
            if matches(node.type_id) {
                return node
            }
            guard !filteredChildren.isEmpty else { return nil }
            var copy = node
            copy.items = filteredChildren
            return copy
        }
        return matches(node.type_id) ? node : nil
    }

    func subtreeContainsMatch(_ node: AssetTreeNode) -> Bool {
        if matches(node.type_id) {
            return true
        }
        return node.items?.contains(where: subtreeContainsMatch) ?? false
    }

    /// 地点内符合过滤条件的物品种类数（递归去重，不含地点节点本身）
    func matchingTypeCount(in location: AssetTreeNode) -> Int {
        var typeIds = Set<Int>()
        func walk(_ node: AssetTreeNode) {
            if matches(node.type_id) {
                typeIds.insert(node.type_id)
            }
            node.items?.forEach(walk)
        }
        location.items?.forEach(walk)
        return typeIds.count
    }

    /// 进入匹配过滤条件的容器后，展示其全部内容
    func containerContext(for node: AssetTreeNode) -> AssetTypeFilterContext {
        if isActive, matches(node.type_id) {
            return .inactive
        }
        return self
    }
}

@MainActor
class CharacterAssetsViewModel: ObservableObject {
    // MARK: - 发布属性

    @Published var isLoading = false
    @Published var assetLocations: [AssetLocationWithOwner] = []
    @Published var error: Error?
    @Published var loadingProgress: AssetLoadingProgress?
    // 多人物加载进度 (已加载/总数)
    @Published var characterLoadingProgress: (current: Int, total: Int)?
    @Published private(set) var searchItemGroups: [AssetSearchItemGroup] = []
    @Published var regionNames: [Int: String] = [:]
    @Published var systemInfoCache: [Int: SolarSystemInfo] = [:]
    @Published var stationNameCache: [Int64: String] = [:]
    @Published var solarSystemNameCache: [Int: String] = [:]
    @Published var dataLoadTime: Date?
    @Published private(set) var unpinnedLocationsByRegion:
        [(region: String, locations: [AssetLocationWithOwner])] = []

    @Published var multiCharacterMode = false {
        didSet {
            UserDefaults.standard.set(multiCharacterMode, forKey: "multiCharacterMode_assets")
            // 切换模式优先使用各角色缓存，保证即时响应；下拉刷新才强制走网络
            if initialLoadDone {
                Task { await loadAssets() }
            }
        }
    }

    @Published var mergeLocations = false {
        didSet {
            UserDefaults.standard.set(mergeLocations, forKey: "mergeLocations_assets")
        }
    }

    @Published var selectedCharacterIds: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_assets"
            )
            // 切换所选人物优先使用各角色缓存，保证即时响应；下拉刷新才强制走网络
            if initialLoadDone, multiCharacterMode {
                Task { await loadAssets() }
            }
        }
    }

    @Published var availableCharacters: [(id: Int, name: String)] = []
    @Published private(set) var ownerPortraits: [Int: UIImage] = [:]
    @Published private(set) var selectedTypeIds: Set<Int> = []
    /// 过滤命中的物品件数总和（过滤徽标第二行"共 x 件"）
    @Published private(set) var activeFilterItemCount = 0

    // MARK: - 私有属性

    /// 当前进行中的资产加载任务。新的加载请求到来时取消旧任务，保证"最新选择优先"。
    private var loadTask: Task<Void, Never>?
    private var initialLoadDone = false
    private(set) var itemInfoCache: [Int: ItemInfo] = [:]
    private(set) var dynamicResultingTypeIds: Set<Int> = []
    private var searchIndexByTypeId: [Int: [AssetSearchEntry]] = [:]
    /// 筛选徽标：资产内持有的物品种类集合
    private var ownedTypeIds: Set<Int> = []

    // MARK: 市场视图筛选数据（marketGroupID 体系）

    private var marketFilterNodesById: [Int: AssetTypeFilterNode] = [:]
    private var marketChildrenByParent: [Int: [Int]] = [:]
    private var marketRootIds: [Int] = []
    /// 各目录子树内资产已持有的物品种类集合（目录层"全部过滤"开关用）
    private var marketOwnedTypeIdsByGroup: [Int: Set<Int>] = [:]
    private let characterId: Int
    private let databaseManager: DatabaseManager

    private struct AssetSearchEntry {
        let ownerId: Int
        let node: AssetTreeNode
        let locationPath: [AssetTreeNode]
        let containerNode: AssetTreeNode
    }

    // MARK: - 计算属性

    private var activeCharacterIds: [Int] {
        if multiCharacterMode {
            return Array(selectedCharacterIds).sorted()
        }
        return [characterId]
    }

    var isTypeFilterActive: Bool {
        typeFilterContext.isActive
    }

    var activeFilterLabel: String? {
        guard isTypeFilterActive else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("Assets_Filter_Active_Types_Format", comment: ""),
            selectedTypeIds.count
        )
    }

    /// 过滤命中件数文案（过滤徽标第二行）
    var activeFilterItemCountLabel: String? {
        guard isTypeFilterActive else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("Assets_Filter_Active_Item_Count_Format", comment: ""),
            activeFilterItemCount
        )
    }

    var typeFilterContext: AssetTypeFilterContext {
        AssetTypeFilterContext(selectedTypeIds: selectedTypeIds)
    }

    // MARK: - 筛选目录（市场视图）

    /// 市场视图：根目录列表（子树内无 SDE 物品的目录不显示；按市场组 ID 固定排序）
    var marketRootFilterNodes: [AssetTypeFilterNode] {
        marketRootIds.compactMap { marketFilterNodesById[$0] }
            .filter { $0.totalTypeCount > 0 }
            .sorted { $0.id < $1.id }
    }

    /// 市场视图：某目录的子目录（子树内无 SDE 物品的目录不显示；按市场组 ID 固定排序）
    func marketGroupFilters(for id: Int) -> [AssetTypeFilterNode] {
        (marketChildrenByParent[id] ?? []).compactMap { marketFilterNodesById[$0] }
            .filter { $0.totalTypeCount > 0 }
            .sorted { $0.id < $1.id }
    }

    /// 市场视图：叶子目录直属物品，未拥有时置灰；已拥有（可选）优先展示
    func marketFilterItems(for id: Int) -> [AssetTypeItemFilter] {
        var items: [AssetTypeItemFilter] = []
        for (typeId, info) in SDEMemoryStore.types
            where info.published && info.marketGroupID == id
        {
            items.append(
                AssetTypeItemFilter(
                    id: typeId,
                    name: info.names.resolved(),
                    iconFileName: assetFilterIcon(info.iconFilename),
                    isOwned: ownedTypeIds.contains(typeId)
                )
            )
        }
        items.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        return items.filter(\.isOwned) + items.filter { !$0.isOwned }
    }

    /// 市场视图：某目录子树内资产已持有的物品种类集合（目录层"全部过滤"开关用）
    func marketOwnedTypeIds(for id: Int) -> Set<Int> {
        marketOwnedTypeIdsByGroup[id] ?? []
    }

    /// 资产中存在、但没有市场目录的物品（含数据库无记录的）
    func filterOwnedItemsWithoutMarketGroup() -> [AssetTypeItemFilter] {
        ownedItemFilter { info in
            guard let info else { return true }
            return info.marketGroupID == nil
        }
    }

    /// 资产中存在、但在物品数据库中未发布的物品（含数据库无记录的）
    func filterOwnedUnpublishedItems() -> [AssetTypeItemFilter] {
        ownedItemFilter { info in
            guard let info else { return true }
            return !info.published
        }
    }

    /// 按条件从资产持有的物品构建筛选项（按名称排序，全部可选）
    private func ownedItemFilter(
        where keep: (SDEMemoryStore.TypeInfo?) -> Bool
    ) -> [AssetTypeItemFilter] {
        var items: [AssetTypeItemFilter] = []
        for typeId in ownedTypeIds {
            let info = SDEMemoryStore.type(for: typeId)
            guard keep(info) else { continue }
            items.append(
                AssetTypeItemFilter(
                    id: typeId,
                    name: info?.names.resolved() ?? "Type ID: \(typeId)",
                    iconFileName: assetFilterIcon(info?.iconFilename ?? ""),
                    isOwned: true
                )
            )
        }
        items.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        return items
    }

    var pinnedLocations: [AssetLocationWithOwner] {
        assetLocations.filter { isLocationPinned($0) && typeFilterContext.subtreeContainsMatch($0.location) }
            .sorted {
                if $0.location.location_id != $1.location.location_id {
                    return $0.location.location_id < $1.location.location_id
                }
                return $0.ownerId < $1.ownerId
            }
    }

    // MARK: - 合并地点（多人物聚合 + mergeLocations 模式）

    /// 合并模式下的置顶地点：按 location_id 去重，任一人物置顶即显示
    /// entries 只包含有匹配物品的人物；totalTypeCount 按过滤器预计算
    var mergedPinnedLocations: [MergedAssetLocation] {
        let pinnedLocationIds = Set(
            assetLocations.filter { isLocationPinned($0) }.map { $0.location.location_id }
        )
        let context = typeFilterContext
        let merged = Dictionary(grouping: assetLocations) { $0.location.location_id }
        return pinnedLocationIds.compactMap { locId in
            let entries = (merged[locId] ?? [])
                .filter { context.subtreeContainsMatch($0.location) }
                .sorted { $0.ownerId < $1.ownerId }
            guard !entries.isEmpty else { return nil }
            return MergedAssetLocation(
                locationId: locId,
                representativeLocation: entries[0].location,
                entries: entries,
                totalTypeCount: mergedTypeCount(for: entries)
            )
        }
        .sorted { $0.locationId < $1.locationId }
    }

    /// 合并模式下的非置顶地点：按 location_id 去重，按星域分组
    /// entries 只包含有匹配物品的人物；totalTypeCount 按过滤器预计算
    var mergedUnpinnedLocationsByRegion:
        [(region: String, locations: [MergedAssetLocation])]
    {
        let pinnedLocationIds = Set(
            assetLocations.filter { isLocationPinned($0) }.map { $0.location.location_id }
        )
        let context = typeFilterContext
        let grouped = Dictionary(grouping: assetLocations) { $0.location.location_id }
        let unknownRegion = NSLocalizedString("Assets_Unknown_Region", comment: "")

        var regionDict: [String: [MergedAssetLocation]] = [:]

        for (locId, entries) in grouped {
            let filtered = entries
                .filter {
                    !pinnedLocationIds.contains($0.location.location_id)
                        && context.subtreeContainsMatch($0.location)
                }
                .sorted { $0.ownerId < $1.ownerId }
            guard !filtered.isEmpty else { continue }

            let regionName: String
            if let regionId = filtered[0].location.region_id,
               let name = regionNames[regionId]
            {
                regionName = name
            } else {
                regionName = unknownRegion
            }

            let merged = MergedAssetLocation(
                locationId: locId,
                representativeLocation: filtered[0].location,
                entries: filtered,
                totalTypeCount: mergedTypeCount(for: filtered)
            )
            regionDict[regionName, default: []].append(merged)
        }

        return regionDict.map { (region: $0.key, locations: sortMergedLocations($0.value)) }
            .sorted { pair1, pair2 in
                if pair1.region == unknownRegion {
                    return false
                }
                if pair2.region == unknownRegion {
                    return true
                }
                return pair1.region < pair2.region
            }
    }

    /// 合并地点的多人物物品种类数（跨人物去重，不含地点节点本身，按过滤器）
    private func mergedTypeCount(for entries: [AssetLocationWithOwner]) -> Int {
        let context = typeFilterContext
        var typeIds = Set<Int>()
        func walk(_ node: AssetTreeNode) {
            if context.matches(node.type_id) {
                typeIds.insert(node.type_id)
            }
            node.items?.forEach(walk)
        }
        for entry in entries {
            entry.location.items?.forEach(walk)
        }
        return typeIds.count
    }

    private func sortMergedLocations(_ locations: [MergedAssetLocation]) -> [MergedAssetLocation] {
        locations.sorted { loc1, loc2 in
            if let system1 = loc1.representativeLocation.system_id,
               let system2 = loc2.representativeLocation.system_id
            {
                if system1 != system2 {
                    return system1 < system2
                }
            }
            return loc1.locationId < loc2.locationId
        }
    }

    /// 获取指定 location_id 下所有人物的资产条目（用于地点详情页）
    func entriesForLocation(_ locationId: Int64) -> [AssetLocationWithOwner] {
        assetLocations.filter { $0.location.location_id == locationId }
    }

    func ownerName(for ownerId: Int) -> String? {
        availableCharacters.first { $0.id == ownerId }?.name
    }

    func ownerPortrait(for ownerId: Int) -> UIImage? {
        ownerPortraits[ownerId]
    }

    // MARK: - 初始化

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager

        multiCharacterMode = UserDefaults.standard.bool(forKey: "multiCharacterMode_assets")
        mergeLocations = UserDefaults.standard.bool(forKey: "mergeLocations_assets")
        let savedIds =
            UserDefaults.standard.array(forKey: "selectedCharacterIds_assets") as? [Int] ?? []
        selectedCharacterIds = Set(savedIds)
        availableCharacters = CharacterSkillsUtils.getAllCharacters()

        let availableIds = Set(availableCharacters.map(\.id))
        let validIds = selectedCharacterIds.intersection(availableIds)
        if validIds.count != selectedCharacterIds.count {
            selectedCharacterIds = validIds
            UserDefaults.standard.set(Array(validIds), forKey: "selectedCharacterIds_assets")
        }
        if selectedCharacterIds.isEmpty {
            selectedCharacterIds.insert(characterId)
        }

        // 构造时启动资产加载（原先由视图 init 触发，移入以避免视图重复构造引发重复加载）
        Task {
            await loadAssets()
        }
    }

    // MARK: - 置顶功能方法

    /// 切换置顶状态（写入该行的归属人物配置）
    func togglePinLocation(_ entry: AssetLocationWithOwner) {
        let locationId = entry.location.location_id
        let ownerId = entry.ownerId

        if UserDefaultsManager.shared.isAssetLocationPinned(locationId, for: ownerId) {
            UserDefaultsManager.shared.removePinnedAssetLocation(locationId, for: ownerId)
        } else {
            UserDefaultsManager.shared.addPinnedAssetLocation(locationId, for: ownerId)
        }

        rebuildRegionGroups()
    }

    func isLocationPinned(_ entry: AssetLocationWithOwner) -> Bool {
        UserDefaultsManager.shared.isAssetLocationPinned(
            entry.location.location_id, for: entry.ownerId
        )
    }

    // MARK: - 私有辅助方法

    /// 清理无效的置顶位置ID（按各归属人物分别清理）
    private func cleanupInvalidPinnedLocations() {
        for ownerId in Set(assetLocations.map(\.ownerId)) {
            let currentLocationIds = Set(
                assetLocations.filter { $0.ownerId == ownerId }.map(\.location.location_id)
            )
            let pinnedLocationIds = UserDefaultsManager.shared.getPinnedAssetLocationIDs(for: ownerId)
            let validPinnedIds = pinnedLocationIds.filter { currentLocationIds.contains($0) }
            guard validPinnedIds.count != pinnedLocationIds.count else { continue }

            Logger.info("清理角色 \(ownerId) 无效置顶位置: \(pinnedLocationIds.filter { !currentLocationIds.contains($0) })")
            UserDefaultsManager.shared.setPinnedAssetLocationIDs(validPinnedIds, for: ownerId)
        }
    }

    /// 对位置进行排序
    private func sortLocations(_ locations: [AssetLocationWithOwner]) -> [AssetLocationWithOwner] {
        locations.sorted { loc1, loc2 in
            let n1 = loc1.location
            let n2 = loc2.location
            if let system1 = n1.system_id, let system2 = n2.system_id {
                if system1 != system2 {
                    return system1 < system2
                }
                if loc1.ownerId != loc2.ownerId {
                    return loc1.ownerId < loc2.ownerId
                }
                return n1.location_id < n2.location_id
            }
            return n1.system_id != nil
        }
    }

    /// 收集资产树中所有物品的type_id
    private func collectAllTypeIds() -> Set<Int> {
        var typeIds = Set<Int>()

        /// 递归函数收集所有type_id
        func collectTypeIds(from node: AssetTreeNode) {
            typeIds.insert(node.type_id)

            if let items = node.items {
                for item in items {
                    collectTypeIds(from: item)
                }
            }
        }

        // 从所有顶层位置开始收集
        for entry in assetLocations {
            collectTypeIds(from: entry.location)
        }

        return typeIds
    }

    /// 收集资产数据中所有的空间站ID
    private func collectAllStationIds() -> [Int64] {
        var stationIds = Set<Int64>()

        func collectFromNode(_ node: AssetTreeNode) {
            // 如果节点是空间站类型，收集其ID
            if node.location_type == "station" {
                stationIds.insert(node.location_id)
            }

            // 递归处理子节点
            if let items = node.items {
                for item in items {
                    collectFromNode(item)
                }
            }
        }

        // 从所有顶层位置开始收集
        for entry in assetLocations {
            collectFromNode(entry.location)
        }

        return Array(stationIds)
    }

    /// 从 SDEMemoryStore 获取所有突变产物 resulting_type 集合
    private func loadDynamicResultingTypes() {
        dynamicResultingTypeIds = SDEMemoryStore.dynamicResultingTypeIDs
    }

    /// 从数据库中获取物品信息的辅助方法
    private func fetchItemInfoFromDatabase(_ typeIds: Set<Int>) {
        if typeIds.isEmpty {
            return
        }

        for typeId in typeIds {
            guard let info = SDEMemoryStore.type(for: typeId) else { continue }
            itemInfoCache[typeId] = ItemInfo(from: info)
        }
    }

    /// 应用物品多选筛选（筛选面板"完成"时调用）
    func applyTypeFilter(_ typeIds: Set<Int>) {
        selectedTypeIds = typeIds
        rebuildRegionGroups()
    }

    /// 构建筛选数据：持有物品种类集合 + 市场目录覆盖率统计
    private func buildTypeFilterIndex() {
        // 顶层地点（空间站/建筑/星系）不算自己拥有的物品，统计从地点内的东西开始
        var ownedTypes = Set<Int>()
        func walk(_ node: AssetTreeNode) {
            ownedTypes.insert(node.type_id)
            node.items?.forEach(walk)
        }
        for entry in assetLocations {
            entry.location.items?.forEach(walk)
        }
        ownedTypeIds = ownedTypes

        // 无资产时市场目录仍可浏览（覆盖率为 0）
        buildMarketFilterIndex()
    }

    /// 构建市场筛选目录：marketGroupID 树 + 子树覆盖率统计（子树种类向上汇总）
    private func buildMarketFilterIndex() {
        // 直属统计：资产物品按 marketGroupID 归集（不含地点节点本身）
        var directOwnedTypes: [Int: Set<Int>] = [:]
        func walkMarket(_ node: AssetTreeNode) {
            if let info = SDEMemoryStore.type(for: node.type_id),
               let marketGroupID = info.marketGroupID
            {
                directOwnedTypes[marketGroupID, default: []].insert(node.type_id)
            }
            node.items?.forEach(walkMarket)
        }
        for entry in assetLocations {
            entry.location.items?.forEach(walkMarket)
        }

        // 各市场目录直属 SDE 已发布物品种数
        var directTypeCounts: [Int: Int] = [:]
        for info in SDEMemoryStore.types.values where info.published {
            if let marketGroupID = info.marketGroupID {
                directTypeCounts[marketGroupID, default: 0] += 1
            }
        }

        // 目录树结构
        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for (id, group) in SDEMemoryStore.marketGroups {
            if let parentID = group.parentGroupID {
                children[parentID, default: []].append(id)
            } else {
                roots.append(id)
            }
        }

        // 后序遍历汇总子树统计并生成节点
        var nodes: [Int: AssetTypeFilterNode] = [:]
        var ownedSets: [Int: Set<Int>] = [:]
        func buildNode(_ id: Int) -> (owned: Set<Int>, total: Int) {
            var owned = directOwnedTypes[id] ?? []
            var total = directTypeCounts[id] ?? 0
            for childID in children[id] ?? [] {
                let result = buildNode(childID)
                owned.formUnion(result.owned)
                total += result.total
            }
            let info = SDEMemoryStore.marketGroups[id]
            nodes[id] = AssetTypeFilterNode(
                id: id,
                name: info?.name ?? "\(id)",
                iconFileName: assetFilterIcon(info?.iconName ?? ""),
                ownedTypeCount: owned.count,
                totalTypeCount: total
            )
            ownedSets[id] = owned
            return (owned, total)
        }
        for rootID in roots {
            _ = buildNode(rootID)
        }

        marketFilterNodesById = nodes
        marketChildrenByParent = children
        marketRootIds = roots
        marketOwnedTypeIdsByGroup = ownedSets
    }

    private func rebuildRegionGroups() {
        let context = typeFilterContext
        let unpinnedLocations = assetLocations.filter {
            !isLocationPinned($0) && (!context.isActive || context.subtreeContainsMatch($0.location))
        }

        let unknownRegion = NSLocalizedString("Assets_Unknown_Region", comment: "")
        let grouped = Dictionary(grouping: unpinnedLocations) { entry in
            if let regionId = entry.location.region_id,
               let regionName = regionNames[regionId]
            {
                return regionName
            }
            return unknownRegion
        }

        unpinnedLocationsByRegion = grouped.filter { !$0.value.isEmpty }
            .map { (region: $0.key, locations: sortLocations($0.value)) }
            .sorted { pair1, pair2 in
                if pair1.region == unknownRegion {
                    return false
                }
                if pair2.region == unknownRegion {
                    return true
                }
                return pair1.region < pair2.region
            }

        // 同步过滤命中物品件数（资产加载与过滤变更后均会重建）
        activeFilterItemCount = matchingItemCount(context: context)
    }

    /// 过滤命中的物品件数总和：递归累加命中节点的 quantity（不含地点节点本身）
    private func matchingItemCount(context: AssetTypeFilterContext) -> Int {
        var count = 0
        func walk(_ node: AssetTreeNode) {
            if context.matches(node.type_id) {
                count += node.quantity
            }
            node.items?.forEach(walk)
        }
        for entry in assetLocations {
            entry.location.items?.forEach(walk)
        }
        return count
    }

    private func buildSearchIndex() {
        var index: [Int: [AssetSearchEntry]] = [:]
        for entry in assetLocations {
            collectSearchEntries(
                in: entry.location, ownerId: entry.ownerId, currentPath: [], index: &index
            )
        }
        searchIndexByTypeId = index
    }

    private func collectSearchEntries(
        in node: AssetTreeNode,
        ownerId: Int,
        currentPath: [AssetTreeNode],
        index: inout [Int: [AssetSearchEntry]]
    ) {
        var path = currentPath
        path.append(node)
        let container = path.count > 1 ? path[path.count - 2] : node
        index[node.type_id, default: []].append(
            AssetSearchEntry(
                ownerId: ownerId, node: node, locationPath: path, containerNode: container
            )
        )
        if let items = node.items {
            for item in items {
                collectSearchEntries(in: item, ownerId: ownerId, currentPath: path, index: &index)
            }
        }
    }

    // MARK: - 公共方法

    /// 加载资产。切换所选人物用缓存（forceRefresh=false，秒切），下拉刷新/重试用 forceRefresh=true 走网络。
    /// 每次调用都会取消进行中的加载任务，确保最新的选择优先，避免"所选人物与显示不一致"。
    func loadAssets(forceRefresh: Bool = false) async {
        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performAssetLoad(forceRefresh: forceRefresh)
        }
        loadTask = task
        await task.value
    }

    private func performAssetLoad(forceRefresh: Bool) async {
        let characterIds = activeCharacterIds

        // 所选人物为空：直接清空，无需加载
        if characterIds.isEmpty {
            if !Task.isCancelled {
                assetLocations = []
                error = nil
                rebuildRegionGroups()
                isLoading = false
                loadingProgress = nil
                characterLoadingProgress = nil
            }
            return
        }

        if !Task.isCancelled {
            if forceRefresh {
                if characterIds.count == 1 {
                    loadingProgress = .loading(page: 1)
                }
            } else {
                isLoading = true
                if characterIds.count == 1 {
                    loadingProgress = .loading(page: 1)
                }
            }
        }

        do {
            if characterIds.count > 1 {
                try await loadMultipleCharacters(characterIds, forceRefresh: forceRefresh)
            } else {
                try await loadSingleCharacter(characterIds[0], forceRefresh: forceRefresh)
            }
            // 被更新的任务取消后，不应用其结果，避免覆盖最新选择的数据
            guard !Task.isCancelled else { return }
            await finalizeLoadedAssets()
            error = nil
            cleanupInvalidPinnedLocations()
            initialLoadDone = true
        } catch {
            if isCancellation(error) {
                Logger.info("资产加载任务被取消")
            } else if !Task.isCancelled {
                Logger.error("加载资产失败: \(error)")
                self.error = error
                // 加载失败时清空资产，避免残留与当前所选人物不一致的旧数据
                assetLocations = []
                rebuildRegionGroups()
            }
        }

        // 只有未被取代的当前任务才清理加载状态，避免误清正在运行的最新任务的状态
        if !Task.isCancelled {
            isLoading = false
            loadingProgress = nil
            characterLoadingProgress = nil
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let nsError = error as NSError?,
           nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled
        {
            return true
        }
        return false
    }

    private func loadSingleCharacter(_ charId: Int, forceRefresh: Bool) async throws {
        guard let wrapper = try await CharacterAssetsJsonAPI.shared.generateAssetTree(
            characterId: charId,
            forceRefresh: forceRefresh,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    guard !(Task.isCancelled) else { return }
                    self?.loadingProgress = progress
                    if case .completed = progress {
                        self?.isLoading = false
                    }
                }
            }
        ) else { return }

        // 被取消后不写入结果，交给后续最新的加载任务处理
        try Task.checkCancellation()
        dataLoadTime = Date(timeIntervalSince1970: TimeInterval(wrapper.update_time))
        assetLocations = wrapper.assetsTree.map {
            AssetLocationWithOwner(ownerId: charId, location: $0)
        }
    }

    private func loadMultipleCharacters(_ characterIds: [Int], forceRefresh: Bool) async throws {
        let total = characterIds.count
        characterLoadingProgress = (0, total)

        let progressActor = AssetsCharacterProgressActor(total: total) { [weak self] current, total in
            Task { @MainActor in
                self?.characterLoadingProgress = (current: current, total: total)
            }
        }

        var allLocations: [AssetLocationWithOwner] = []
        var latestUpdateTime: TimeInterval = 0
        var firstError: Error?

        await withTaskGroup(of: (Int, Result<AssetTreeWrapper?, Error>).self) { group in
            for charId in characterIds {
                group.addTask {
                    do {
                        let wrapper = try await CharacterAssetsJsonAPI.shared.generateAssetTree(
                            characterId: charId,
                            forceRefresh: forceRefresh,
                            progressCallback: { _ in }
                        )
                        return (charId, .success(wrapper))
                    } catch {
                        return (charId, .failure(error))
                    }
                }
            }

            for await (charId, result) in group {
                if Task.isCancelled {
                    break
                }
                await progressActor.increment()
                switch result {
                case let .success(wrapper?):
                    latestUpdateTime = max(latestUpdateTime, TimeInterval(wrapper.update_time))
                    allLocations.append(
                        contentsOf: wrapper.assetsTree.map {
                            AssetLocationWithOwner(ownerId: charId, location: $0)
                        }
                    )
                case let .failure(error):
                    Logger.error("加载角色\(charId)资产失败: \(error)")
                    if firstError == nil {
                        firstError = error
                    }
                case .success(nil):
                    break
                }
            }
        }

        // 被取消后不写入部分结果，交给后续最新的加载任务处理
        try Task.checkCancellation()
        assetLocations = allLocations
        if latestUpdateTime > 0 {
            dataLoadTime = Date(timeIntervalSince1970: latestUpdateTime)
        }
        if allLocations.isEmpty, let firstError {
            throw firstError
        }
    }

    private func finalizeLoadedAssets() async {
        await loadRegionNames()
        await preloadStationNames()
        await loadItemInfoFromDatabase()
        loadDynamicResultingTypes()
        await fillNodeNamesInMemory()
        buildSearchIndex()
        buildTypeFilterIndex()
        rebuildRegionGroups()
        if multiCharacterMode {
            await loadOwnerPortraits(for: availableCharacters.map(\.id))
        }
    }

    private func loadOwnerPortraits(for characterIds: [Int]) async {
        // 仅拉取尚未缓存的头像，避免每次切换所选人物都重复请求
        let toFetch = characterIds.filter { ownerPortraits[$0] == nil }
        guard !toFetch.isEmpty else { return }
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for id in toFetch {
                group.addTask {
                    let image = try? await CharacterAPI.shared.fetchCharacterPortrait(
                        characterId: id, size: 32, catchImage: false
                    )
                    return (id, image)
                }
            }
            for await (id, image) in group {
                if let image {
                    ownerPortraits[id] = image
                }
            }
        }
    }

    /// 加载星域名称
    private func loadRegionNames() async {
        // 收集所有需要查询的星系ID
        let systemIds = Set(assetLocations.compactMap { $0.location.system_id })

        // 如果没有星系ID，直接返回
        if systemIds.isEmpty {
            return
        }

        // 使用批量查询获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: Array(systemIds),
            databaseManager: databaseManager
        )

        // 保存星系信息到缓存
        systemInfoCache = systemInfoMap

        // 从查询结果中提取区域信息和星系名称
        for (systemId, systemInfo) in systemInfoMap {
            regionNames[systemInfo.regionId] = systemInfo.regionName
            solarSystemNameCache[systemId] = systemInfo.systemName
        }

        // 触发UI更新
        rebuildRegionGroups()
    }

    /// 预加载所有空间站名称
    private func preloadStationNames() async {
        let stationIds = collectAllStationIds()

        if stationIds.isEmpty {
            Logger.info("没有需要预载的空间站ID")
            return
        }

        // 构建SQL查询，一次性获取所有空间站名称
        for stationId in stationIds {
            if let name = SDEMemoryStore.station(for: Int(stationId))?.name {
                stationNameCache[Int64(stationId)] = name
            }
        }
    }

    /// 从数据库中加载物品信息
    private func loadItemInfoFromDatabase() async {
        // 收集所有需要的type_id
        let typeIds = collectAllTypeIds()
        // 使用辅助方法从数据库中获取信息
        fetchItemInfoFromDatabase(typeIds)
    }

    /// 搜索资产
    func searchAssets(query: String) async {
        guard !query.isEmpty else {
            searchItemGroups = []
            return
        }

        // 使用缓存的物品信息进行搜索，而不是查询数据库
        var matchingTypeIds: [Int: ItemInfo] = [:]

        // 在缓存中查找匹配搜索条件的物品（任意语种名称）
        for (typeId, itemInfo) in itemInfoCache {
            if itemInfo.matches(query) {
                matchingTypeIds[typeId] = itemInfo
            }
        }

        // 在资产数据中查找这些type_id对应的item_id
        let context = typeFilterContext
        var rawResults: [AssetSearchResult] = []
        for (typeId, itemInfo) in matchingTypeIds {
            guard context.matches(typeId) else { continue }
            guard let entries = searchIndexByTypeId[typeId] else { continue }
            for entry in entries {
                let updatedItemInfo = itemInfo.withIconFileName(
                    entry.node.resolvedIconName(itemInfo: itemInfo)
                )
                rawResults.append(
                    AssetSearchResult(
                        ownerId: entry.ownerId,
                        node: entry.node,
                        itemInfo: updatedItemInfo,
                        locationPath: entry.locationPath,
                        containerNode: entry.containerNode,
                        totalQuantity: 0
                    )
                )
            }
        }

        // 按位置和物品类型合并结果
        var mergedResults: [String: AssetSearchResult] = [:]

        for result in rawResults {
            let key = result.mergeKey
            if let existingResult = mergedResults[key] {
                // 合并数量
                let newTotalQuantity = existingResult.totalQuantity + result.node.quantity

                let mergedResult = AssetSearchResult(
                    ownerId: existingResult.ownerId,
                    node: existingResult.node,
                    itemInfo: existingResult.itemInfo,
                    locationPath: existingResult.locationPath,
                    containerNode: existingResult.containerNode,
                    totalQuantity: newTotalQuantity
                )
                mergedResults[key] = mergedResult
            } else {
                let initialResult = AssetSearchResult(
                    ownerId: result.ownerId,
                    node: result.node,
                    itemInfo: result.itemInfo,
                    locationPath: result.locationPath,
                    containerNode: result.containerNode,
                    totalQuantity: result.node.quantity
                )
                mergedResults[key] = initialResult
            }
        }

        searchItemGroups = AssetSearchItemGroup.build(
            from: Array(mergedResults.values).sorted { $0.itemInfo.name < $1.itemInfo.name },
            itemInfoCache: itemInfoCache
        )
    }

    /// 在内存中填充节点名称
    private func fillNodeNamesInMemory() async {
        /// 递归函数，填充节点及其所有子节点的名称
        func fillNodeName(_ node: inout AssetTreeNode) {
            // 为空间站节点填充名称
            if node.location_type == "station", node.name == nil {
                node.name = stationNameCache[node.location_id]
            }

            // 为星系节点填充名称
            if node.location_type == "solar_system", node.name == nil,
               let systemId = node.system_id
            {
                node.name = solarSystemNameCache[systemId]
            }

            // 递归处理子节点
            if var items = node.items {
                for i in 0 ..< items.count {
                    fillNodeName(&items[i])
                }
                node.items = items
            }
        }

        // 遍历并处理所有顶层位置节点
        for i in 0 ..< assetLocations.count {
            fillNodeName(&assetLocations[i].location)
        }
    }
}
