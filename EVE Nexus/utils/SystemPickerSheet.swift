import SwiftUI

/// 通用星系选择器：第一层星域（安等分布条 + 星系数量），第二层按星座分组的星系；
/// 第一层搜索时跨星域直接匹配星系（"匹配星系"分组），点击即选中。
///
/// - `includeSystem`: 星系纳入谓词（nil = 全部星系），统计与搜索均遵循该谓词；参数为 (星系ID, 星系信息)
/// - `showsSovereignty`: 星系行显示主权（联盟/派系）图标与名称，如跳跃导航场景
struct SystemPickerSheet: View {
    let title: String
    let currentSelection: Int?
    let includeSystem: ((Int, SDEMemoryStore.UniverseSystemInfo) -> Bool)?
    let showsSovereignty: Bool
    let onSelect: (Int, String) -> Void
    let onCancel: () -> Void

    /// 星域空间统计：总星系数与高安/低安/00 分布
    struct RegionStat {
        var total = 0
        var hisec = 0
        var lowsec = 0
        var nullsec = 0
    }

    /// 星域条目
    struct RegionEntry: Identifiable {
        let id: Int
        let name: String
    }

    /// 全局搜索命中的星系条目
    struct MatchedSystem: Identifiable {
        let id: Int
        let name: String
        let security: Double
        let regionName: String
    }

    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isPreparing = true
    /// 全量星域列表（过滤基准，不可被搜索结果覆盖）
    @State private var allRegions: [RegionEntry] = []
    /// 首字母 → 星域分组
    @State private var regionSections: [String: [RegionEntry]] = [:]
    @State private var sectionTitles: [String] = []
    @State private var regionStats: [Int: RegionStat] = [:]
    /// 主权信息（showsSovereignty 时启用，按需加载）
    @StateObject private var sovereigntyVM = PlanetarySearchResultViewModel()
    /// 搜索命中星系的主权加载任务（去抖）
    @State private var sovereigntyLoadTask: Task<Void, Never>?

    init(
        title: String,
        currentSelection: Int? = nil,
        includeSystem: ((Int, SDEMemoryStore.UniverseSystemInfo) -> Bool)? = nil,
        showsSovereignty: Bool = false,
        onSelect: @escaping (Int, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.currentSelection = currentSelection
        self.includeSystem = includeSystem
        self.showsSovereignty = showsSovereignty
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            Group {
                if isPreparing {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        Text(NSLocalizedString("PI_Output_Loading_Systems", comment: ""))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    regionLevelList
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Common_Cancel", comment: "取消")) {
                        onCancel()
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            prompt: NSLocalizedString("System_Search_Placeholder", comment: "搜索星系...")
        )
        .onChange(of: searchText) { _, _ in
            updateSections()
            scheduleSovereigntyLoadForMatches()
        }
        .onChange(of: isSearchActive) { _, _ in
            updateSections()
        }
        .onAppear {
            prepareRegions()
        }
    }

    // MARK: - 第一层：星域列表

    private var regionLevelList: some View {
        List {
            // 搜索无结果时的指引
            if !searchText.isEmpty, matchedSystems.isEmpty, sectionTitles.isEmpty {
                Section {
                    Text(NSLocalizedString("System_Search_No_Match", comment: "未找到匹配的星域或星系"))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 搜索时：跨星域直接匹配星系
            if !matchedSystems.isEmpty {
                Section(header: Text(NSLocalizedString("System_Search_Matched_Systems", comment: "匹配星系"))) {
                    ForEach(matchedSystems) { system in
                        systemRow(
                            id: system.id,
                            name: system.name,
                            security: system.security,
                            regionName: system.regionName
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 星域按首字母分组；每行带安等分布条与星系数量
            ForEach(sectionTitles, id: \.self) { sectionTitle in
                if let regionsInSection = regionSections[sectionTitle], !regionsInSection.isEmpty {
                    Section(header: Text(sectionTitle).id(sectionTitle)) {
                        ForEach(regionsInSection) { region in
                            NavigationLink {
                                RegionSystemsLevelView(
                                    regionId: region.id,
                                    regionName: region.name,
                                    currentSelection: currentSelection,
                                    showsSovereignty: showsSovereignty,
                                    sovereigntyVM: sovereigntyVM,
                                    includeSystem: includeSystem,
                                    onSelect: onSelect
                                )
                            } label: {
                                regionRow(region: region)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
    }

    /// 星域行：星域名 + 安等分布条 + 星系数量
    private func regionRow(region: RegionEntry) -> some View {
        HStack(spacing: 12) {
            Text(region.name)
                .foregroundColor(.primary)

            Spacer()

            if let stat = regionStats[region.id] {
                SecurityDistributionBar(stat: stat)
                    .frame(width: 48, height: 4)

                Text("\(stat.total)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
            }
        }
    }

    /// 星系行：安等数字 + 星系名（+ 星域名），主权模式下附主权图标与名称
    private func systemRow(id: Int, name: String, security: Double, regionName: String?) -> some View {
        Button(action: {
            onSelect(id, name)
        }) {
            SystemRowView(
                name: name,
                security: security,
                regionName: regionName,
                isSelected: currentSelection == id,
                showsSovereignty: showsSovereignty,
                sovereigntyIcon: showsSovereignty ? sovereigntyVM.getIconForSystem(id) : nil,
                sovereigntyName: showsSovereignty ? sovereigntyVM.getOwnerNameForSystem(id) : nil,
                isSovereigntyLoading: showsSovereignty
                    && (sovereigntyVM.isLoadingSovereignty || sovereigntyVM.isLoadingIconForSystem(id))
            )
        }
    }

    /// 搜索命中的跨星域星系（限制数量，避免一次性渲染过多）
    private var matchedSystems: [MatchedSystem] {
        guard !searchText.isEmpty else { return [] }

        var results: [MatchedSystem] = []
        for (systemId, names) in SDEMemoryStore.solarSystemNames {
            guard names.matchesSearch(searchText),
                  let info = SDEMemoryStore.universeSystems[systemId],
                  includeSystem?(systemId, info) ?? true
            else { continue }
            let name = names.resolved()
            guard !name.isEmpty else { continue }
            let regionName = SDEMemoryStore.regionNames[info.regionID]?.resolved() ?? ""
            results.append(
                MatchedSystem(id: systemId, name: name, security: info.security, regionName: regionName)
            )
        }

        return Array(
            results
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(50)
        )
    }

    /// 加载星域并按谓词聚合安等分布（同 RegionSearchView 的数据口径）
    private func prepareRegions() {
        guard allRegions.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let loaded: [RegionEntry] = SDEMemoryStore.regionNames.compactMap { id, text in
                guard id < 11_000_000 else { return nil }
                let name = text.resolved()
                guard !name.isEmpty else { return nil }
                return RegionEntry(id: id, name: name)
            }

            // 一次遍历聚合每个星域的星系数与安等分布（应用谓词）
            var stats: [Int: RegionStat] = [:]
            for (systemId, info) in SDEMemoryStore.universeSystems {
                guard includeSystem?(systemId, info) ?? true else { continue }
                var stat = stats[info.regionID] ?? RegionStat()
                stat.total += 1
                Self.classifySecurity(info.security, into: &stat)
                stats[info.regionID] = stat
            }

            // 无可选星系的星域不显示
            let visibleRegions = loaded.filter { stats[$0.id] != nil }

            DispatchQueue.main.async {
                regionStats = stats
                allRegions = visibleRegions
                regionSections = Self.groupByFirstLetter(visibleRegions)
                sectionTitles = regionSections.keys.sorted()
                isPreparing = false
                // 主权信息不在此处全量加载：进入第二层或搜索命中时按需加载（避免上千星系的映射与图标请求）
            }
        }
    }

    /// 按安全类别归类到高安/低安/00（复用 SolarSystem.swift 的 getSecurityClass）
    private static func classifySecurity(_ security: Double, into stat: inout RegionStat) {
        switch getSecurityClass(trueSec: security) {
        case .highSec:
            stat.hisec += 1
        case .lowSec:
            stat.lowsec += 1
        case .nullSecOrWH:
            stat.nullsec += 1
        }
    }

    /// 按首字母分组（包括中文拼音），组内按名称排序
    private static func groupByFirstLetter(_ regions: [RegionEntry]) -> [String: [RegionEntry]] {
        let grouped = Dictionary(grouping: regions) { region -> String in
            guard let firstChar = region.name.first else { return "#" }
            return Self.firstLetter(of: String(firstChar))
        }

        var result = grouped
        for (key, _) in result {
            result[key]?.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return result
    }

    private static func firstLetter(of char: String) -> String {
        let uppercaseChar = char.uppercased()

        if uppercaseChar >= "A" && uppercaseChar <= "Z" {
            return uppercaseChar
        }

        let pinyin = NSMutableString(string: char) as CFMutableString
        CFStringTransform(pinyin, nil, kCFStringTransformToLatin, false)
        CFStringTransform(pinyin, nil, kCFStringTransformStripDiacritics, false)

        if let firstPinyinChar = String(pinyin as String).first {
            let letter = String(firstPinyinChar).uppercased()
            if letter >= "A" && letter <= "Z" {
                return letter
            }
        }

        return "#"
    }

    /// 搜索过滤后重新分组星域
    private func updateSections() {
        guard !isPreparing else { return }

        var filtered = allRegions
        if !searchText.isEmpty {
            filtered = allRegions.filter { region in
                SDEMemoryStore.regionNames[region.id]?.matchesSearch(searchText) == true
            }
        }

        regionSections = Self.groupByFirstLetter(filtered)
        sectionTitles = regionSections.keys.sorted()
    }

    /// 搜索命中星系的主权按需加载（300ms 去抖，仅命中列表 ≤50 个星系）
    private func scheduleSovereigntyLoadForMatches() {
        guard showsSovereignty, !searchText.isEmpty else {
            sovereigntyLoadTask?.cancel()
            return
        }

        sovereigntyLoadTask?.cancel()
        sovereigntyLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let ids = matchedSystems.map { $0.id }
            guard !ids.isEmpty else { return }
            sovereigntyVM.loadSovereigntyData(forSystemIds: ids)
        }
    }
}

/// 可复用星系行视图：安等数字 + 星系名（安等色着色），可选星域后缀与选中标记；
/// `showsSovereignty` 时切换为两行布局（主权图标 + 主权名），图标加载中显示 ProgressView
struct SystemRowView: View {
    let name: String
    let security: Double
    /// 星域名后缀（如第一层搜索结果，跨星域时用于区分）
    var regionName: String? = nil
    var isSelected: Bool = false
    var showsSovereignty: Bool = false
    var sovereigntyIcon: Image? = nil
    var sovereigntyName: String? = nil
    var isSovereigntyLoading: Bool = false

    var body: some View {
        if showsSovereignty {
            sovereigntyBody
        } else {
            plainBody
        }
    }

    /// 单行布局
    private var plainBody: some View {
        HStack(spacing: 8) {
            securityText(.body)
            nameText
            regionSuffix
            Spacer()
            selectionMark
        }
    }

    /// 两行布局：主权图标 + （主行 / 主权名）
    private var sovereigntyBody: some View {
        HStack(spacing: 10) {
            ZStack {
                if isSovereigntyLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else if let icon = sovereigntyIcon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .cornerRadius(5)
                } else {
                    Image("faction_default")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .cornerRadius(5)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    securityText(.callout)
                    nameText
                    Spacer()
                    selectionMark
                }

                // 主权名三态：已加载 → 名称；加载中 → 占位（redacted）；确认无主权 → 提示文案
                sovereigntyNameText
            }
        }
    }

    @ViewBuilder
    private var sovereigntyNameText: some View {
        let noSovereignty = NSLocalizedString("Jump_Navigation_No_Sovereignty", comment: "无主权")
        if let sovereigntyName = sovereigntyName {
            Text(sovereigntyName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if isSovereigntyLoading {
            Text(noSovereignty)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .redacted(reason: .placeholder)
        } else {
            Text(noSovereignty)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    /// 安等数字（按安等着色的等宽字体）
    private func securityText(_ style: Font.TextStyle) -> some View {
        Text(formatSystemSecurity(security))
            .foregroundColor(getSecurityColor(security))
            .font(.system(style, design: .monospaced))
    }

    private var nameText: some View {
        Text(name)
            .foregroundColor(.primary)
    }

    @ViewBuilder
    private var regionSuffix: some View {
        if let regionName = regionName {
            Text("/ \(regionName)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .foregroundColor(.blue)
        }
    }
}

/// 三段安等分布条：高安（绿）/ 低安（橙）/ 00（紫），宽度按星系比例
private struct SecurityDistributionBar: View {
    let stat: SystemPickerSheet.RegionStat

    var body: some View {
        SegmentedProgressBar(segments: [
            .init(value: Double(stat.hisec), color: getSecurityColor(0.6)),
            .init(value: Double(stat.lowsec), color: getSecurityColor(0.4)),
            .init(value: Double(stat.nullsec), color: getSecurityColor(-0.3)),
        ])
        .frame(width: 48)
    }
}

/// 第二层：星域内星系，按星座分组
private struct RegionSystemsLevelView: View {
    let regionId: Int
    let regionName: String
    let currentSelection: Int?
    let showsSovereignty: Bool
    @ObservedObject var sovereigntyVM: PlanetarySearchResultViewModel
    let includeSystem: ((Int, SDEMemoryStore.UniverseSystemInfo) -> Bool)?
    let onSelect: (Int, String) -> Void

    struct SystemEntry: Identifiable {
        let id: Int
        let name: String
        let security: Double
        let constellationId: Int
    }

    /// 星座分组
    struct ConstellationGroup: Identifiable {
        let name: String
        let systems: [SystemEntry]
        var id: String {
            name
        }
    }

    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var systems: [SystemEntry] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text(NSLocalizedString("Loading_Systems", comment: "加载星系中..."))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                List {
                    if constellationGroups.isEmpty {
                        Section {
                            Text(NSLocalizedString("System_Search_No_Match", comment: "未找到匹配的星域或星系"))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    ForEach(constellationGroups) { group in
                        Section(header: constellationHeader(group)) {
                            ForEach(group.systems) { system in
                                systemRow(system)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(regionName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            prompt: NSLocalizedString("System_Search_Placeholder", comment: "搜索星系...")
        )
        .onAppear {
            loadSystems()
        }
    }

    /// 星座分组：搜索过滤后按星座名分组排序，组内星系按名称排序
    private var constellationGroups: [ConstellationGroup] {
        let filtered: [SystemEntry]
        if searchText.isEmpty {
            filtered = systems
        } else {
            filtered = systems.filter { system in
                SDEMemoryStore.solarSystemNames[system.id]?.matchesSearch(searchText) == true
            }
        }

        let grouped = Dictionary(grouping: filtered) { system in
            SDEMemoryStore.constellationNames[system.constellationId]?.resolved() ?? "#"
        }

        return grouped
            .map { name, list in
                ConstellationGroup(
                    name: name,
                    systems: list.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 星座 Section 头：星座名居左，星系计数居右
    private func constellationHeader(_ group: ConstellationGroup) -> some View {
        HStack {
            Text(group.name)

            Spacer()

            Text("\(group.systems.count)")
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 星系行：安等数字 + 星系名；主权模式下附主权图标与名称
    private func systemRow(_ system: SystemEntry) -> some View {
        Button(action: {
            onSelect(system.id, system.name)
        }) {
            SystemRowView(
                name: system.name,
                security: system.security,
                isSelected: currentSelection == system.id,
                showsSovereignty: showsSovereignty,
                sovereigntyIcon: showsSovereignty ? sovereigntyVM.getIconForSystem(system.id) : nil,
                sovereigntyName: showsSovereignty ? sovereigntyVM.getOwnerNameForSystem(system.id) : nil,
                isSovereigntyLoading: showsSovereignty
                    && (sovereigntyVM.isLoadingSovereignty || sovereigntyVM.isLoadingIconForSystem(system.id))
            )
        }
    }

    /// 从内存索引加载该星域的星系（含星座ID，应用谓词）
    private func loadSystems() {
        guard systems.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let loaded: [SystemEntry] = SDEMemoryStore.universeSystems.compactMap { systemId, info in
                guard info.regionID == regionId,
                      includeSystem?(systemId, info) ?? true,
                      let names = SDEMemoryStore.solarSystemNames[systemId]
                else { return nil }
                let name = names.resolved()
                guard !name.isEmpty else { return nil }
                return SystemEntry(
                    id: systemId,
                    name: name,
                    security: info.security,
                    constellationId: info.constellationID
                )
            }

            DispatchQueue.main.async {
                systems = loaded
                isLoading = false

                // 主权按需加载：仅当前星域内的星系（几十至几百个）
                if showsSovereignty, !loaded.isEmpty {
                    sovereigntyVM.loadSovereigntyData(forSystemIds: loaded.map { $0.id })
                }
            }
        }
    }
}
