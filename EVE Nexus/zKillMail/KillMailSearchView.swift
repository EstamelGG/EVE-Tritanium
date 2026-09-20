import SwiftUI

// MARK: - 关键词搜索历史（键盘「搜索」提交且至少命中一条结果时写入）

private enum KillMailKeywordSearchHistory {
    private static let userDefaultsKey = "KillMailKeywordSearchHistory.v1"
    private static let maxCount = 20

    private struct Entry: Codable, Equatable {
        let keyword: String
        let timestamp: TimeInterval
    }

    private static func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }

    private static func saveEntries(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    /// 最近关键词，从新到旧，最多 20 条
    static func recentKeywords() -> [String] {
        loadEntries()
            .sorted { $0.timestamp > $1.timestamp }
            .map(\.keyword)
    }

    /// 记录一次搜索（去重后按时间置顶，截断为 20）。应在确认有搜索结果后调用。
    static func recordSearchSubmission(_ raw: String) {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        var entries = loadEntries()
        entries.removeAll { $0.keyword == keyword }
        entries.append(Entry(keyword: keyword, timestamp: Date().timeIntervalSince1970))
        entries.sort { $0.timestamp > $1.timestamp }
        if entries.count > maxCount {
            entries = Array(entries.prefix(maxCount))
        }
        saveEntries(entries)
    }

    /// 从历史中删除指定关键词（与记录时使用相同裁剪规则）
    static func removeKeyword(_ raw: String) {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        var entries = loadEntries()
        entries.removeAll { $0.keyword == keyword }
        saveEntries(entries)
    }
}

struct BRKillMailSearchView: View {
    let characterId: Int
    @StateObject private var viewModel = BRKillMailSearchViewModel()
    @State private var searchFieldText = ""
    @State private var hasSubmittedKeywordSearch = false
    @State private var recentKeywords: [String] = []
    @State private var isLoadingMore = false
    @State private var selectedFilter: KillMailFilter = .all
    /// 各筛选视角独立缓存的数据集：切换标签时命中缓存则瞬时恢复，无需重载
    @State private var filterDataCache: [KillMailLoadTrigger: FilterData] = [:]

    /// 有效筛选器：星域/星系搜索仅支持「全部」，自动归一化
    private var effectiveFilter: KillMailFilter {
        guard let result = viewModel.selectedResult,
              result.category == .solar_system || result.category == .region
        else { return selectedFilter }
        return .all
    }

    /// 当前视角标识：选中对象 + 有效筛选器。用作 .task(id:) 触发值与缓存键
    private var killMailLoadTrigger: KillMailLoadTrigger? {
        guard let result = viewModel.selectedResult else { return nil }
        return KillMailLoadTrigger(resultID: result.id, filter: effectiveFilter)
    }

    /// 当前视角的数据集（未加载过时为 nil）
    private var currentFilterData: FilterData? {
        guard let trigger = killMailLoadTrigger else { return nil }
        return filterDataCache[trigger]
    }

    /// 分页状态
    private struct SearchPaginationState {
        var currentZKBPage: Int = 1 // 当前 zkillboard API 页码
        var pendingZKBEntries: [ZKBKillMailEntry] = [] // 待转换的原始数据
        var convertedKillmailIds: Set<Int> = [] // 已转换的 killmail ID（用于去重）
        var hasMore: Bool = true // 是否还有更多数据
    }

    /// 视角标识：搜索结果 ID + 有效筛选器
    private struct KillMailLoadTrigger: Hashable {
        let resultID: Int
        let filter: KillMailFilter
    }

    /// 单个筛选视角的完整数据集
    private struct FilterData {
        var killMails: [KillMailListEntity] = []
        var paginationState = SearchPaginationState()
        var hasMoreData = true
        var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
        var allianceIconMap: [Int: UIImage] = [:]
        var corporationIconMap: [Int: UIImage] = [:]
        /// 初始加载是否完成过（区分「骨架屏加载中」与「无记录」）
        var isLoaded = false
    }

    /// 获取当前角色信息
    private var character: EVECharacterInfo? {
        EVELogin.shared.getCharacterByID(characterId)?.character
    }

    var body: some View {
        List {
            if viewModel.selectedResult != nil {
                Section {
                    HStack {
                        KMSearchResultRow(result: viewModel.selectedResult!)
                        Spacer()
                        Button {
                            viewModel.selectedResult = nil
                            filterDataCache = [:]
                            hasSubmittedKeywordSearch = false
                            searchFieldText = ""
                            viewModel.resetKeywordSearchResults()
                            recentKeywords = KillMailKeywordSearchHistory.recentKeywords()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    // 只在非星系和星域搜索时显示过滤器
                    if let selectedResult = viewModel.selectedResult,
                       selectedResult.category != .solar_system
                       && selectedResult.category != .region
                    {
                        Picker(
                            NSLocalizedString("KillMail_Filter", comment: ""),
                            selection: $selectedFilter
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
                    }

                    if let data = currentFilterData, !data.killMails.isEmpty {
                        ForEach(data.killMails) { entity in
                            let shipInfo = data.shipInfoMap[entity.shipTypeId] ?? (
                                name: String(
                                    format: NSLocalizedString("KillMail_Unknown_Item", comment: ""),
                                    entity.shipTypeId
                                ),
                                iconFileName: IconManager.defaultItemIcon
                            )
                            BRKillMailCell(
                                entity: entity,
                                shipInfo: shipInfo,
                                allianceIcon: entity.allianceId.flatMap { data.allianceIconMap[$0] },
                                corporationIcon: data.corporationIconMap[entity.corporationId],
                                characterId: characterId,
                                searchResult: viewModel.selectedResult,
                                character: character
                            )
                        }

                        if data.hasMoreData {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                } else {
                                    Button(action: {
                                        Task {
                                            await loadMoreKillMails()
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
                    } else if currentFilterData?.isLoaded == true {
                        Text(NSLocalizedString("KillMail_No_Records", comment: ""))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        // 该视角尚无数据 = 加载中，展示骨架屏
                        ForEach(0 ..< 6, id: \.self) { _ in
                            ListSkeletonRow.killMail
                        }
                    }
                }
            } else if hasSubmittedKeywordSearch {
                if viewModel.isSearching,
                   viewModel.searchResults.values.allSatisfy(\.isEmpty),
                   viewModel.directKillMailEntity == nil
                {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                } else if viewModel.searchResults.values.allSatisfy(\.isEmpty),
                          viewModel.directKillMailEntity == nil
                {
                    Section {
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                } else {
                    if let notice = viewModel.skippedOnlineSearchNotice {
                        Section {
                            Text(notice)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let kmEntity = viewModel.directKillMailEntity {
                        Section {
                            NavigationLink {
                                BRKillMailDetailView(
                                    listEntity: kmEntity,
                                    character: character
                                )
                            } label: {
                                KillMailDirectSearchResultRow(entity: kmEntity)
                            }
                        } header: {
                            Text(
                                NSLocalizedString(
                                    "KillMail_Search_Direct_KM", comment: "按 ID 匹配的战斗记录"
                                )
                            )
                        }
                    }

                    ForEach(viewModel.categories, id: \.self) { category in
                        if let results = viewModel.searchResults[category], !results.isEmpty {
                            Section(header: Text(category.localizedTitle)) {
                                ForEach(results) { result in
                                    Button {
                                        viewModel.selectedResult = result
                                    } label: {
                                        KMSearchResultRow(result: result)
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    if recentKeywords.isEmpty {
                        Text(NSLocalizedString("Main_Search_Results_Placeholder", comment: ""))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(recentKeywords, id: \.self) { keyword in
                            HStack(spacing: 8) {
                                Button {
                                    applyHistoryKeyword(keyword)
                                } label: {
                                    Text(keyword)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    KillMailKeywordSearchHistory.removeKeyword(keyword)
                                    recentKeywords = KillMailKeywordSearchHistory.recentKeywords()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .imageScale(.medium)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("KillMail_Search_Recent_History", comment: ""))
                }
            }
        }
        .navigationTitle(NSLocalizedString("KillMail_Search_Title", comment: ""))
        .searchable(
            text: $searchFieldText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("KillMail_Search_Input_Prompt", comment: ""))
        )
        .onSubmit(of: .search) {
            submitKeywordSearch(recordHistory: true)
        }
        .onChange(of: searchFieldText) { _, newValue in
            if newValue.isEmpty {
                hasSubmittedKeywordSearch = false
                viewModel.resetKeywordSearchResults()
            }
        }
        .onAppear {
            recentKeywords = KillMailKeywordSearchHistory.recentKeywords()
        }
        .task(id: killMailLoadTrigger) {
            guard let trigger = killMailLoadTrigger,
                  viewModel.selectedResult != nil else { return }

            // 保持 @State filter 与归一化后的值同步（星域/星系强制 .all）
            if selectedFilter != trigger.filter {
                selectedFilter = trigger.filter
            }

            // 该视角已有缓存数据：瞬时恢复，无需重载
            if filterDataCache[trigger]?.isLoaded == true {
                return
            }

            await loadKillMails(for: trigger)

            if !Task.isCancelled {
                // 标记该视角初始加载完成（含失败场景：落入「无记录」而非永久骨架屏）
                filterDataCache[trigger]?.isLoaded = true
            }
        }
    }

    private func submitKeywordSearch(recordHistory: Bool) {
        let q = searchFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        hasSubmittedKeywordSearch = true
        viewModel.search(characterId: characterId, searchText: q, force: true) { hasResults in
            if recordHistory, hasResults {
                KillMailKeywordSearchHistory.recordSearchSubmission(q)
                recentKeywords = KillMailKeywordSearchHistory.recentKeywords()
            }
        }
    }

    private func applyHistoryKeyword(_ keyword: String) {
        searchFieldText = keyword
        hasSubmittedKeywordSearch = true
        viewModel.search(characterId: characterId, searchText: keyword, force: true)
    }

    private func loadKillMails(for trigger: KillMailLoadTrigger) async {
        guard let selectedResult = viewModel.selectedResult else { return }

        // 重置该视角的数据集
        await MainActor.run {
            filterDataCache[trigger] = FilterData()
        }

        do {
            try Task.checkCancellation()

            let zkbEntries = try await zKbToolAPI.shared.fetchZKBKillMailsBySearchResult(
                result: selectedResult, page: 1, filter: trigger.filter
            )

            try Task.checkCancellation()

            await MainActor.run {
                filterDataCache[trigger]?.paginationState.pendingZKBEntries = zkbEntries
                filterDataCache[trigger]?.paginationState.currentZKBPage = 1
                filterDataCache[trigger]?.paginationState.hasMore = !zkbEntries.isEmpty
            }

            await loadNextBatch(for: trigger)
        } catch is CancellationError {
            // .task(id:) 自动取消，静默返回
        } catch {
            Logger.error("加载战斗日志失败: \(error)")
        }
    }

    private func loadNextBatch(for trigger: KillMailLoadTrigger) async {
        // 从 pendingZKBEntries 中取10个唯一条目
        let (batch, hasMore): ([ZKBKillMailEntry], Bool) = await MainActor.run {
            var data = filterDataCache[trigger, default: FilterData()]
            var batch: [ZKBKillMailEntry] = []
            var remainingEntries: [ZKBKillMailEntry] = []

            for entry in data.paginationState.pendingZKBEntries {
                if !data.paginationState.convertedKillmailIds.contains(entry.killmail_id) {
                    if batch.count < 10 {
                        batch.append(entry)
                        data.paginationState.convertedKillmailIds.insert(entry.killmail_id)
                    } else {
                        remainingEntries.append(entry)
                    }
                }
            }
            data.paginationState.pendingZKBEntries = remainingEntries
            let hasMore = data.paginationState.hasMore
            filterDataCache[trigger] = data

            return (batch, hasMore)
        }

        if Task.isCancelled {
            return
        }

        // 如果当前批次不足10个，尝试加载下一页
        var finalBatch = batch
        if finalBatch.count < 10, hasMore {
            let nextPage = await MainActor.run {
                (filterDataCache[trigger]?.paginationState.currentZKBPage ?? 1) + 1
            }
            guard let selectedResult = viewModel.selectedResult else { return }

            if Task.isCancelled {
                return
            }

            do {
                let nextPageEntries = try await zKbToolAPI.shared.fetchZKBKillMailsBySearchResult(
                    result: selectedResult, page: nextPage, filter: trigger.filter
                )

                let updatedBatch: [ZKBKillMailEntry] = await MainActor.run {
                    var data = filterDataCache[trigger, default: FilterData()]
                    data.paginationState.currentZKBPage = nextPage
                    data.paginationState.hasMore = !nextPageEntries.isEmpty

                    var newBatch = finalBatch
                    // 将新页面的数据添加到待处理列表
                    for entry in nextPageEntries {
                        if !data.paginationState.convertedKillmailIds.contains(entry.killmail_id) {
                            if newBatch.count < 10 {
                                newBatch.append(entry)
                                data.paginationState.convertedKillmailIds.insert(entry.killmail_id)
                            } else {
                                data.paginationState.pendingZKBEntries.append(entry)
                            }
                        }
                    }
                    filterDataCache[trigger] = data
                    return newBatch
                }
                finalBatch = updatedBatch
            } catch {
                Logger.error("加载下一页失败: \(error)")
                await MainActor.run {
                    filterDataCache[trigger]?.paginationState.hasMore = false
                }
            }
        }

        // 如果批次为空，说明没有更多数据
        if finalBatch.isEmpty {
            await MainActor.run {
                filterDataCache[trigger]?.hasMoreData = false
                filterDataCache[trigger]?.paginationState.hasMore = false
            }
            return
        }

        // 转换数据
        if Task.isCancelled {
            return
        }

        do {
            let entities = try await KillMailDataConverter.shared.fetchKillMailListEntities(
                zkbEntries: finalBatch
            )

            if Task.isCancelled {
                return
            }

            await MainActor.run {
                filterDataCache[trigger]?.killMails.append(contentsOf: entities)
            }

            await loadShipInfo(for: trigger, entities: entities)
            await loadOrganizationIcons(for: trigger, entities: entities)

            if Task.isCancelled {
                return
            }

            // 检查是否还有更多数据
            await MainActor.run {
                if let data = filterDataCache[trigger],
                   data.paginationState.pendingZKBEntries.isEmpty, !data.paginationState.hasMore
                {
                    filterDataCache[trigger]?.hasMoreData = false
                }
            }
        } catch {
            Logger.error("转换 killmail 数据失败: \(error)")
        }
    }

    private func loadMoreKillMails() async {
        guard let trigger = killMailLoadTrigger else { return }
        let canLoadMore = await MainActor.run { filterDataCache[trigger]?.hasMoreData ?? false }
        guard !isLoadingMore, canLoadMore else { return }

        isLoadingMore = true
        await loadNextBatch(for: trigger)
        isLoadingMore = false
    }

    private func loadShipInfo(for trigger: KillMailLoadTrigger, entities: [KillMailListEntity]) async {
        let shipIds = entities.map(\.shipTypeId)
        guard !shipIds.isEmpty else { return }

        // 内存索引批量取船名和图标
        for typeId in Set(shipIds) {
            guard let info = SDEMemoryStore.type(for: typeId) else { continue }
            filterDataCache[trigger]?.shipInfoMap[typeId] = (
                name: info.name, iconFileName: info.iconFilename
            )
        }
    }

    private func loadOrganizationIcons(
        for trigger: KillMailLoadTrigger, entities: [KillMailListEntity]
    ) async {
        for entity in entities {
            if let allyId = entity.allianceId, allyId > 0,
               filterDataCache[trigger]?.allianceIconMap[allyId] == nil
            {
                do {
                    let icon = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allyId)
                    filterDataCache[trigger]?.allianceIconMap[allyId] = icon
                } catch {
                    Logger.error("加载联盟图标失败 - 联盟ID: \(allyId), 错误: \(error)")
                }
            } else if entity.corporationId > 0,
                      filterDataCache[trigger]?.corporationIconMap[entity.corporationId] == nil
            {
                do {
                    let icon = try await CorporationAPI.shared.fetchCorporationLogo(
                        corporationId: entity.corporationId
                    )
                    filterDataCache[trigger]?.corporationIconMap[entity.corporationId] = icon
                } catch {
                    Logger.error("加载军团图标失败 - 军团ID: \(entity.corporationId), 错误: \(error)")
                }
            }
        }
    }
}

/// 按 killmail ID 直接搜索时的首行展示：左侧船型图标，右侧船名 + 受害者显示名
struct KillMailDirectSearchResultRow: View {
    let entity: KillMailListEntity
    @State private var shipName: String = ""
    @State private var shipIconFileName: String = IconManager.defaultItemIcon

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconManager.shared.loadImage(for: shipIconFileName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedShipName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(entity.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .task(id: entity.killmailId) {
            await loadShipInfoFromDatabase()
        }
    }

    private var resolvedShipName: String {
        if !shipName.isEmpty {
            return shipName
        }
        return String(
            format: NSLocalizedString("KillMail_Unknown_Item", comment: ""),
            entity.shipTypeId
        )
    }

    private func loadShipInfoFromDatabase() async {
        let tid = entity.shipTypeId
        guard let info = SDEMemoryStore.type(for: tid) else { return }
        await MainActor.run {
            shipName = info.name
            shipIconFileName = info.iconFilename
        }
    }
}

/// 搜索结果行视图
struct KMSearchResultRow: View {
    let result: SearchResult
    @State private var loadedIcon: UIImage?

    var body: some View {
        HStack {
            if let image = result.icon ?? loadedIcon {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // 显示加载中的占位图，同时开始加载图标
                ProgressView()
                    .frame(width: 32, height: 32)
                    .task {
                        await loadIcon()
                    }
            }

            VStack(alignment: .leading) {
                Text(result.name)
                Text(result.category.localizedTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func loadIcon() async {
        // 替换图标尺寸
        Logger.debug("Load img from result: \(result.imageURL)")
        let urlString = result.imageURL.replacingOccurrences(of: "size=32", with: "size=64")
        guard let url = URL(string: urlString) else {
            // URL无效时设置默认图标
            await MainActor.run {
                loadedIcon = UIImage(named: "not_found")
            }
            return
        }

        do {
            let data = try await NetworkManager.shared.fetchData(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    loadedIcon = image
                }
            } else {
                // 数据无法转换为图像时设置默认图标
                await MainActor.run {
                    loadedIcon = UIImage(named: "not_found")
                }
            }
        } catch {
            Logger.error("加载图标失败: \(error)")
            // 加载失败时设置默认图标
            await MainActor.run {
                loadedIcon = UIImage(named: "not_found")
            }
        }
    }
}

/// 搜索结果类别
enum SearchResultCategory: String {
    case alliance
    case character
    case corporation
    case inventory_type
    case solar_system
    case region

    var localizedTitle: String {
        switch self {
        case .alliance: return NSLocalizedString("KillMail_Search_Alliance", comment: "")
        case .character: return NSLocalizedString("KillMail_Search_Character", comment: "")
        case .corporation: return NSLocalizedString("KillMail_Search_Corporation", comment: "")
        case .inventory_type: return NSLocalizedString("KillMail_Search_Item", comment: "")
        case .solar_system: return NSLocalizedString("KillMail_Search_System", comment: "")
        case .region: return NSLocalizedString("KillMail_Search_Region", comment: "")
        }
    }
}

/// 搜索结果模型
struct SearchResult: Identifiable, Equatable {
    let id: Int
    let name: String
    let category: SearchResultCategory
    let imageURL: String
    var icon: UIImage?

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        return lhs.id == rhs.id && lhs.category == rhs.category
    }
}

@MainActor
class BRKillMailSearchViewModel: ObservableObject {
    @Published var searchResults: [SearchResultCategory: [SearchResult]] = [:]
    @Published var isSearching = false
    @Published var selectedResult: SearchResult?
    /// 关键词为纯数字时，按 killmail ID 解析到的单条记录（展示在列表首段）
    @Published var directKillMailEntity: KillMailListEntity?
    // 关键词不足 3 字时未请求 zkill 联网补全，在结果顶部提示
    @Published var skippedOnlineSearchNotice: String?
    private var lastSearchText: String = ""

    let categories: [SearchResultCategory] = [
        .inventory_type, .character, .corporation, .alliance,
        .solar_system, .region,
    ]

    /// 清空关键词搜索状态（不改变已选搜索对象 selectedResult）
    func resetKeywordSearchResults() {
        searchResults = [:]
        directKillMailEntity = nil
        lastSearchText = ""
        skippedOnlineSearchNotice = nil
    }

    /// 当前关键词搜索是否命中任意一条结果（本地舰船、联网分类、或 killmail ID）
    func hasAnyKeywordSearchResults() -> Bool {
        if directKillMailEntity != nil {
            return true
        }
        return searchResults.values.contains { !$0.isEmpty }
    }

    /// 同步入口：同步校验 + 置位 isSearching，异步搜索在内部 Task 执行。
    /// 调用方无需再包 Task，避免同步状态与异步调度之间的帧间隙。
    func search(
        characterId: Int,
        searchText: String,
        force: Bool = false,
        onComplete: ((_ hasResults: Bool) -> Void)? = nil
    ) {
        guard !searchText.isEmpty else {
            resetKeywordSearchResults()
            return
        }

        if !force,
           searchText == lastSearchText,
           !searchResults.isEmpty || directKillMailEntity != nil
        {
            return
        }

        // 同步清除旧结果，确保 body 在异步搜索期间显示加载指示器
        searchResults = [:]
        skippedOnlineSearchNotice = nil
        directKillMailEntity = nil
        isSearching = true

        Task {
            defer {
                isSearching = false
                let hasResults = hasAnyKeywordSearchResults()
                onComplete?(hasResults)
            }

            async let directKillmailTask = fetchDirectKillMailIfApplicable(searchText: searchText)

            // 联网搜索
            var networkResults: [SearchResultCategory: [SearchResult]] = [:]
            do {
                let apiResults = try await zKbToolAPI.shared.searchEveItems(
                    characterId: characterId,
                    searchText: searchText
                )

                for (categoryStr, items) in apiResults {
                    guard let category = SearchResultCategory(rawValue: categoryStr) else { continue }

                    var results: [SearchResult] = []
                    var seenIds = Set<Int>()

                    for item in items {
                        if !seenIds.contains(item.id) {
                            results.append(
                                SearchResult(
                                    id: item.id,
                                    name: item.name,
                                    category: category,
                                    imageURL: item.image,
                                    icon: nil
                                )
                            )
                            seenIds.insert(item.id)
                        }
                    }

                    if !results.isEmpty {
                        networkResults[category] = results
                    }
                }

                // 异步加载图标（不阻塞搜索完成）
                Task {
                    for category in categories {
                        if let results = networkResults[category] {
                            for result in results {
                                if let url = URL(
                                    string: result.imageURL.replacingOccurrences(
                                        of: "size=32", with: "size=64"
                                    )
                                ),
                                    let data = try? await NetworkManager.shared.fetchData(from: url),
                                    let image = UIImage(data: data)
                                {
                                    if let index = self.searchResults[category]?.firstIndex(where: {
                                        $0.id == result.id
                                    }) {
                                        self.searchResults[category]?[index].icon = image
                                    }
                                }
                            }
                        }
                    }
                }

            } catch {
                Logger.error("联网搜索失败: \(error)")
            }

            searchResults = networkResults
            directKillMailEntity = await directKillmailTask

            lastSearchText = searchText

            if searchText.count < 3 {
                skippedOnlineSearchNotice = NSLocalizedString(
                    "KillMail_Search_Skipped_Online_Results_Banner", comment: ""
                )
            } else {
                skippedOnlineSearchNotice = nil
            }
        }
    }

    /// 关键词为纯数字时，尝试按 killmail ID 拉取并转换为列表实体
    private func fetchDirectKillMailIfApplicable(searchText: String) async -> KillMailListEntity? {
        guard searchText.allSatisfy({ $0.isNumber }),
              let killmailId = Int(searchText)
        else { return nil }

        do {
            let zkbEntry = try await zKbToolAPI.shared.fetchZKBKillMailByID(killmailId: killmailId)
            let entities = try await KillMailDataConverter.shared.fetchKillMailListEntities(
                zkbEntries: [zkbEntry]
            )
            return entities.first
        } catch {
            Logger.debug("按 ID 解析 killmail 失败: \(error.localizedDescription)")
            return nil
        }
    }
}
