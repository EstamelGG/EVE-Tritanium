import SwiftUI

enum KillMailFilter: String {
    case all
    case kill
    case loss
}

struct KillMailEntry: Identifiable {
    let id: Int
    let entity: KillMailListEntity
}

class KillMailViewModel: ObservableObject {
    @Published private(set) var killMails: [KillMailEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @Published private(set) var allianceIconMap: [Int: UIImage] = [:]
    @Published private(set) var corporationIconMap: [Int: UIImage] = [:]
    @Published private(set) var characterStats: CharBattleIsk?
    @Published private(set) var hasMoreData = true // 是否还有更多数据可加载

    private var cachedData: [KillMailFilter: CachedKillMailData] = [:]
    private let characterId: Int
    let kbAPI = zKbToolAPI.shared
    private var currentIndex = 0

    /// 为每个 filter 维护分页状态
    private struct FilterPaginationState {
        var currentZKBPage: Int = 1 // 当前 zkillboard API 页码
        var pendingZKBEntries: [ZKBKillMailEntry] = [] // 待转换的原始数据
        var convertedKillmailIds: Set<Int> = [] // 已转换的 killmail ID（用于去重）
        var hasMore: Bool = true // 是否还有更多数据
    }

    private var paginationState: [KillMailFilter: FilterPaginationState] = [
        .all: FilterPaginationState(),
        .kill: FilterPaginationState(),
        .loss: FilterPaginationState(),
    ]
    private let fileManager = FileManager.default
    private var cacheDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let kbDirectory = documentsPath.appendingPathComponent("kb")
        try? fileManager.createDirectory(at: kbDirectory, withIntermediateDirectories: true)
        return kbDirectory
    }

    struct CachedKillMailData {
        let mails: [KillMailEntry]
        let shipInfo: [Int: (name: String, iconFileName: String)]
        let allianceIcons: [Int: UIImage]
        let corporationIcons: [Int: UIImage]
    }

    init(characterId: Int) {
        self.characterId = characterId
    }

    private func getCacheFilePath(for type: String) -> URL {
        return cacheDirectory.appendingPathComponent("\(type)_\(characterId).json")
    }

    private struct ListCacheWrapper: Codable {
        let data: [KillMailListEntity]
        let updateTime: TimeInterval
    }

    private func saveToCache(_ entities: [KillMailListEntity], for type: String, filter: KillMailFilter = .all) {
        let cacheKey = "\(type)_\(filter.rawValue)"
        let filePath = getCacheFilePath(for: cacheKey)
        let wrapper = ListCacheWrapper(data: entities, updateTime: Date().timeIntervalSince1970)
        do {
            let jsonData = try JSONEncoder().encode(wrapper)
            try jsonData.write(to: filePath)
            Logger.info("保存到缓存文件: \(filePath)")
        } catch {
            Logger.error("保存缓存失败: \(error)")
        }
    }

    private func loadFromCache(for type: String, filter: KillMailFilter = .all) -> [KillMailListEntity]? {
        let cacheKey = "\(type)_\(filter.rawValue)"
        let filePath = getCacheFilePath(for: cacheKey)
        guard let data = try? Data(contentsOf: filePath),
              let wrapper = try? JSONDecoder().decode(ListCacheWrapper.self, from: data)
        else { return nil }
        let cacheAge = Date().timeIntervalSince1970 - wrapper.updateTime
        if cacheAge > 3600 {
            try? fileManager.removeItem(at: filePath)
            return nil
        }
        Logger.info("从缓存加载文件: \(filePath)")
        return wrapper.data
    }

    private func saveToCache(_ dict: [String: Any], for type: String) {
        let filePath = getCacheFilePath(for: type)
        var data = dict
        data["update_time"] = Date().timeIntervalSince1970
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
            try jsonData.write(to: filePath)
        } catch {
            Logger.error("保存缓存失败: \(error)")
        }
    }

    private func loadDictFromCache(for type: String) -> [String: Any]? {
        let filePath = getCacheFilePath(for: type)
        guard let data = try? Data(contentsOf: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updateTime = dict["update_time"] as? TimeInterval
        else { return nil }
        if Date().timeIntervalSince1970 - updateTime > 3600 {
            try? fileManager.removeItem(at: filePath)
            return nil
        }
        return dict
    }

    private func convertToEntries(_ entities: [KillMailListEntity]) -> [KillMailEntry] {
        return entities.map { entity in
            defer { currentIndex += 1 }
            return KillMailEntry(id: currentIndex, entity: entity)
        }
    }

    func loadDataIfNeeded(for filter: KillMailFilter) async {
        // 切换过滤器时，先检查内存缓存，如果有就直接使用，避免重新加载
        let hasCached = await MainActor.run {
            if let cached = self.cachedData[filter] {
                // 直接从内存缓存读取，不需要重新加载
                self.killMails = cached.mails
                self.shipInfoMap = cached.shipInfo
                self.allianceIconMap = cached.allianceIcons
                self.corporationIconMap = cached.corporationIcons
                self.hasMoreData = true
                return true
            }
            return false
        }

        // 如果有内存缓存，直接返回，不需要加载
        if hasCached {
            return
        }

        // 如果没有内存缓存，重置分页状态并加载数据
        await MainActor.run {
            self.paginationState[filter] = FilterPaginationState()
            self.killMails = []
            self.hasMoreData = true
        }

        await loadData(for: filter)
    }

    private func loadData(for filter: KillMailFilter, forceRefresh: Bool = false, updateUI: Bool = true) async {
        guard characterId > 0 else {
            await MainActor.run {
                errorMessage = String(
                    format: NSLocalizedString("KillMail_Invalid_Character_ID", comment: ""),
                    characterId
                )
                isLoading = false
            }
            return
        }

        // 如果不是强制刷新，先尝试从缓存文件加载
        if !forceRefresh {
            if let cachedEntities = loadFromCache(for: "km", filter: filter) {
                let entries = convertToEntries(cachedEntities)
                let shipIds = cachedEntities.map(\.shipTypeId)
                let shipInfo = getShipInfo(for: shipIds)
                let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: cachedEntities)

                let cachedKillMailData = CachedKillMailData(
                    mails: entries,
                    shipInfo: shipInfo,
                    allianceIcons: allianceIcons,
                    corporationIcons: corporationIcons
                )

                await MainActor.run {
                    self.cachedData[filter] = cachedKillMailData
                    if updateUI {
                        self.killMails = entries
                    }
                    self.shipInfoMap.merge(shipInfo) { current, _ in current }
                    self.allianceIconMap.merge(allianceIcons) { current, _ in current }
                    self.corporationIconMap.merge(corporationIcons) { current, _ in current }
                    self.hasMoreData = true
                    if updateUI {
                        self.isLoading = false
                    }
                }

                Logger.debug("从缓存文件加载数据成功 - filter: \(filter)")
                return
            }
        }

        // 前台加载（含强制刷新）显示加载态；后台静默刷新其他筛选不影响当前 UI
        if updateUI {
            await MainActor.run { isLoading = true }
        }

        do {
            // 获取分页状态（在主线程上）
            // 如果是强制刷新，状态已经在 refreshData 中重置了
            var state = await MainActor.run {
                if let existing = self.paginationState[filter] {
                    return existing
                } else {
                    let newState = FilterPaginationState()
                    self.paginationState[filter] = newState
                    return newState
                }
            }

            // 强制刷新时，或者待转换数据为空时，从 zkillboard API 获取第一页
            if forceRefresh || state.pendingZKBEntries.isEmpty {
                Logger.debug("从 zkillboard 获取第一页数据 - filter: \(filter), forceRefresh: \(forceRefresh)")
                // 强制刷新时，从第一页开始获取
                let pageToFetch = forceRefresh ? 1 : state.currentZKBPage
                let zkbEntries = try await kbAPI.fetchZKBCharacterKillMails(
                    characterId: characterId,
                    page: pageToFetch,
                    filter: filter
                )

                if zkbEntries.isEmpty {
                    // 没有数据了
                    state.hasMore = false
                    // 复制 state 以避免并发访问问题
                    let finalState = state
                    await MainActor.run {
                        self.killMails = []
                        self.hasMoreData = false
                        self.isLoading = false
                        // 在主线程上更新 paginationState
                        self.paginationState[filter] = finalState
                    }
                    return
                }

                state.pendingZKBEntries = zkbEntries
                // 强制刷新时，从第1页开始，所以下一页是第2页；否则继续递增
                state.currentZKBPage = forceRefresh ? 2 : (state.currentZKBPage + 1)
            }

            // 只转换前10个（去重）
            let batchSize = 10
            var entriesToConvert: [ZKBKillMailEntry] = []
            var remainingEntries: [ZKBKillMailEntry] = []

            for entry in state.pendingZKBEntries {
                if entriesToConvert.count < batchSize, !state.convertedKillmailIds.contains(entry.killmail_id) {
                    entriesToConvert.append(entry)
                    state.convertedKillmailIds.insert(entry.killmail_id)
                } else {
                    remainingEntries.append(entry)
                }
            }

            state.pendingZKBEntries = remainingEntries

            // 如果转换的数据不足10个，且还有更多页，尝试加载下一页
            if entriesToConvert.count < batchSize, state.hasMore {
                Logger.debug("当前页数据不足10个，尝试加载下一页")
                let nextPageEntries = try await kbAPI.fetchZKBCharacterKillMails(
                    characterId: characterId,
                    page: state.currentZKBPage,
                    filter: filter
                )

                if nextPageEntries.isEmpty {
                    state.hasMore = false
                } else {
                    state.pendingZKBEntries.append(contentsOf: nextPageEntries)
                    state.currentZKBPage += 1

                    // 从新加载的数据中补齐到10个
                    for entry in state.pendingZKBEntries {
                        if entriesToConvert.count >= batchSize {
                            break
                        }
                        if !state.convertedKillmailIds.contains(entry.killmail_id) {
                            entriesToConvert.append(entry)
                            state.convertedKillmailIds.insert(entry.killmail_id)
                        }
                    }

                    // 更新剩余数据
                    state.pendingZKBEntries = state.pendingZKBEntries.filter { entry in
                        !state.convertedKillmailIds.contains(entry.killmail_id) || entriesToConvert.contains(where: { $0.killmail_id == entry.killmail_id })
                    }
                }
            }

            // 如果最终转换的数据仍不足10个，说明没有更多数据了
            if entriesToConvert.count < batchSize {
                state.hasMore = false
            }

            let entities = try await KillMailDataConverter.shared.fetchKillMailListEntities(
                zkbEntries: entriesToConvert
            )

            let entries = convertToEntries(entities)
            let shipIds = entities.map(\.shipTypeId)
            let shipInfo = getShipInfo(for: shipIds)
            let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: entities)

            let cachedData = CachedKillMailData(
                mails: entries,
                shipInfo: shipInfo,
                allianceIcons: allianceIcons,
                corporationIcons: corporationIcons
            )

            // 在 MainActor 闭包外获取需要的值
            let hasMore = state.hasMore
            // 复制 state 以避免并发访问问题
            let finalState = state

            await MainActor.run {
                self.cachedData[filter] = cachedData
                if updateUI {
                    self.killMails = entries
                }
                self.shipInfoMap.merge(shipInfo) { current, _ in current }
                self.allianceIconMap.merge(allianceIcons) { current, _ in current }
                self.corporationIconMap.merge(corporationIcons) { current, _ in current }
                self.hasMoreData = hasMore
                if updateUI {
                    self.isLoading = false
                }
                // 在主线程上更新 paginationState
                self.paginationState[filter] = finalState
            }

            saveToCache(entities, for: "km", filter: filter)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func refreshData(for filter: KillMailFilter, updateUI: Bool = true) async {
        // 强制刷新：重置分页状态，清空列表，就像重新进入页面一样
        await MainActor.run {
            self.paginationState[filter] = FilterPaginationState()
            if updateUI {
                self.killMails = []
                // 与清空单帧同步置位，避免闪现「暂无战斗记录」
                self.isLoading = true
            }
            self.hasMoreData = true
        }

        // 重新加载数据（不使用缓存，强制从 zkillboard API 获取）
        await loadData(for: filter, forceRefresh: true, updateUI: updateUI)
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
            Logger.error("加载\(type)图标失败 - ID: \(id), 错误: \(error)")
            return nil
        }
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

    func loadStats(forceRefresh: Bool = false) async {
        if !forceRefresh, characterStats != nil {
            return
        }

        if !forceRefresh {
            await MainActor.run { isLoading = true }
        }

        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh, let cachedData = loadDictFromCache(for: "stats"),
           let stats = try? JSONDecoder().decode(
               CharBattleIsk.self, from: try JSONSerialization.data(withJSONObject: cachedData)
           )
        {
            await MainActor.run {
                self.characterStats = stats
                if self.killMails.isEmpty {
                    self.isLoading = false
                }
            }
            return
        }

        do {
            let stats = try await ZKillMailsAPI.shared.fetchCharacterStats(characterId: characterId)
            // 保存到缓存
            if let jsonData = try? JSONEncoder().encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            {
                saveToCache(dict, for: "stats")
            }

            await MainActor.run {
                self.characterStats = stats
                if self.killMails.isEmpty {
                    self.isLoading = false
                }
            }
        } catch {
            Logger.error(
                String(
                    format: NSLocalizedString("KillMail_Stats_Failed", comment: ""),
                    error.localizedDescription
                )
            )
            await MainActor.run {
                if self.killMails.isEmpty {
                    self.isLoading = false
                }
            }
        }
    }

    func loadMoreData(for filter: KillMailFilter = .all) async {
        guard !isLoadingMore, hasMoreData else { return }

        await MainActor.run { isLoadingMore = true }

        do {
            // 在主线程上获取状态
            var state = await MainActor.run {
                self.paginationState[filter] ?? FilterPaginationState()
            }
            let batchSize = 10

            // 从待转换数据中取10个（去重）
            var entriesToConvert: [ZKBKillMailEntry] = []
            var remainingEntries: [ZKBKillMailEntry] = []

            for entry in state.pendingZKBEntries {
                if entriesToConvert.count < batchSize, !state.convertedKillmailIds.contains(entry.killmail_id) {
                    entriesToConvert.append(entry)
                    state.convertedKillmailIds.insert(entry.killmail_id)
                } else {
                    remainingEntries.append(entry)
                }
            }

            state.pendingZKBEntries = remainingEntries

            // 如果不足10个，尝试加载下一页
            if entriesToConvert.count < batchSize, state.hasMore {
                Logger.debug("加载更多：当前页数据不足10个，尝试加载下一页 - page: \(state.currentZKBPage)")
                let nextPageEntries = try await kbAPI.fetchZKBCharacterKillMails(
                    characterId: characterId,
                    page: state.currentZKBPage,
                    filter: filter
                )

                if nextPageEntries.isEmpty {
                    state.hasMore = false
                } else {
                    state.pendingZKBEntries.append(contentsOf: nextPageEntries)
                    state.currentZKBPage += 1

                    // 从新加载的数据中补齐到10个
                    var tempRemaining: [ZKBKillMailEntry] = []
                    for entry in state.pendingZKBEntries {
                        if entriesToConvert.count >= batchSize {
                            tempRemaining.append(entry)
                        } else if !state.convertedKillmailIds.contains(entry.killmail_id) {
                            entriesToConvert.append(entry)
                            state.convertedKillmailIds.insert(entry.killmail_id)
                        } else {
                            tempRemaining.append(entry)
                        }
                    }
                    state.pendingZKBEntries = tempRemaining
                }
            }

            // 如果最终转换的数据仍不足10个，说明没有更多数据了
            if entriesToConvert.count < batchSize {
                state.hasMore = false
            }

            let entities = try await KillMailDataConverter.shared.fetchKillMailListEntities(
                zkbEntries: entriesToConvert
            )

            let entries = convertToEntries(entities)
            let shipIds = entities.map(\.shipTypeId)
            let newShipInfo = getShipInfo(for: shipIds)
            let (newAllianceIcons, newCorporationIcons) = await loadOrganizationIcons(for: entities)

            // 在 MainActor 闭包外获取需要的值
            let hasMore = state.hasMore
            // 复制 state 以避免并发访问问题
            let finalState = state

            await MainActor.run {
                killMails.append(contentsOf: entries)
                shipInfoMap.merge(newShipInfo) { current, _ in current }
                allianceIconMap.merge(newAllianceIcons) { current, _ in current }
                corporationIconMap.merge(newCorporationIcons) { current, _ in current }
                hasMoreData = hasMore
                isLoadingMore = false
                // 在主线程上更新 paginationState
                self.paginationState[filter] = finalState
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingMore = false
            }
        }
    }

    /// 预加载所有过滤器的数据
    func preloadAllFilterData() async {
        await MainActor.run { isLoading = true }

        // 使用任务组并行加载所有过滤器数据
        await withTaskGroup(of: Void.self) { group in
            for filter in [KillMailFilter.all, KillMailFilter.kill, KillMailFilter.loss] {
                if cachedData[filter] == nil {
                    group.addTask {
                        await self.loadData(for: filter)
                    }
                }
            }
        }

        // 加载完成后，如果当前选择的过滤器有缓存数据，就显示它
        if let cached = cachedData[.all] {
            await MainActor.run {
                killMails = cached.mails
                shipInfoMap = cached.shipInfo
                allianceIconMap = cached.allianceIcons
                corporationIconMap = cached.corporationIcons
                isLoading = false
            }
        }
    }

    func refreshStats() async {
        // 不要立即设置isLoading=true，保持现有UI状态

        do {
            let stats = try await ZKillMailsAPI.shared.fetchCharacterStats(characterId: characterId)
            // 保存到缓存
            if let jsonData = try? JSONEncoder().encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            {
                saveToCache(dict, for: "stats")
            }

            await MainActor.run {
                self.characterStats = stats
            }
        } catch {
            Logger.error(
                String(
                    format: NSLocalizedString("KillMail_Stats_Failed", comment: ""),
                    error.localizedDescription
                )
            )
        }
    }
}

struct BRKillMailView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailViewModel
    @State private var selectedFilter: KillMailFilter = .all
    @State private var isLoading = false
    @State private var hasInitialized = false // 跟踪是否已执行初始加载

    /// 获取当前角色信息
    private var character: EVECharacterInfo? {
        EVELogin.shared.getCharacterByID(characterId)?.character
    }

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailViewModel(characterId: characterId))
    }

    /// 执行初始数据加载，但只在第一次调用时执行
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized, !isLoading else { return }

        hasInitialized = true
        isLoading = true

        Task {
            // 创建一个任务组，同时加载战斗统计信息和所有过滤器的战斗记录
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await viewModel.loadStats()
                }

                group.addTask {
                    await viewModel.preloadAllFilterData()
                }
            }

            // 所有任务完成后重置isLoading
            isLoading = false
        }
    }

    var body: some View {
        List {
            // 战斗统计信息
            Section {
                if let stats = viewModel.characterStats {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("KillMail_Destroyed_Value", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatISK(stats.iskDestroyed))
                            .foregroundColor(.green)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.red)
                        Text(NSLocalizedString("KillMail_Lost_Value", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatISK(stats.iskLost))
                            .foregroundColor(.red)
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            // 搜索入口与收藏夹
            Section {
                NavigationLink(destination: BRKillMailSearchView(characterId: characterId)) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("KillMail_Search_Title", comment: ""))
                    }
                }
                NavigationLink(destination: BRKillMailFavoritesView(characterId: characterId, eveCharacter: character)) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(NSLocalizedString("KillMail_Favorites_Link", comment: ""))
                    }
                }
            }

            // 战斗记录列表
            Section(header: Text(NSLocalizedString("KillMail_Battle_Records", comment: ""))) {
                Picker(
                    NSLocalizedString("KillMail_Filter", comment: ""), selection: $selectedFilter
                ) {
                    Text(NSLocalizedString("KillMail_Filter_All", comment: "")).tag(
                        KillMailFilter.all
                    )
                    Text(NSLocalizedString("KillMail_Filter_Kills", comment: "")).tag(
                        KillMailFilter.kill
                    )
                    Text(NSLocalizedString("KillMail_Filter_Losses", comment: "")).tag(
                        KillMailFilter.loss
                    )
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)
                .onChange(of: selectedFilter) { _, newValue in
                    Task {
                        await viewModel.loadDataIfNeeded(for: newValue)
                    }
                }

                if isLoading || viewModel.isLoading {
                    ForEach(0 ..< 6, id: \.self) { _ in
                        ListSkeletonRow.killMail
                    }
                } else if viewModel.killMails.isEmpty {
                    Text(NSLocalizedString("KillMail_No_Records", comment: ""))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.killMails) { entry in
                        let entity = entry.entity
                        let shipInfo = viewModel.shipInfoMap[entity.shipTypeId] ?? (
                            name: String(
                                format: NSLocalizedString("KillMail_Unknown_Item", comment: ""),
                                entity.shipTypeId
                            ),
                            iconFileName: IconManager.defaultItemIcon
                        )
                        BRKillMailCell(
                            entity: entity,
                            shipInfo: shipInfo,
                            allianceIcon: entity.allianceId.flatMap { viewModel.allianceIconMap[$0] },
                            corporationIcon: viewModel.corporationIconMap[entity.corporationId],
                            characterId: characterId,
                            searchResult: nil,
                            character: character
                        )
                    }

                    // 加载更多按钮
                    if viewModel.hasMoreData {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMore {
                                ProgressView()
                            } else {
                                Button(action: {
                                    Task {
                                        await viewModel.loadMoreData(for: selectedFilter)
                                    }
                                }) {
                                    Text(NSLocalizedString("KillMail_Load_More", comment: ""))
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("KillMail_View_Title", comment: ""))
        .refreshable {
            // 刷新战斗统计和所有三个子页面的战斗记录
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await viewModel.refreshStats()
                }
                // 刷新当前选中的类别，并更新UI
                group.addTask {
                    await viewModel.refreshData(for: selectedFilter, updateUI: true)
                }
                // 并行刷新其他两个类别，只更新缓存，不更新UI
                for filter in [KillMailFilter.all, KillMailFilter.kill, KillMailFilter.loss] {
                    if filter != selectedFilter {
                        group.addTask {
                            await viewModel.refreshData(for: filter, updateUI: false)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadInitialDataIfNeeded()
        }
    }
}

private func formatKillMailTime(_ timestamp: Int) -> String {
    FormatUtil.formatDateToLocalTime(Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

struct BRKillMailCell: View {
    let entity: KillMailListEntity
    let shipInfo: (name: String, iconFileName: String)
    let allianceIcon: UIImage?
    let corporationIcon: UIImage?
    let characterId: Int
    let searchResult: SearchResult?
    let character: EVECharacterInfo?
    // 收藏夹：ESI 先出列后，zkill 估值异步写入；未就绪且 `isAsyncTotalValueLoading` 时显示指示器
    var asyncTotalValue: Double? = nil
    var isAsyncTotalValueLoading: Bool = false

    // 与 12pt medium monospaced 数值行高对齐，避免加载指示器 ↔ 文本切换时上下跳变
    private static let valueRowHeight: CGFloat = 20
    private static let valueMinWidth: CGFloat = 92

    @ViewBuilder
    private var totalValueView: some View {
        let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
        ZStack(alignment: .trailing) {
            if entity.zkb.totalValue != nil {
                Text(FormatUtil.formatISK(entity.totalValue))
                    .font(mono)
                    .foregroundColor(valueColor)
                    .lineLimit(1)
            } else if isAsyncTotalValueLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(valueColor)
            } else if let asyncTotalValue {
                Text(FormatUtil.formatISK(asyncTotalValue))
                    .font(mono)
                    .foregroundColor(valueColor)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(mono)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: Self.valueMinWidth, minHeight: Self.valueRowHeight, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var isLoss: Bool {
        if let searchResult = searchResult {
            switch searchResult.category {
            case .character: return entity.characterId == searchResult.id
            case .corporation: return entity.corporationId == searchResult.id
            case .alliance: return entity.allianceId == searchResult.id
            case .inventory_type: return entity.shipTypeId == searchResult.id
            default: return false
            }
        }
        return entity.characterId == characterId
    }

    private var valueColor: Color {
        isLoss ? .red : .green
    }

    private var organizationIcon: UIImage? {
        if let allyId = entity.allianceId, allyId > 0, let icon = allianceIcon {
            return icon
        }
        if entity.corporationId > 0, let icon = corporationIcon {
            return icon
        }
        return nil
    }

    private var locationText: Text {
        let sys = entity.system
        let sec = sys?.security ?? 0
        let securityText = Text(formatSystemSecurity(sec))
            .foregroundColor(getSecurityColor(sec))
            .font(.system(size: 12, weight: .medium))
        let systemName = Text(" \(sys?.systemName ?? NSLocalizedString("Unknown", comment: ""))")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
        let regionText = Text(" / \(sys?.regionName ?? NSLocalizedString("Unknown", comment: ""))")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        return securityText + systemName + regionText
    }

    var body: some View {
        NavigationLink(destination: BRKillMailDetailView(listEntity: entity, character: character)) {
            VStack(alignment: .leading, spacing: 8) {
                // 第一行：图标和信息
                HStack(spacing: 12) {
                    // 左侧飞船图标
                    IconManager.shared.loadImage(for: shipInfo.iconFileName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // 右侧信息
                    VStack(alignment: .leading, spacing: 2) {
                        // 飞船名称
                        Text(shipInfo.name)
                            .font(.system(size: 16, weight: .medium))

                        // 显示名称（角色/联盟/军团）
                        Text(entity.displayName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        // 位置信息
                        locationText
                    }

                    Spacer()

                    // 右侧组织图标
                    if let icon = organizationIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                    }
                }

                // 第二行：时间和价值
                HStack {
                    Text(formatKillMailTime(entity.timestamp))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Spacer()

                    totalValueView
                }
            }
        }
        .buttonStyle(.plain)
    }
}
