
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

                // 百分比最多保留一位小数，省略末尾的零
                let influencePercent = FormatUtil.format(min(max(incursion.incursion.influence, 0), 1) * 100, maxFractionDigits: 1)
                let influenceText = String(
                    format: NSLocalizedString("Incursions_Influence_Format", comment: ""),
                    influencePercent
                )

                // 添加星座信息（包含影响度百分比）
                let constellationLabel = NSLocalizedString("Incursions_Export_Constellation_Label", comment: "")
                output += "\(constellationLabel)\(incursion.location.constellationName) (\(influenceText)) - \(sovereigntyName)\n"

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

/// 入侵状态行：状态三色小方块 + 状态文字 + 影响力进度条
/// 从 `IncursionCell` 抽出，便于脱开 DatabaseManager / ViewModel 单独预览
struct IncursionProgressRow: View {
    let state: String
    let influence: Double

    static let stateOrder = ["established", "mobilizing", "withdrawing"]
    static let progressFillColor = Color(red: 64 / 255, green: 168 / 255, blue: 176 / 255)
    static let progressTrackColor = Color(red: 130 / 255, green: 55 / 255, blue: 55 / 255)

    static func color(for state: String) -> Color {
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

    static func text(for state: String) -> String {
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

    private var stateColor: Color {
        Self.color(for: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(Self.stateOrder, id: \.self) { item in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                item == state
                                    ? Self.color(for: item)
                                    : Color.secondary.opacity(0.35)
                            )
                            .frame(width: 14, height: 5)
                    }
                }
                Text(Self.text(for: state))
                    .foregroundColor(stateColor)
                    .font(.caption)
                Spacer(minLength: 8)
                Text(verbatim: "\(FormatUtil.format(min(max(influence, 0), 1) * 100, maxFractionDigits: 1))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundColor(Self.progressFillColor)
            }

            let fraction = min(max(influence, 0), 1)
            SegmentedProgressBar(segments: [
                .init(value: fraction, color: Self.progressFillColor),
                .init(value: 1 - fraction, color: Self.progressTrackColor),
            ])
        }
    }
}

struct IncursionCell: View {
    let incursion: PreparedIncursion
    let databaseManager: DatabaseManager
    let viewModel: IncursionsViewModel

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
                        if incursion.incursion.hasBoss {
                            IconManager.shared.loadImage(for: "iconmothership")
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                    }

                    Text(
                        "\(incursion.location.constellationName) / \(incursion.location.regionName)"
                    )
                    .foregroundColor(.secondary)
                    .font(.caption)

                    IncursionProgressRow(
                        state: incursion.incursion.state,
                        influence: incursion.incursion.influence
                    )
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
    @State private var showInformation = false

    init(databaseManager: DatabaseManager) {
        // 构造表达式内联在 autoclosure 中，避免父视图每次重渲染都新建 ViewModel；
        // 数据加载已在 ViewModel init 中启动
        _viewModel = StateObject(wrappedValue: IncursionsViewModel(databaseManager: databaseManager))
    }

    private var canCopyIncursions: Bool {
        !viewModel.isLoading && !viewModel.preparedIncursions.isEmpty
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
            } header: {
                if !viewModel.preparedIncursions.isEmpty {
                    Text(
                        "\(viewModel.preparedIncursions.count) \(NSLocalizedString("Main_Setting_Static_Resource_Incursions_num", comment: ""))"
                    )
                }
            }
            Group {
                if canCopyIncursions {
                    Section {
                        Button {
                            Task {
                                await viewModel.exportIncursionsToClipboard()
                            }
                        } label: {
                            Label("Incursions_Copy_To_Clipboard", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: canCopyIncursions)
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.fetchIncursionsData(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Incursions", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showInformation = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel(Text("Incursions_Info_Title"))
            }
        }
        .sheet(isPresented: $showInformation) {
            IncursionsInformationView()
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

// MARK: - Preview

private struct IncursionsInformationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                informationSection(
                    title: Text("Incursions_Info_Overview_Title"),
                    body: Text("Incursions_Info_Overview_Body")
                )
                Section {
                    stageExample(
                        state: "established", number: 1,
                        detail: Text("Incursions_Info_Established_Detail")
                    )
                    stageExample(
                        state: "mobilizing", number: 2,
                        detail: Text("Incursions_Info_Mobilizing_Detail")
                    )
                    stageExample(
                        state: "withdrawing", number: 3,
                        detail: Text("Incursions_Info_Withdrawing_Detail")
                    )
                } header: {
                    Text("Incursions_Info_Stages_Title")
                }
                Section {
                    influenceExample(value: 1, detail: Text("Incursions_Info_Influence_High"))
                    influenceExample(value: 0.5, detail: Text("Incursions_Info_Influence_Medium"))
                    influenceExample(value: 0, detail: Text("Incursions_Info_Influence_Low"))
                    Text("Incursions_Info_Influence_Body")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                } header: {
                    Text("Incursions_Info_Influence_Title")
                } footer: {
                    Text("Incursions_Info_Examples_Note")
                }
                Section {
                    effectRow(icon: "effectcyno", text: Text("Incursions_Info_Jamming"))
                    effectRow(icon: "effecttax", text: Text("Incursions_Info_Bounties"))
                    effectRow(icon: "effectresistancedecrease", text: Text("Incursions_Info_Resistances"))
                    effectRow(icon: "effectdamagedecrease", text: Text("Incursions_Info_Damage"))
                } header: {
                    Text("Incursions_Info_Effects_Title")
                }
                Section {
                    siteInformationRow(
                        title: Text("Incursions_Info_Vanguard"), icon: "incursionlight",
                        firstLabel: Text("Incursions_Info_Resistance_Penalty"), firstValue: "10%",
                        secondLabel: Text("Incursions_Info_Damage_Penalty"), secondValue: "10%"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Assault"), icon: "incursionmedium",
                        firstLabel: Text("Incursions_Info_Resistance_Penalty"), firstValue: "25%",
                        secondLabel: Text("Incursions_Info_Damage_Penalty"), secondValue: "25%"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Headquarters"), icon: "incursionheavy",
                        firstLabel: Text("Incursions_Info_Resistance_Penalty"), firstValue: "50%",
                        secondLabel: Text("Incursions_Info_Damage_Penalty"), secondValue: "50%"
                    )
                } header: {
                    Text("Incursions_Info_Penalties_Title")
                }
                informationSection(
                    title: Text("Incursions_Info_Ending_Title"),
                    body: Text("Incursions_Info_Ending_Body")
                )
                Section {
                    HStack(alignment: .center, spacing: 12) {
                        Image("iconmothership")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                        Text("Incursions_Info_Mothership_Detected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    siteInformationRow(
                        title: Text("Incursions_Info_Staging"), icon: "incursionstaging",
                        firstLabel: Text("Incursions_Info_Max_ISK"), firstValue: "3,500,000",
                        secondLabel: Text("Incursions_Info_Max_LP"), secondValue: "400"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Vanguard"), icon: "incursionlight",
                        firstLabel: Text("Incursions_Info_Max_ISK"), firstValue: "15,000,000",
                        secondLabel: Text("Incursions_Info_Max_LP"), secondValue: "2,000"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Assault"), icon: "incursionmedium",
                        firstLabel: Text("Incursions_Info_Max_ISK"), firstValue: "26,000,000",
                        secondLabel: Text("Incursions_Info_Max_LP"), secondValue: "5,000"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Headquarters"), icon: "incursionheavy",
                        firstLabel: Text("Incursions_Info_Max_ISK"), firstValue: "45,000,000",
                        secondLabel: Text("Incursions_Info_Max_LP"), secondValue: "10,000"
                    )
                } header: {
                    Text("Incursions_Info_Rewards_Title")
                } footer: {
                    Text("Incursions_Info_Rewards_Note")
                }
                informationSection(
                    title: Text("Incursions_Info_LP_Settlement_Title"),
                    body: Text("Incursions_Info_LP_Settlement_Body")
                )
                informationSection(
                    title: Text("Incursions_Info_LP_Uses_Title"),
                    body: Text("Incursions_Info_LP_Uses_Body")
                )
                Section {
                    Text("Incursions_Info_LP_Conversion_Body")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                } header: {
                    Text("Incursions_Info_LP_Conversion_Title")
                } footer: {
                    Text("Incursions_Info_LP_Conversion_Note")
                }
                Section {
                    siteInformationRow(
                        title: Text("Incursions_Info_Staging"), icon: "incursionstaging",
                        firstLabel: Text("Incursions_Info_Optimal_Pilots"), firstValue: "3–5",
                        secondLabel: Text("Incursions_Info_Fleet_Range"), secondValue: "1–3"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Vanguard"), icon: "incursionlight",
                        firstLabel: Text("Incursions_Info_Optimal_Pilots"), firstValue: "5–15",
                        secondLabel: Text("Incursions_Info_Fleet_Range"), secondValue: "1–25"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Assault"), icon: "incursionmedium",
                        firstLabel: Text("Incursions_Info_Optimal_Pilots"), firstValue: "10–30",
                        secondLabel: Text("Incursions_Info_Fleet_Range"), secondValue: "1–40"
                    )
                    siteInformationRow(
                        title: Text("Incursions_Info_Headquarters"), icon: "incursionheavy",
                        firstLabel: Text("Incursions_Info_Optimal_Pilots"), firstValue: "20–60",
                        secondLabel: Text("Incursions_Info_Fleet_Range"), secondValue: "11–70"
                    )
                } header: {
                    Text("Incursions_Info_Fleet_Title")
                } footer: {
                    Text("Incursions_Info_Fleet_Note")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Incursions_Info_Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Common_Done") { dismiss() }
                }
            }
        }
    }

    private func effectRow(icon: String, text: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
            text
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }

    private func siteInformationRow(
        title: Text, icon: String,
        firstLabel: Text, firstValue: String,
        secondLabel: Text, secondValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(icon)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                title
                    .font(.subheadline.weight(.semibold))
            }
            informationValue(label: firstLabel, value: firstValue)
            informationValue(label: secondLabel, value: secondValue)
        }
        .padding(.vertical, 6)
    }

    private func informationValue(label: Text, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                label
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 12)
                Text(verbatim: value)
                    .monospacedDigit()
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                label.foregroundStyle(.secondary)
                Text(verbatim: value).monospacedDigit()
            }
        }
        .font(.subheadline)
    }

    private func informationSection(title: Text, body: Text) -> some View {
        Section {
            body
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        } header: {
            title
        }
    }

    private func stageExample(state: String, number: Int, detail: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IncursionProgressRow.color(for: state))
                .frame(width: 30, height: 30)
                .background(IncursionProgressRow.color(for: state).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(IncursionProgressRow.text(for: state))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IncursionProgressRow.color(for: state))
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    private func influenceExample(value: Double, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IncursionProgressRow(state: "established", influence: value)
            detail
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

#Preview("入侵进度行 - 三种阶段（浅色）") {
    IncursionProgressRowPreviewList()
}

#Preview("入侵进度行 - 三种阶段（深色）") {
    IncursionProgressRowPreviewList()
        .preferredColorScheme(.dark)
}

/// 预览容器：三种阶段 × 多档影响力，在真实 List 行背景下对比两段进度
private struct IncursionProgressRowPreviewList: View {
    private let influences: [Double] = [0, 0.15, 0.35, 0.6, 0.85, 1]

    var body: some View {
        List {
            ForEach(IncursionProgressRow.stateOrder, id: \.self) { state in
                Section {
                    ForEach(influences, id: \.self) { influence in
                        HStack(spacing: 12) {
                            Text("\(FormatUtil.format(influence * 100, maxFractionDigits: 1))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                            IncursionProgressRow(state: state, influence: influence)
                        }
                    }
                } header: {
                    Text(IncursionProgressRow.text(for: state))
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
