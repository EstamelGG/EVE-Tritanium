
//  IncursionsView.swift
//  EVE Panel

//  Created by GG Estamel on 2024/12/16.

import SwiftUI

// MARK: - Models

struct PreparedIncursion: Identifiable {
    let id: Int
    let incursion: Incursion
    let faction: FactionInfo
    let location: LocationInfo
    let sovereignty: SovereigntyInfo?

    struct FactionInfo {
        let iconName: String
        let name: String
    }

    struct LocationInfo {
        let systemId: Int
        let systemName: String
        let security: Double
        let constellationId: Int
        let constellationName: String
        let regionId: Int
        let regionName: String
    }

    class SovereigntyInfo: ObservableObject {
        let id: Int
        let isAlliance: Bool
        @Published var icon: Image?
        @Published var isLoadingIcon: Bool = true

        init(id: Int, isAlliance: Bool) {
            self.id = id
            self.isAlliance = isAlliance
        }
    }

    init(
        incursion: Incursion, faction: FactionInfo, location: LocationInfo,
        sovereignty: SovereigntyInfo? = nil
    ) {
        id = incursion.constellationId
        self.incursion = incursion
        self.faction = faction
        self.location = location
        self.sovereignty = sovereignty
    }
}

// MARK: - ViewModel

@MainActor
final class IncursionsViewModel: ObservableObject {
    @Published private(set) var preparedIncursions: [PreparedIncursion] = []
    @Published var isLoading = true
    @Published var errorMessage: String?

    // 导出状态
    @Published var showExportAlert = false
    @Published var exportSuccess = false
    @Published var exportMessage = ""

    let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var lastFetchTime: Date?
    private let cacheTimeout: TimeInterval = 300 // 5分钟缓存

    /// 缓存所有星系信息，包括受影响的星系
    private var allSystemInfoCache: [Int: SolarSystemInfo] = [:]

    // 主权数据缓存
    private var sovereigntyData: [SovereigntyData] = []
    private var loadingTasks: [Int: Task<Void, Never>] = [:]

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        // 构造时启动数据加载（原先由视图 init 触发，移入以避免视图重复构造引发重复加载）
        Task {
            await fetchIncursionsData()
        }
    }

    deinit {
        loadingTask?.cancel()
        loadingTasks.values.forEach { $0.cancel() }
    }

    func fetchIncursionsData(forceRefresh: Bool = false) async {
        // 如果不是强制刷新，且缓存未过期，且已有数据，则直接返回
        if !forceRefresh,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTimeout,
           !preparedIncursions.isEmpty
        {
            Logger.debug("使用缓存的入侵数据，跳过加载")
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                Logger.info("开始获取入侵数据")
                let incursions = try await IncursionsAPI.shared.fetchIncursions(
                    forceRefresh: forceRefresh
                )

                if Task.isCancelled {
                    return
                }

                await processIncursions(incursions)

                if Task.isCancelled {
                    return
                }

                self.lastFetchTime = Date()
                self.isLoading = false

            } catch {
                Logger.error("获取入侵数据失败: \(error)")
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    private func processIncursions(_ incursions: [Incursion]) async {
        // 提取所有需要查询的星系ID（包括主要星系和所有受影响星系）
        var allSystemIds = Set<Int>()
        for incursion in incursions {
            allSystemIds.insert(incursion.stagingSolarSystemId)
            allSystemIds.formUnion(incursion.infestedSolarSystems)
        }

        // 一次性获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: Array(allSystemIds),
            databaseManager: databaseManager
        )

        // 缓存所有星系信息
        allSystemInfoCache = systemInfoMap

        // 获取主权数据
        do {
            sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData(
                forceRefresh: false
            )
        } catch {
            Logger.error("获取主权数据失败: \(error)")
        }

        var prepared: [PreparedIncursion] = []

        for incursion in incursions {
            // 获取派系信息
            guard let faction = await getFactionInfo(factionId: incursion.factionId) else {
                continue
            }

            // 获取星系信息
            guard let systemInfo = systemInfoMap[incursion.stagingSolarSystemId] else {
                continue
            }

            let locationInfo = PreparedIncursion.LocationInfo(
                systemId: systemInfo.systemId,
                systemName: systemInfo.systemName,
                security: systemInfo.security,
                constellationId: systemInfo.constellationId,
                constellationName: systemInfo.constellationName,
                regionId: systemInfo.regionId,
                regionName: systemInfo.regionName
            )

            // 获取主权信息
            let sovereigntyInfo = getSovereigntyInfo(for: incursion.stagingSolarSystemId)

            let preparedIncursion = PreparedIncursion(
                incursion: incursion,
                faction: .init(iconName: faction.iconName, name: faction.name),
                location: locationInfo,
                sovereignty: sovereigntyInfo
            )

            prepared.append(preparedIncursion)
        }

        // 多重排序条件：
        // 1. 按影响力从大到小
        // 2. 同等影响力下，有boss的优先
        // 3. boss状态相同时，按星系名称字母顺序
        prepared.sort { a, b in
            if a.incursion.influence != b.incursion.influence {
                return a.incursion.influence > b.incursion.influence
            }
            if a.incursion.hasBoss != b.incursion.hasBoss {
                return a.incursion.hasBoss
            }
            return a.location.systemName < b.location.systemName
        }

        if !prepared.isEmpty {
            Logger.success("成功准备 \(prepared.count) 条数据")
            preparedIncursions = prepared

            // 开始加载主权图标
            loadAllSovereigntyIcons()
        } else {
            Logger.error("没有可显示的完整数据")
        }
    }

    private func getFactionInfo(factionId: Int) async -> (iconName: String, name: String)? {
        let iconName = factionId == 500_019 ? "sansha" : "corporations_default"
        guard let name = SDEMemoryStore.faction(for: factionId)?.name else { return nil }
        return (iconName, name)
    }

    private func getSovereigntyInfo(for systemId: Int) -> PreparedIncursion.SovereigntyInfo? {
        guard let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) else {
            return nil
        }

        if let allianceId = systemData.allianceId {
            return PreparedIncursion.SovereigntyInfo(id: allianceId, isAlliance: true)
        } else if let factionId = systemData.factionId {
            return PreparedIncursion.SovereigntyInfo(id: factionId, isAlliance: false)
        }

        return nil
    }

    private func loadAllSovereigntyIcons() {
        // 取消之前的加载任务
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()

        // 按主权ID分组
        var allianceToIncursions: [Int: [PreparedIncursion.SovereigntyInfo]] = [:]
        var factionToIncursions: [Int: [PreparedIncursion.SovereigntyInfo]] = [:]

        for incursion in preparedIncursions {
            if let sovereignty = incursion.sovereignty {
                if sovereignty.isAlliance {
                    allianceToIncursions[sovereignty.id, default: []].append(sovereignty)
                } else {
                    factionToIncursions[sovereignty.id, default: []].append(sovereignty)
                }
            }
        }

        // 加载联盟图标
        for (allianceId, sovereignties) in allianceToIncursions {
            let task = Task {
                do {
                    Logger.debug("开始加载联盟图标: \(allianceId)，影响 \(sovereignties.count) 个入侵")

                    // 加载联盟图标
                    let logo = try await AllianceAPI.shared.fetchAllianceLogo(
                        allianceID: allianceId, size: 64
                    )

                    await MainActor.run {
                        for sovereignty in sovereignties {
                            sovereignty.icon = Image(uiImage: logo)
                            sovereignty.isLoadingIcon = false
                        }
                    }

                    Logger.debug("联盟图标和名称加载成功: \(allianceId)")
                } catch {
                    Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                    await MainActor.run {
                        for sovereignty in sovereignties {
                            sovereignty.isLoadingIcon = false
                        }
                    }
                }
            }
            loadingTasks[allianceId] = task
        }

        // 加载派系图标
        for (factionId, sovereignties) in factionToIncursions {
            let task = Task {
                Logger.debug("开始加载派系图标: \(factionId)，影响 \(sovereignties.count) 个入侵")

                if let iconName = SDEMemoryStore.faction(for: factionId)?.iconName {
                    let icon = IconManager.shared.loadImage(for: iconName)

                    await MainActor.run {
                        for sovereignty in sovereignties {
                            sovereignty.icon = icon
                            sovereignty.isLoadingIcon = false
                        }
                    }

                    Logger.debug("派系图标和名称加载成功: \(factionId)")
                } else {
                    Logger.error("派系图标加载失败: \(factionId)")
                    await MainActor.run {
                        for sovereignty in sovereignties {
                            sovereignty.isLoadingIcon = false
                        }
                    }
                }
            }
            loadingTasks[factionId] = task
        }
    }

    /// 获取入侵涉及的所有星系名称，已排序
    func getInfestedSystemNames(for incursion: PreparedIncursion) -> [String] {
        return incursion.incursion.infestedSolarSystems
            .compactMap { systemId in
                allSystemInfoCache[systemId]?.systemName
            }
            .sorted()
    }

    /// 导出入侵信息到剪贴板
    func exportIncursionsToClipboard() async {
        guard !preparedIncursions.isEmpty else {
            Logger.warning("没有可导出的入侵数据")
            exportSuccess = false
            exportMessage = NSLocalizedString("Incursions_Export_Empty", comment: "")
            showExportAlert = true
            return
        }

        do {
            // 收集所有需要获取名称的ID（联盟和派系）
            var allianceIds: Set<Int> = []
            var factionIds: Set<Int> = []

            for incursion in preparedIncursions {
                if let sovereignty = incursion.sovereignty {
                    if sovereignty.isAlliance {
                        allianceIds.insert(sovereignty.id)
                    } else {
                        factionIds.insert(sovereignty.id)
                    }
                }
            }

            // 批量获取联盟和派系名称
            var sovereigntyNames: [Int: String] = [:]

            // 获取联盟名称
            if !allianceIds.isEmpty {
                do {
                    let namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: Array(allianceIds))
                    for (id, info) in namesMap {
                        sovereigntyNames[id] = info.name
                    }
                } catch {
                    Logger.error("获取联盟名称失败: \(error)")
                }
            }

            // 获取派系名称
            for factionId in factionIds {
                if let name = SDEMemoryStore.faction(for: factionId)?.name {
                    sovereigntyNames[factionId] = name
                }
            }

            // 格式化日期
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            let dateString = dateFormatter.string(from: Date())

            // 构建输出文本
            let incursionTitle = NSLocalizedString("Incursions_Export_Title", comment: "")
            var output = "\(dateString) - \(incursionTitle)\n\n"

            // 按星座分组（使用UI的排序顺序）
            for incursion in preparedIncursions {
                // 获取势力名称
                var sovereigntyName = ""
                if let sovereignty = incursion.sovereignty {
                    sovereigntyName = sovereigntyNames[sovereignty.id] ?? NSLocalizedString("Unknown", comment: "")
                } else {
                    sovereigntyName = NSLocalizedString("Structure_Info_No_Sovereignty", comment: "")
                }

                // 获取受影响的星系名称（已排序）
                let systemNames = getInfestedSystemNames(for: incursion)

                // 格式化影响度百分比（整数）
                let influencePercent = Int(round(incursion.incursion.influence * 100))

                // 添加星座信息（包含影响度百分比）
                let constellationLabel = NSLocalizedString("Incursions_Export_Constellation_Label", comment: "")
                output += "\(constellationLabel)\(incursion.location.constellationName) (\(influencePercent)%) - \(sovereigntyName)\n"

                // 添加星系列表
                for systemName in systemNames {
                    output += " - \(systemName)\n"
                }

                output += "\n"
            }

            // 复制到剪贴板
            UIPasteboard.general.string = output
            Logger.info("入侵信息已复制到剪贴板")

            // 显示成功消息
            exportSuccess = true
            exportMessage = NSLocalizedString("Incursions_Export_Success", comment: "")
            showExportAlert = true
        }
    }
}

// MARK: - Views

struct IncursionCell: View {
    let incursion: PreparedIncursion
    let databaseManager: DatabaseManager
    let viewModel: IncursionsViewModel

    private static let stateOrder = ["established", "mobilizing", "withdrawing"]
    private static let progressFillColor = Color(red: 64 / 255, green: 168 / 255, blue: 176 / 255)

    private var stateColor: Color {
        Self.color(for: incursion.incursion.state)
    }

    private var stateText: String {
        Self.text(for: incursion.incursion.state)
    }

    private static func color(for state: String) -> Color {
        switch state {
        case "withdrawing":
            return Color(red: 175 / 255, green: 55 / 255, blue: 54 / 255)
        case "mobilizing":
            return Color(red: 223 / 255, green: 100 / 255, blue: 55 / 255)
        case "established":
            return Color(red: 96 / 255, green: 179 / 255, blue: 88 / 255)
        default:
            return .secondary
        }
    }

    private static func text(for state: String) -> String {
        switch state {
        case "withdrawing":
            return NSLocalizedString("Incursions_State_Withdrawing", comment: "")
        case "mobilizing":
            return NSLocalizedString("Incursions_State_Mobilizing", comment: "")
        case "established":
            return NSLocalizedString("Incursions_State_Established", comment: "")
        default:
            return state
        }
    }

    var body: some View {
        NavigationLink(
            destination: InfestedSystemsView(
                databaseManager: databaseManager,
                systemIds: incursion.incursion.infestedSolarSystems,
                stagingSystemId: incursion.incursion.stagingSolarSystemId
            )
        ) {
            HStack(alignment: .center, spacing: 12) {
                if let sovereignty = incursion.sovereignty {
                    SovereigntyIconView(sovereignty: sovereignty)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 48, height: 48)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(formatSystemSecurity(incursion.location.security))
                            .foregroundColor(getSecurityColor(incursion.location.security))
                            .font(.system(.subheadline, design: .monospaced))
                        Text(incursion.location.systemName)
                            .fontWeight(.semibold)
                            .font(.subheadline)
                            .lineLimit(1)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = incursion.location.systemName
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy_Staging_Solar", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                                Button {
                                    UIPasteboard.general.string =
                                        incursion.location.constellationName
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy_Constellation", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                                Button {
                                    let systemNames = viewModel.getInfestedSystemNames(
                                        for: incursion
                                    )
                                    let formattedString =
                                        "\(incursion.location.constellationName) \(NSLocalizedString("Misc_Constellation", comment: "")) (\(systemNames.joined(separator: ",")))"
                                    UIPasteboard.general.string = formattedString
                                } label: {
                                    Label(
                                        NSLocalizedString(
                                            "Misc_Copy_Constellation_And_Solar", comment: ""
                                        ),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }
                        Text(
                            "[\(String(format: "%.1f", incursion.incursion.influence * 100))%]"
                        )
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        if incursion.incursion.hasBoss {
                            IconManager.shared.loadImage(for: "sansha_boss")
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                    }

                    Text(
                        "\(incursion.location.constellationName) / \(incursion.location.regionName)"
                    )
                    .foregroundColor(.secondary)
                    .font(.caption)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            HStack(spacing: 3) {
                                ForEach(Self.stateOrder, id: \.self) { state in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(
                                            state == incursion.incursion.state
                                                ? Self.color(for: state)
                                                : Color.secondary.opacity(0.35)
                                        )
                                        .frame(width: 14, height: 5)
                                }
                            }
                            Text(stateText)
                                .foregroundColor(stateColor)
                                .font(.caption)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(stateColor)
                                Rectangle()
                                    .fill(Self.progressFillColor)
                                    .frame(
                                        width: geo.size.width
                                            * CGFloat(incursion.incursion.influence)
                                    )
                            }
                        }
                        .frame(height: 3)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

struct SovereigntyIconView: View {
    @ObservedObject var sovereignty: PreparedIncursion.SovereigntyInfo

    var body: some View {
        if sovereignty.isLoadingIcon {
            ProgressView()
                .frame(width: 48, height: 48)
        } else if let icon = sovereignty.icon {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .cornerRadius(6)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 48, height: 48)
        }
    }
}

struct IncursionsView: View {
    @StateObject private var viewModel: IncursionsViewModel

    init(databaseManager: DatabaseManager) {
        // 构造表达式内联在 autoclosure 中，避免父视图每次重渲染都新建 ViewModel；
        // 数据加载已在 ViewModel init 中启动
        _viewModel = StateObject(wrappedValue: IncursionsViewModel(databaseManager: databaseManager))
    }

    var body: some View {
        List {
            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.preparedIncursions.isEmpty {
                    Section {
                        NoDataSection()
                    }
                } else {
                    ForEach(viewModel.preparedIncursions) { incursion in
                        IncursionCell(
                            incursion: incursion,
                            databaseManager: viewModel.databaseManager,
                            viewModel: viewModel
                        )
                    }
                }
            } footer: {
                if !viewModel.preparedIncursions.isEmpty {
                    Text(
                        "\(viewModel.preparedIncursions.count) \(NSLocalizedString("Main_Setting_Static_Resource_Incursions_num", comment: ""))"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.fetchIncursionsData(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Incursions", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await viewModel.exportIncursionsToClipboard()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.isLoading || viewModel.preparedIncursions.isEmpty)
            }
        }
        .alert(
            viewModel.exportSuccess
                ? NSLocalizedString("Operation_Success", comment: "")
                : NSLocalizedString("Incursions_Export_Failed_Title", comment: ""),
            isPresented: $viewModel.showExportAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.exportMessage)
        }
    }
}
