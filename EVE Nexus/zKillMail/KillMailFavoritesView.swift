import SwiftUI

// MARK: - UserDefaults 收藏存储

struct FavoriteKillMailRecord: Codable, Equatable {
    let killmailId: Int
    let hash: String
    /// 收藏时缓存的 zkill 总价；旧版 JSON 无此键，解码为 `nil`。
    let value: Double?
    /// zkill 掉落总价值；可选，与 `value` 迁移策略相同。
    let droppedValue: Double?
    /// zkill 摧毁总价值；可选。
    let destroyedValue: Double?
}

final class KillMailFavoritesStore: ObservableObject {
    static let shared = KillMailFavoritesStore()

    private let defaultsKey = "KillMailFavoriteKMRecords"

    @Published private(set) var records: [FavoriteKillMailRecord] = []

    private init() {
        records = Self.loadFromDefaults(key: defaultsKey)
    }

    private static func loadFromDefaults(key: String) -> [FavoriteKillMailRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        if let decoded = try? JSONDecoder().decode([FavoriteKillMailRecord].self, from: data) {
            return decoded
        }
        return []
    }

    /// 仅 id+hash 参与「列表是否需整表重载」判断；`value` 回填不触发 `reloadFromStart`。
    static func listIdentityIgnoringValue(_ records: [FavoriteKillMailRecord]) -> String {
        records.map { "\($0.killmailId):\($0.hash)" }.joined(separator: "\u{1e}")
    }

    /// 与列表展示一致：按 killmail id 降序。
    static func recordsSortedByKillmailId(_ records: [FavoriteKillMailRecord]) -> [FavoriteKillMailRecord] {
        records.sorted { $0.killmailId > $1.killmailId }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func isFavorite(killmailId: Int) -> Bool {
        records.contains { $0.killmailId == killmailId }
    }

    func add(
        killmailId: Int,
        hash: String,
        value: Double? = nil,
        droppedValue: Double? = nil,
        destroyedValue: Double? = nil
    ) {
        guard !isFavorite(killmailId: killmailId) else { return }
        var next = records
        next.insert(
            FavoriteKillMailRecord(
                killmailId: killmailId,
                hash: hash,
                value: value,
                droppedValue: droppedValue,
                destroyedValue: destroyedValue
            ),
            at: 0
        )
        records = next
        persist()
    }

    func remove(killmailId: Int) {
        remove(killmailIds: Set([killmailId]))
    }

    /// 批量取消收藏，仅触发一次 `objectWillChange`，便于列表动画与「忽略重载」标记配合
    func remove(killmailIds: Set<Int>) {
        guard !killmailIds.isEmpty else { return }
        records.removeAll { killmailIds.contains($0.killmailId) }
        persist()
    }

    func toggle(
        killmailId: Int,
        hash: String,
        value: Double? = nil,
        droppedValue: Double? = nil,
        destroyedValue: Double? = nil
    ) {
        if isFavorite(killmailId: killmailId) {
            remove(killmailId: killmailId)
        } else {
            add(
                killmailId: killmailId,
                hash: hash,
                value: value,
                droppedValue: droppedValue,
                destroyedValue: destroyedValue
            )
        }
    }

    /// 自 zkill 拉回数据后写入；仅填补本地仍为 `nil` 的字段，不覆盖已有缓存。
    @MainActor
    func updateStoredZkbFieldsIfMissing(
        killmailId: Int,
        totalValue: Double? = nil,
        droppedValue: Double? = nil,
        destroyedValue: Double? = nil
    ) {
        guard let idx = records.firstIndex(where: { $0.killmailId == killmailId }) else { return }
        let old = records[idx]
        var v = old.value
        if v == nil, let t = totalValue {
            v = t
        }
        var d = old.droppedValue
        if d == nil, let dv = droppedValue {
            d = dv
        }
        var des = old.destroyedValue
        if des == nil, let dsv = destroyedValue {
            des = dsv
        }
        guard v != old.value || d != old.droppedValue || des != old.destroyedValue else { return }
        var next = records
        next[idx] = FavoriteKillMailRecord(
            killmailId: old.killmailId,
            hash: old.hash,
            value: v,
            droppedValue: d,
            destroyedValue: des
        )
        records = next
        persist()
    }
}

// MARK: - 收藏夹列表

@MainActor
private final class KillMailFavoritesListModel: ObservableObject {
    @Published private(set) var entries: [KillMailEntry] = []
    @Published private(set) var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @Published private(set) var allianceIconMap: [Int: UIImage] = [:]
    @Published private(set) var corporationIconMap: [Int: UIImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    // 行级异步 zkill 估值（ESI 用本地 hash，不阻塞在估值请求上）
    @Published private(set) var asyncISKByKillmailId: [Int: Double] = [:]
    @Published private(set) var iskLoadingKillmailIds: Set<Int> = []

    // 懒加载：每批仅从收藏序列取 10 条做 ESI/展示；估值按行异步补全
    private let pageSize = 10
    private var recordsSnapshot: [FavoriteKillMailRecord] = []
    // 已按条Consumed 的 `recordsSnapshot` 前缀长度（含拉取结果为空的收藏条）
    private var loadedRecordEnd = 0
    private var isPaging = false
    // 列表内左划删除时已本地更新，忽略本次 `records` 变化带来的全量重载
    private var suppressRecordsChangeReload = false
    private var iskFetchInFlight: Set<Int> = []

    /// 行出现时：列表缺总价时拉 zkill；收藏记录中仍缺总价/掉落/摧毁估价时也会拉取并写回本地。
    func requestAsyncISKIfNeeded(for entity: KillMailListEntity) {
        let id = entity.killmailId
        let needsListTotal = entity.zkb.totalValue == nil
        let favoriteNeedsSupplement: Bool = {
            guard KillMailFavoritesStore.shared.isFavorite(killmailId: id),
                  let rec = KillMailFavoritesStore.shared.records.first(where: { $0.killmailId == id })
            else { return false }
            return rec.value == nil || rec.droppedValue == nil || rec.destroyedValue == nil
        }()
        guard needsListTotal || favoriteNeedsSupplement else { return }
        if iskFetchInFlight.contains(id) {
            return
        }
        if needsListTotal, asyncISKByKillmailId[id] != nil {
            return
        }
        iskFetchInFlight.insert(id)
        var loading = iskLoadingKillmailIds
        loading.insert(id)
        iskLoadingKillmailIds = loading

        Task {
            var value: Double = 0
            var persistTotal: Double?
            do {
                let entry = try await zKbToolAPI.shared.fetchZKBKillMailByID(killmailId: id)
                value = entry.zkb.totalValue ?? 0
                persistTotal = entry.zkb.totalValue
                await MainActor.run {
                    KillMailFavoritesStore.shared.updateStoredZkbFieldsIfMissing(
                        killmailId: id,
                        totalValue: entry.zkb.totalValue,
                        droppedValue: entry.zkb.droppedValue,
                        destroyedValue: entry.zkb.destroyedValue
                    )
                }
            } catch {
                Logger.error("收藏夹: 异步估值 zkill 失败 killmail_id=\(id) \(error)")
                value = 0
                persistTotal = nil
            }
            await MainActor.run {
                iskFetchInFlight.remove(id)
                var ld = iskLoadingKillmailIds
                ld.remove(id)
                iskLoadingKillmailIds = ld
                if needsListTotal {
                    var m = asyncISKByKillmailId
                    m[id] = persistTotal ?? value
                    asyncISKByKillmailId = m
                }
            }
        }
    }

    func removeFavoritesFromList(ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        suppressRecordsChangeReload = true
        KillMailFavoritesStore.shared.remove(killmailIds: ids)
        let updated = KillMailFavoritesStore.shared.records
        withAnimation(.easeInOut(duration: 0.28)) {
            applyLocalAfterRemovals(killmailIds: ids, updatedRecords: updated)
        }
    }

    /// 供 `onChange(records)`：若为列表内删除触发的更新则跳过全量 `reloadFromStart`
    func consumeSuppressReloadIfNeeded() -> Bool {
        if suppressRecordsChangeReload {
            suppressRecordsChangeReload = false
            return true
        }
        return false
    }

    private func applyLocalAfterRemovals(killmailIds: Set<Int>, updatedRecords: [FavoriteKillMailRecord]) {
        let oldSnap = recordsSnapshot
        let oldEnd = min(loadedRecordEnd, oldSnap.count)
        let removedInPrefix = oldSnap.prefix(oldEnd).filter { killmailIds.contains($0.killmailId) }.count

        recordsSnapshot = KillMailFavoritesStore.recordsSortedByKillmailId(updatedRecords)
        loadedRecordEnd = min(max(0, oldEnd - removedInPrefix), recordsSnapshot.count)

        entries.removeAll { killmailIds.contains($0.entity.killmailId) }
        entries = entries.map { KillMailEntry(id: $0.entity.killmailId, entity: $0.entity) }

        if !killmailIds.isEmpty {
            var nextISK = asyncISKByKillmailId
            for id in killmailIds {
                nextISK.removeValue(forKey: id)
            }
            asyncISKByKillmailId = nextISK
            var nextLoading = iskLoadingKillmailIds
            for id in killmailIds {
                nextLoading.remove(id)
            }
            iskLoadingKillmailIds = nextLoading
            for id in killmailIds {
                iskFetchInFlight.remove(id)
            }
        }

        hasMore = loadedRecordEnd < recordsSnapshot.count

        if entries.isEmpty, !recordsSnapshot.isEmpty, !isLoading, !isPaging {
            Task { await loadNextPagesUntilBatchFound(isInitial: false) }
        }
    }

    /// 下拉刷新或收藏列表变化：从第一条起重新分页加载
    func reloadFromStart(records: [FavoriteKillMailRecord]) async {
        errorMessage = nil
        recordsSnapshot = KillMailFavoritesStore.recordsSortedByKillmailId(records)
        loadedRecordEnd = 0
        entries = []
        shipInfoMap = [:]
        allianceIconMap = [:]
        corporationIconMap = [:]
        asyncISKByKillmailId = [:]
        iskLoadingKillmailIds = []
        iskFetchInFlight.removeAll()
        hasMore = !records.isEmpty
        guard !records.isEmpty else {
            isLoading = false
            isLoadingMore = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        await loadNextPagesUntilBatchFound(isInitial: true)
    }

    /// 仅同步分页快照中的 `value`，避免异步回填总价触发整表 `reloadFromStart`。
    func syncRecordsSnapshotFromStore(_ storeRecords: [FavoriteKillMailRecord]) {
        guard KillMailFavoritesStore.listIdentityIgnoringValue(recordsSnapshot)
            == KillMailFavoritesStore.listIdentityIgnoringValue(storeRecords) else { return }
        recordsSnapshot = KillMailFavoritesStore.recordsSortedByKillmailId(storeRecords)
    }

    /// 列表滑到底附近时由最后一行 `onAppear` 触发
    func loadMoreIfNeeded() async {
        guard hasMore, !isLoading, !isLoadingMore, !isPaging else { return }
        await loadNextPagesUntilBatchFound(isInitial: false)
    }

    /// 连续消费空批直至拿到实体或耗尽记录，避免首屏全失败时无法继续
    private func loadNextPagesUntilBatchFound(isInitial: Bool) async {
        guard loadedRecordEnd < recordsSnapshot.count else {
            hasMore = false
            return
        }
        isPaging = true
        if !isInitial {
            isLoadingMore = true
        }
        defer {
            isPaging = false
            isLoadingMore = false
            hasMore = loadedRecordEnd < recordsSnapshot.count
        }

        var accumulated: [KillMailListEntity] = []
        do {
            while loadedRecordEnd < recordsSnapshot.count {
                let start = loadedRecordEnd
                let end = min(start + pageSize, recordsSnapshot.count)
                let slice = Array(recordsSnapshot[start ..< end])
                loadedRecordEnd = end

                let batch = try await fetchListEntities(for: slice)
                accumulated.append(contentsOf: batch)
                if !batch.isEmpty {
                    break
                }
            }

            guard !accumulated.isEmpty else { return }

            let merged = (entries.map(\.entity) + accumulated).sorted {
                $0.killmailId > $1.killmailId
            }
            entries = merged.map { KillMailEntry(id: $0.killmailId, entity: $0) }

            mergeShipInfo(for: accumulated)
            let (aIcons, cIcons) = await loadOrganizationIcons(for: accumulated)
            var aMap = allianceIconMap
            var cMap = corporationIconMap
            for (k, v) in aIcons {
                aMap[k] = v
            }
            for (k, v) in cIcons {
                cMap[k] = v
            }
            allianceIconMap = aMap
            corporationIconMap = cMap
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeShipInfo(for newEntities: [KillMailListEntity]) {
        let missing = Set(newEntities.map(\.shipTypeId)).filter { shipInfoMap[$0] == nil }
        guard !missing.isEmpty else { return }
        let fetched = getShipInfo(for: Array(missing))
        var map = shipInfoMap
        for (k, v) in fetched {
            map[k] = v
        }
        shipInfoMap = map
    }

    /// 将若干条收藏记录转为列表实体（与原先整表 `reload` 逻辑一致，仅作用域为当前切片）
    private func fetchListEntities(for records: [FavoriteKillMailRecord]) async throws -> [KillMailListEntity] {
        guard !records.isEmpty else { return [] }

        var idToEntry: [Int: ZKBKillMailEntry] = [:]
        for rec in records {
            let trimmed = rec.hash.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                idToEntry[rec.killmailId] = ZKBKillMailEntry(
                    killmailId: rec.killmailId,
                    storedHash: trimmed,
                    storedTotalValue: rec.value,
                    storedDroppedValue: rec.droppedValue,
                    storedDestroyedValue: rec.destroyedValue
                )
            }
        }

        let idsNeedingZkill = Set(
            records
                .filter { $0.hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map(\.killmailId)
        )
        await withTaskGroup(of: (Int, ZKBKillMailEntry?).self) { group in
            for id in idsNeedingZkill {
                group.addTask {
                    do {
                        let e = try await zKbToolAPI.shared.fetchZKBKillMailByID(killmailId: id)
                        return (id, e)
                    } catch {
                        Logger.error("收藏夹: 拉取 zkill 失败 killmail_id=\(id) \(error)")
                        return (id, nil)
                    }
                }
            }
            for await (id, zkb) in group {
                if let zkb {
                    idToEntry[id] = zkb
                }
            }
        }

        let orderedZKB: [ZKBKillMailEntry] = records.compactMap { idToEntry[$0.killmailId] }
        guard !orderedZKB.isEmpty else { return [] }

        var entities = try await KillMailDataConverter.shared.fetchKillMailListEntities(zkbEntries: orderedZKB)

        let idsSucceeded = Set(entities.map(\.killmailId))
        let idsAttempted = Set(orderedZKB.map(\.killmail_id))
        var retryIds = idsAttempted.subtracting(idsSucceeded)
        let idsNeverLoaded = Set(records.map(\.killmailId)).filter { idToEntry[$0] == nil }
        retryIds.formUnion(idsNeverLoaded)

        if !retryIds.isEmpty {
            var refreshedById: [Int: ZKBKillMailEntry] = [:]
            await withTaskGroup(of: (Int, ZKBKillMailEntry?).self) { group in
                for id in retryIds {
                    group.addTask {
                        do {
                            let e = try await zKbToolAPI.shared.fetchZKBKillMailByID(killmailId: id)
                            return (id, e)
                        } catch {
                            Logger.error("收藏夹: 二次拉取 zkill 失败 killmail_id=\(id) \(error)")
                            return (id, nil)
                        }
                    }
                }
                for await (id, zkb) in group {
                    if let zkb {
                        idToEntry[id] = zkb
                        refreshedById[id] = zkb
                    }
                }
            }

            var fallbackZKB: [ZKBKillMailEntry] = []
            for rec in records {
                guard retryIds.contains(rec.killmailId),
                      let e = refreshedById[rec.killmailId]
                else { continue }
                fallbackZKB.append(e)
            }
            if !fallbackZKB.isEmpty {
                let more = try await KillMailDataConverter.shared.fetchKillMailListEntities(zkbEntries: fallbackZKB)
                entities.append(contentsOf: more)
            }
        }

        for rec in records {
            guard let e = idToEntry[rec.killmailId] else { continue }
            let z = e.zkb
            KillMailFavoritesStore.shared.updateStoredZkbFieldsIfMissing(
                killmailId: rec.killmailId,
                totalValue: z.totalValue,
                droppedValue: z.droppedValue,
                destroyedValue: z.destroyedValue
            )
        }

        return entities.sorted { $0.killmailId > $1.killmailId }
    }

    private func getShipInfo(for typeIds: [Int]) -> [Int: (name: String, iconFileName: String)] {
        var infoMap: [Int: (name: String, iconFileName: String)] = [:]
        for typeId in typeIds {
            if let info = SDEMemoryStore.type(for: typeId) {
                infoMap[typeId] = (name: info.name, iconFileName: info.iconFilename)
            }
        }
        return infoMap
    }

    private func loadOrganizationIcons(for entities: [KillMailListEntity]) async -> (
        [Int: UIImage], [Int: UIImage]
    ) {
        var allianceIcons: [Int: UIImage] = [:]
        var corporationIcons: [Int: UIImage] = [:]

        for entity in entities {
            if let allyId = entity.allianceId, allyId > 0 {
                if allianceIcons[allyId] == nil,
                   let icon = await loadSingleOrganizationIcon(type: "alliance", id: allyId)
                {
                    allianceIcons[allyId] = icon
                }
            } else if entity.corporationId > 0 {
                let corpId = entity.corporationId
                if corporationIcons[corpId] == nil,
                   let icon = await loadSingleOrganizationIcon(type: "corporation", id: corpId)
                {
                    corporationIcons[corpId] = icon
                }
            }
        }

        return (allianceIcons, corporationIcons)
    }

    private func loadSingleOrganizationIcon(type: String, id: Int) async -> UIImage? {
        do {
            switch type {
            case "alliance":
                return try await AllianceAPI.shared.fetchAllianceLogo(allianceID: id, size: 64)
            case "corporation":
                return try await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: id, size: 64
                )
            default:
                return nil
            }
        } catch {
            Logger.error("收藏夹: 加载\(type)图标失败 ID=\(id) \(error)")
            return nil
        }
    }
}

struct BRKillMailFavoritesView: View {
    let characterId: Int
    let eveCharacter: EVECharacterInfo?

    @ObservedObject private var favoritesStore = KillMailFavoritesStore.shared
    @StateObject private var listModel = KillMailFavoritesListModel()
    /// 与「我的战斗记录」一致：仅首次进入本页时拉取列表，从详情返回不重复请求
    @State private var hasLoadedFavoritesList = false

    var body: some View {
        favoritesList
            .navigationTitle(NSLocalizedString("KillMail_Favorites_Title", comment: ""))
            .refreshable {
                await listModel.reloadFromStart(records: favoritesStore.records)
            }
            .onAppear {
                guard !hasLoadedFavoritesList else { return }
                hasLoadedFavoritesList = true
                Task {
                    await listModel.reloadFromStart(records: favoritesStore.records)
                }
            }
            .onChange(of: favoritesStore.records) { oldRecords, newRecords in
                if listModel.consumeSuppressReloadIfNeeded() {
                    return
                }
                if KillMailFavoritesStore.listIdentityIgnoringValue(oldRecords)
                    == KillMailFavoritesStore.listIdentityIgnoringValue(newRecords)
                {
                    listModel.syncRecordsSnapshotFromStore(newRecords)
                    return
                }
                Task {
                    await listModel.reloadFromStart(records: newRecords)
                }
            }
    }

    private var favoritesList: some View {
        List {
            favoritesListContents
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.28), value: listModel.entries.count)
    }

    @ViewBuilder
    private var favoritesListContents: some View {
        if listModel.isLoading, favoritesStore.records.isEmpty == false, listModel.entries.isEmpty {
            Section {
                ForEach(0 ..< 6, id: \.self) { _ in
                    ListSkeletonRow.killMail
                }
            } header: {
                favoritesCountHeader
            }
        } else if let err = listModel.errorMessage {
            Text(err)
                .foregroundColor(.red)
        } else if favoritesStore.records.isEmpty {
            Text(NSLocalizedString("KillMail_Favorites_Empty", comment: ""))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else if listModel.entries.isEmpty {
            Section {
                Text(NSLocalizedString("KillMail_Favorites_Load_Failed", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } header: {
                favoritesCountHeader
            }
        } else {
            favoritesEntriesSection
        }
    }

    private var favoritesEntriesSection: some View {
        Section {
            ForEach(listModel.entries) { entry in
                favoritesRow(for: entry)
            }
            .onDelete(perform: removeFavoritesAtIndexes)

            if listModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .listRowSeparator(.hidden, edges: .all)
            }
        } header: {
            favoritesCountHeader
        }
    }

    private func favoritesRow(for entry: KillMailEntry) -> some View {
        let entity = entry.entity
        let shipInfo = listModel.shipInfoMap[entity.shipTypeId] ?? (
            name: String(
                format: NSLocalizedString("KillMail_Unknown_Item", comment: ""),
                entity.shipTypeId
            ),
            iconFileName: IconManager.defaultItemIcon
        )
        return BRKillMailCell(
            entity: entity,
            shipInfo: shipInfo,
            allianceIcon: entity.allianceId.flatMap { listModel.allianceIconMap[$0] },
            corporationIcon: listModel.corporationIconMap[entity.corporationId],
            characterId: characterId,
            searchResult: nil,
            character: eveCharacter,
            asyncTotalValue: listModel.asyncISKByKillmailId[entity.killmailId],
            isAsyncTotalValueLoading: entity.zkb.totalValue == nil
                && listModel.iskLoadingKillmailIds.contains(entity.killmailId)
        )
        .onAppear {
            listModel.requestAsyncISKIfNeeded(for: entity)
            if entity.killmailId == listModel.entries.last?.entity.killmailId {
                Task { await listModel.loadMoreIfNeeded() }
            }
        }
    }

    private func removeFavoritesAtIndexes(_ indexSet: IndexSet) {
        let ids = indexSet.compactMap { index -> Int? in
            guard listModel.entries.indices.contains(index) else { return nil }
            return listModel.entries[index].entity.killmailId
        }
        listModel.removeFavoritesFromList(ids: Set(ids))
    }

    /// 分组表头右侧：收藏总数，小字号
    private var favoritesCountHeader: some View {
        HStack {
            Spacer(minLength: 0)
            Text("(\(favoritesStore.records.count))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
    }
}
