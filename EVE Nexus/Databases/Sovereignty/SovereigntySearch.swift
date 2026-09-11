import SwiftUI

// MARK: - 主权搜索与数据引擎

/// 主权数据的唯一加载管道：提供主权列表数据，并支撑三级目录统一的全局搜索
/// （主权势力名 + 星系名，结果与当前所在层级无关）
@MainActor
final class SovereigntySearchEngine {
    static let shared = SovereigntySearchEngine()

    /// 星系命中结果：含所属主权（用于展示主权信息）
    struct SystemHit: Identifiable {
        let system: SolarSystemInfo
        let sovereignty: SovereigntyInfo?
        var id: Int {
            system.systemId
        }
    }

    /// 搜索结果：主权势力 + 星系
    struct Results {
        var sovereignties: [SovereigntyInfo] = []
        var systems: [SystemHit] = []
        var isEmpty: Bool {
            sovereignties.isEmpty && systems.isEmpty
        }
    }

    private(set) var sovereignties: [SovereigntyInfo] = []
    private var sovereigntyById: [Int: SovereigntyInfo] = [:]
    /// 主权势力ID（联盟或派系）→ 控制的星系ID
    private var ownerSystemIds: [Int: [Int]] = [:]
    /// 星系ID → 所属主权（联盟优先，派系兜底）
    private var systemOwner: [Int: (id: Int, isAlliance: Bool)] = [:]
    /// 星系位置信息缓存（会话级）
    private var systemInfoCache: [Int: SolarSystemInfo] = [:]
    private var isLoaded = false

    private init() {}

    /// 加载全部主权数据（会话级缓存），返回主权列表（按星系数量降序）
    @discardableResult
    func loadAll(forceRefresh: Bool = false) async throws -> [SovereigntyInfo] {
        if isLoaded, !forceRefresh {
            return sovereignties
        }

        let data = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
            forceRefresh: forceRefresh
        )

        // 统计各联盟/派系的星系数量
        var allianceCounts: [Int: Int] = [:]
        var factionCounts: [Int: Int] = [:]
        for item in data {
            if let allianceId = item.allianceId {
                allianceCounts[allianceId, default: 0] += 1
            }
            if let factionId = item.factionId {
                factionCounts[factionId, default: 0] += 1
            }
        }

        var list: [SovereigntyInfo] = []

        // 联盟（名称走 ESI 解析）
        let allianceNames = try await UniverseAPI.shared.getNamesWithFallback(
            ids: Array(allianceCounts.keys)
        )
        for (allianceId, count) in allianceCounts {
            guard let name = allianceNames[allianceId]?.name else { continue }
            list.append(
                SovereigntyInfo(
                    id: allianceId,
                    names: LocalizedText.filled(with: name),
                    icon: nil,
                    systemCount: count,
                    isAlliance: true
                )
            )
        }

        // 派系（名称与图标走本地 SDE）
        for (factionId, count) in factionCounts {
            guard let faction = SDEMemoryStore.faction(for: factionId) else { continue }
            list.append(
                SovereigntyInfo(
                    id: factionId,
                    names: faction.names,
                    icon: IconManager.shared.loadImage(for: faction.iconName),
                    systemCount: count,
                    isAlliance: false
                )
            )
        }

        list.sort { $0.systemCount > $1.systemCount }

        // 建立势力→星系、星系→势力索引
        var owners: [Int: [Int]] = [:]
        var ownersBySystem: [Int: (id: Int, isAlliance: Bool)] = [:]
        for item in data {
            let owner: (id: Int, isAlliance: Bool)
            if let allianceId = item.allianceId {
                owner = (allianceId, true)
            } else if let factionId = item.factionId {
                owner = (factionId, false)
            } else {
                continue
            }
            owners[owner.id, default: []].append(item.systemId)
            ownersBySystem[item.systemId] = owner
        }

        sovereignties = list
        sovereigntyById = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        ownerSystemIds = owners
        systemOwner = ownersBySystem
        systemInfoCache = [:]
        isLoaded = true
        return list
    }

    /// 某主权势力控制的星系（含位置信息）
    func systemInfos(forSovereigntyId sovereigntyId: Int, forceRefresh: Bool = false) async throws
        -> [SolarSystemInfo]
    {
        try await loadAll(forceRefresh: forceRefresh)
        let ids = ownerSystemIds[sovereigntyId] ?? []
        let infos = await cachedInfos(for: ids)
        return Array(infos.values)
    }

    /// 星系所属主权势力（名称/图标随 loadAll 解析完毕；无主权返回 nil）
    /// 调用前需确保 loadAll 已完成（会话级缓存，重复调用零开销）
    func sovereigntyInfo(forSystemId systemId: Int) -> SovereigntyInfo? {
        guard let owner = systemOwner[systemId] else { return nil }
        return sovereigntyById[owner.id]
    }

    /// 全局搜索：主权势力名 + 星系名
    func search(_ query: String) async -> Results {
        guard !query.isEmpty else { return Results() }

        do {
            try await loadAll()
        } catch {
            Logger.error("主权搜索加载数据失败: \(error)")
            return Results()
        }

        let matchedSovereignties = sovereignties.filter { $0.matches(query) }

        // 星系名匹配（内存索引），一次性批量补查位置信息
        let matchedSystemIds = systemOwner.keys
            .filter { SDEMemoryStore.solarSystemNames[$0]?.matchesSearch(query) == true }
            .sorted()

        var hits: [SystemHit] = []
        if !matchedSystemIds.isEmpty {
            let infos = await cachedInfos(for: matchedSystemIds)
            for systemId in matchedSystemIds {
                guard let system = infos[systemId], let owner = systemOwner[systemId] else {
                    continue
                }
                hits.append(
                    SystemHit(system: system, sovereignty: sovereigntyById[owner.id])
                )
            }
            hits.sort { $0.system.systemName < $1.system.systemName }
        }

        return Results(sovereignties: matchedSovereignties, systems: hits)
    }

    /// 批量获取星系位置信息（带会话缓存）
    private func cachedInfos(for ids: [Int]) async -> [Int: SolarSystemInfo] {
        let missing = Array(Set(ids).subtracting(systemInfoCache.keys))
        if !missing.isEmpty {
            let fetched = await getBatchSolarSystemInfo(
                solarSystemIds: missing,
                databaseManager: .shared
            )
            systemInfoCache.merge(fetched) { _, new in new }
        }
        var result: [Int: SolarSystemInfo] = [:]
        for id in ids where systemInfoCache[id] != nil {
            result[id] = systemInfoCache[id]
        }
        return result
    }
}

// MARK: - 统一搜索结果页

/// 三级目录共用的搜索结果页：主权势力 / 星系 双 section，均可跳转
struct SovereigntySearchResultsView: View {
    let results: SovereigntySearchEngine.Results
    @StateObject private var iconLoader = AllianceIconLoader()

    /// 命中结果中涉及的联盟ID（主权行 + 星系行所属主权，图标异步加载，结果变化时自动重新触发）
    private var allianceIds: [Int] {
        var ids = Set(results.sovereignties.filter(\.isAlliance).map(\.id))
        ids.formUnion(
            results.systems.compactMap { $0.sovereignty }.filter(\.isAlliance).map(\.id)
        )
        return ids.sorted()
    }

    var body: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_Not_Found", comment: ""),
                        systemImage: "magnifyingglass"
                    )
                }
            }

            if !results.sovereignties.isEmpty {
                Section(
                    header: Text(
                        "\(NSLocalizedString("Sovereignty_Search_Results_Factions", comment: "主权势力")) (\(results.sovereignties.count))"
                    )
                ) {
                    ForEach(results.sovereignties, id: \.id) { sovereignty in
                        NavigationLink(
                            destination: SovereigntyRegionsView(
                                databaseManager: .shared,
                                sovereigntyInfo: sovereignty
                            )
                        ) {
                            sovereigntyRow(sovereignty)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            if !results.systems.isEmpty {
                Section(
                    header: Text(
                        "\(NSLocalizedString("Sovereignty_Search_Results_Systems", comment: "星系")) (\(results.systems.count))"
                    )
                ) {
                    ForEach(results.systems) { hit in
                        systemHitRow(hit)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .listStyle(.insetGrouped)
        .task(id: allianceIds) {
            // 加载命中联盟的图标（缓存命中时瞬时完成）
            guard !allianceIds.isEmpty else { return }
            iconLoader.loadIcons(for: allianceIds)
        }
    }

    /// 主权势力行：点按进入第二级（星域列表）
    private func sovereigntyRow(_ sovereignty: SovereigntyInfo) -> some View {
        HStack {
            if let icon = iconLoader.icons[sovereignty.id] ?? sovereignty.icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else if sovereignty.isAlliance {
                // 联盟图标加载中
                ProgressView()
                    .frame(width: 32, height: 32)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Image("faction_default")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading) {
                Text(sovereignty.name)
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = sovereignty.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                Text(
                    "\(sovereignty.systemCount) \(NSLocalizedString("Sovereignty_Systems", comment: "个星系"))"
                )
                .font(.caption)
                .foregroundColor(.gray)
            }

            Spacer()
        }
    }

    /// 星系行：纯展示，附所属主权信息（图标+名称，联盟图标异步加载）
    private func systemHitRow(_ hit: SovereigntySearchEngine.SystemHit) -> some View {
        let sovereignty = hit.sovereignty
        let icon = sovereignty.flatMap { iconLoader.icons[$0.id] ?? $0.icon }
        // 联盟图标尚未就绪时显示加载态
        let isIconLoading = sovereignty?.isAlliance == true && icon == nil

        return SystemRowView(
            name: hit.system.systemName,
            security: hit.system.security,
            showsSovereignty: true,
            sovereigntyIcon: icon,
            sovereigntyName: sovereignty?.name,
            isSovereigntyLoading: isIconLoading
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = hit.system.systemName
            } label: {
                Label(
                    NSLocalizedString("Misc_Copy_Location", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
    }
}

// MARK: - 搜索容器

/// 三级目录统一的搜索挂载容器：包裹页面内容即获得与全局一致的搜索体验
/// （同一提示词、提交后切换为统一结果页、左上角返回按钮）
struct SovereigntySearchScope<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isShowingSearchResults = false
    @State private var isSearching = false
    @State private var results: SovereigntySearchEngine.Results?

    var body: some View {
        Group {
            if isShowingSearchResults {
                searchContent
            } else {
                content()
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            prompt: NSLocalizedString(
                "Sovereignty_Search_Placeholder", comment: "搜索主权势力或星系..."
            )
        )
        .onSubmit(of: .search) {
            if !searchText.isEmpty {
                Task { await performSearch() }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                isShowingSearchResults = false
                results = nil
            }
        }
        .navigationBarBackButtonHidden(isShowingSearchResults)
        .toolbar {
            if isShowingSearchResults {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        searchText = ""
                        isSearchActive = false
                        isShowingSearchResults = false
                        results = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(NSLocalizedString("Misc_back", comment: ""))
                        }
                    }
                }
            }
        }
    }

    /// 搜索中加载遮罩 / 结果页
    @ViewBuilder
    private var searchContent: some View {
        if isSearching {
            Color(.systemBackground)
                .ignoresSafeArea()
                .overlay {
                    VStack {
                        ProgressView()
                        Text(NSLocalizedString("Main_Database_Searching", comment: ""))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
        } else if let results {
            SovereigntySearchResultsView(results: results)
        }
    }

    private func performSearch() async {
        isSearching = true
        isShowingSearchResults = true
        results = await SovereigntySearchEngine.shared.search(searchText)
        isSearching = false
    }
}
