import SwiftUI

/// 人物表单子页面：声望与联系人
/// - segmented Picker 切换 Standings / Contacts，切 tab 懒加载
/// - Standings：势力 → 军团 → 代理人，组内名称排序，行含类型标签与声望着色
/// - Contacts：faction → alliance → corporation → character，组内名称排序，
///   行尾 is_blocked → restriction / is_watched → contacts 图标
struct CharacterStandingsContactsPage: View {
    let character: EVECharacterInfo

    @State private var selectedTab = 0 // 0 = Standings, 1 = Contacts
    @State private var standingsLoaded = false
    @State private var contactsLoaded = false

    @State private var standingsRows: [StandingRowItem] = []
    @State private var isLoadingStandings = true

    @State private var contactsRows: [ContactRowItem] = []
    @State private var isLoadingContacts = true

    /// 军团/联盟归属与 logo 的页面级缓存（同实体去重，避免行级重复请求）
    @StateObject private var entityCache = ContactEntityCache()

    // MARK: - Contacts 筛选

    /// 声望筛选（nil = 全部；ESI 联系人声望为离散档位 +10/+5/0/-5/-10）
    @State private var standingFilter: Double?
    @State private var blockedOnly = false
    @State private var watchedOnly = false

    private var hasActiveFilter: Bool {
        standingFilter != nil || blockedOnly || watchedOnly
    }

    /// 应用筛选后的联系人列表（保持原排序）
    private var filteredContacts: [ContactRowItem] {
        contactsRows.filter { contact in
            if let standingFilter, contact.standing != standingFilter {
                return false
            }
            if blockedOnly, !contact.isBlocked {
                return false
            }
            if watchedOnly, !contact.isWatched {
                return false
            }
            return true
        }
    }

    var body: some View {
        List {
            Section {
                Picker(selection: $selectedTab) {
                    Text(NSLocalizedString("Standings", comment: "")).tag(0)
                    Text(NSLocalizedString("Contacts", comment: "")).tag(1)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)

                if selectedTab == 0 {
                    if isLoadingStandings {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(standingsRows) { row in
                            StandingEntryRow(item: row)
                                .listRowInsets(standingsContactsRowInsets)
                        }
                    }
                } else {
                    if isLoadingContacts {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if filteredContacts.isEmpty {
                        Text(NSLocalizedString("Main_EVE_Mail_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(filteredContacts) { row in
                            ContactRowView(item: row, character: character, cache: entityCache)
                                .listRowInsets(standingsContactsRowInsets)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Character_Standings_Contacts", comment: "声望与联系人"))
        .toolbar {
            // 仅 Contacts 标签显示筛选菜单
            ToolbarItem(placement: .navigationBarTrailing) {
                if selectedTab == 1 {
                    Menu {
                        // .inline 避免在 macOS 上被折叠为子菜单；数字项用 verbatim 不进本地化
                        Picker(selection: $standingFilter, label: Text("")) {
                            Text(NSLocalizedString("Misc_All", comment: "")).tag(Double?.none)
                            Text(verbatim: "+10").tag(Double?.some(10))
                            Text(verbatim: "+5").tag(Double?.some(5))
                            Text(verbatim: "0").tag(Double?.some(0))
                            Text(verbatim: "-5").tag(Double?.some(-5))
                            Text(verbatim: "-10").tag(Double?.some(-10))
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Toggle(isOn: $blockedOnly) {
                            Text(NSLocalizedString("Contacts_Blocked", comment: "已屏蔽"))
                        }

                        Toggle(isOn: $watchedOnly) {
                            Text(NSLocalizedString("Contacts_Watched", comment: "已关注"))
                        }
                    } label: {
                        Image(
                            systemName: hasActiveFilter
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
            }
        }
        .task {
            if !standingsLoaded {
                await loadStandings()
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == 1, !contactsLoaded {
                Task { await loadContacts() }
            }
        }
        .refreshable {
            if selectedTab == 0 {
                await loadStandings(forceRefresh: true)
            } else {
                await loadContacts(forceRefresh: true)
            }
        }
    }

    // MARK: - 加载

    /// 声望：faction/npc_corp 名称走 SDE（零网络），agent 名称走本地库优先的批量解析
    private func loadStandings(forceRefresh: Bool = false) async {
        isLoadingStandings = true
        defer { standingsLoaded = true }

        guard
            let data = try? await CharacterStandingsAPI.shared.fetchStandings(
                characterId: character.CharacterID, forceRefresh: forceRefresh
            )
        else {
            isLoadingStandings = false
            return
        }

        // agent 名称单独批量解析（agents 表本地优先，未命中才走网络）
        let agentIds = data.filter { $0.from_type == "agent" }.map { $0.from_id }
        var agentNames: [Int: String] = [:]
        if !agentIds.isEmpty,
           let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(ids: agentIds)
        {
            for (id, info) in namesMap {
                agentNames[id] = info.name
            }
        }

        let rows = data.compactMap { standing -> StandingRowItem? in
            let name: String
            var iconFileName: String?
            var sortOrder: Int
            switch standing.from_type {
            case "faction":
                guard let faction = SDEMemoryStore.faction(for: standing.from_id) else {
                    return nil
                }
                name = faction.name
                iconFileName = faction.iconName
                sortOrder = 0
            case "npc_corp":
                guard let corp = SDEMemoryStore.npcCorporation(for: standing.from_id) else {
                    return nil
                }
                name = corp.name
                iconFileName = corp.iconFilename.isEmpty ? "corporation_default" : corp.iconFilename
                sortOrder = 1
            case "agent":
                name = agentNames[standing.from_id] ?? "Unknown (\(standing.from_id))"
                sortOrder = 2
            default:
                return nil
            }

            return StandingRowItem(
                id: standing.from_id,
                type: standing.from_type,
                name: name,
                iconFileName: iconFileName,
                standing: standing.standing,
                sortOrder: sortOrder
            )
        }
        .sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            standingsRows = rows
            isLoadingStandings = false
        }
    }

    /// 联系人：faction 名称优先 SDE，其余批量解析（本地库优先，分批 ≤1000）
    private func loadContacts(forceRefresh: Bool = false) async {
        isLoadingContacts = true
        defer { contactsLoaded = true }

        guard
            let data = try? await GetCharContacts.shared.fetchContacts(
                characterId: character.CharacterID, forceRefresh: forceRefresh
            )
        else {
            isLoadingContacts = false
            return
        }

        var names: [Int: String] = [:]
        for contact in data where contact.contact_type == "faction" {
            if let faction = SDEMemoryStore.faction(for: contact.contact_id) {
                names[contact.contact_id] = faction.name
            }
        }

        let missingIds = data.map { $0.contact_id }.filter { names[$0] == nil }
        if !missingIds.isEmpty,
           let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(ids: missingIds)
        {
            for (id, info) in namesMap {
                names[id] = info.name
            }
        }

        let typeOrder = ["faction": 0, "alliance": 1, "corporation": 2, "character": 3]
        let rows = data.compactMap { contact -> ContactRowItem? in
            // faction 联系人无法解析名称时跳过（SDE 缺失）
            if contact.contact_type == "faction", names[contact.contact_id] == nil {
                return nil
            }
            return ContactRowItem(
                id: contact.contact_id,
                contactType: contact.contact_type,
                name: names[contact.contact_id] ?? "Unknown (\(contact.contact_id))",
                standing: contact.standing,
                isBlocked: contact.is_blocked ?? false,
                isWatched: contact.is_watched ?? false,
                sortOrder: typeOrder[contact.contact_type] ?? 4
            )
        }
        .sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            contactsRows = rows
            isLoadingContacts = false
        }

        // 归属与 logo 批量预载（同军团/联盟去重，刷新时强制重载）
        await entityCache.loadIfNeeded(contacts: rows, force: forceRefresh)
    }
}

// MARK: - 行数据模型（文件内共用）

/// 行统一 inset（与人物表单其他列表一致）
private let standingsContactsRowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

/// 声望值格式化：整数不带小数位，非整数保留一位
private func formatStandingValue(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%+.0f", value)
        : String(format: "%+.1f", value)
}

/// 声望行：faction/npc_corp 用本地图标，agent 用异步头像
private struct StandingRowItem: Identifiable {
    let id: Int // from_id
    let type: String // faction / npc_corp / agent
    let name: String
    let iconFileName: String? // faction/npc_corp 本地图标；agent 为 nil（用头像）
    let standing: Double
    let sortOrder: Int // faction = 0, npc_corp = 1, agent = 2
}

/// 联系人行
private struct ContactRowItem: Identifiable {
    let id: Int // contact_id
    let contactType: String // faction / alliance / corporation / character
    let name: String
    let standing: Double
    let isBlocked: Bool
    let isWatched: Bool
    let sortOrder: Int // faction = 0, alliance = 1, corporation = 2, character = 3
}

/// 联系人归属条目：人物 → 军团、联盟各一行；军团 → 联盟一行
private struct AffiliationEntry: Identifiable {
    let id: Int // 军团/联盟 ID
    let name: String
    let isAlliance: Bool // 决定 logo 加载方式
}

/// 联系人实体信息缓存（参考 EmploymentAllianceCache）
/// - 相同军团/联盟只请求一次：publicInfo 并发去重 → 名称一次批量 → logo 去重预载
/// - 行视图直接读缓存，避免滚动时行级重复请求触发 ESI 限速
@MainActor
private final class ContactEntityCache: ObservableObject {
    /// 联系人 ID → 归属条目（人物 → [军团, 联盟]；军团 → [联盟]）
    @Published private(set) var affiliations: [Int: [AffiliationEntry]] = [:]
    /// 军团/联盟 ID → logo（归属行与军团/联盟联系人主图标共用）
    @Published private(set) var logos: [Int: UIImage] = [:]

    private var isLoaded = false
    private var lastContactIds: Set<Int> = []

    func loadIfNeeded(contacts: [ContactRowItem], force: Bool = false) async {
        let contactIds = Set(contacts.map(\.id))
        guard force || !isLoaded || lastContactIds != contactIds else { return }
        isLoaded = true
        lastContactIds = contactIds

        // 1. 人物联系人并发拉 publicInfo、军团联系人拉 corpInfo（各自有 ESI 缓存层）
        var characterCorp: [Int: Int] = [:]
        var characterAlliance: [Int: Int] = [:]
        var corpAlliance: [Int: Int] = [:] // 军团联系人 → 联盟

        await withTaskGroup(of: (Int, String, Int?, Int?).self) { group in
            for contact in contacts {
                group.addTask {
                    switch contact.contactType {
                    case "character":
                        let info = try? await CharacterAPI.shared.fetchCharacterPublicInfo(
                            characterId: contact.id
                        )
                        return (contact.id, "character", info?.corporation_id, info?.alliance_id)
                    case "corporation":
                        let corp = try? await CorporationAPI.shared.fetchCorporationInfo(
                            corporationId: contact.id
                        )
                        return (contact.id, "corporation", nil, corp?.alliance_id)
                    default:
                        return (contact.id, "other", nil, nil)
                    }
                }
            }
            for await (id, kind, corpId, allianceId) in group {
                if kind == "character", let corpId {
                    characterCorp[id] = corpId
                    if let allianceId {
                        characterAlliance[id] = allianceId
                    }
                } else if kind == "corporation", let allianceId {
                    corpAlliance[id] = allianceId
                }
            }
        }

        // 2. 汇总唯一军团/联盟 ID（含军团/联盟联系人自身，供行首图标使用），名称一次批量解析
        let corpContactIds = Set(
            contacts.filter { $0.contactType == "corporation" }.map(\.id)
        )
        let allianceContactIds = Set(
            contacts.filter { $0.contactType == "alliance" }.map(\.id)
        )
        let corpIdSet = Set(characterCorp.values).union(corpContactIds)
        let allianceIdSet = Set(characterAlliance.values)
            .union(corpAlliance.values)
            .union(allianceContactIds)
        var entityIds = corpIdSet.union(allianceIdSet)

        var names: [Int: (name: String, category: String)] = [:]
        if !entityIds.isEmpty,
           let map = try? await UniverseAPI.shared.getNamesWithFallback(ids: Array(entityIds))
        {
            names = map
        }

        func resolvedName(_ id: Int) -> String? {
            // 过滤 ID 兜底条目（category == "unknown" 表示解析失败，name 是纯数字 ID）
            guard let info = names[id], info.category != "unknown" else { return nil }
            return info.name
        }

        // 3. 构建归属（过滤解析失败的条目，避免显示数字串）
        var result: [Int: [AffiliationEntry]] = [:]
        for (contactId, corpId) in characterCorp {
            var entries: [AffiliationEntry] = []
            if let name = resolvedName(corpId) {
                entries.append(AffiliationEntry(id: corpId, name: name, isAlliance: false))
            }
            if let allianceId = characterAlliance[contactId], let name = resolvedName(allianceId) {
                entries.append(AffiliationEntry(id: allianceId, name: name, isAlliance: true))
            }
            if !entries.isEmpty {
                result[contactId] = entries
            }
        }
        for (contactId, allianceId) in corpAlliance {
            if let name = resolvedName(allianceId) {
                result[contactId] = [AffiliationEntry(id: allianceId, name: name, isAlliance: true)]
            }
        }
        affiliations = result

        // 4. 唯一实体 logo 并发预载（去重后同实体只请求一次）
        entityIds = entityIds.filter { logos[$0] == nil }
        guard !entityIds.isEmpty else { return }
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for id in entityIds {
                if corpIdSet.contains(id) {
                    group.addTask {
                        (id, try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: id))
                    }
                } else {
                    group.addTask {
                        (id, try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: id))
                    }
                }
            }
            for await (id, image) in group {
                if let image {
                    logos[id] = image
                }
            }
        }
    }
}

// MARK: - 行视图

/// 声望行：图标（agent 为异步头像）+ 名称 + 类型标签 + 声望着色
private struct StandingEntryRow: View {
    let item: StandingRowItem

    @State private var portraitImage: Image?

    var body: some View {
        HStack(spacing: 12) {
            if let iconFileName = item.iconFileName {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            } else if let portraitImage {
                portraitImage
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            } else {
                Image("default_char")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)

                typeTag
            }

            Spacer()

            Text(formatStandingValue(item.standing))
                .foregroundColor(standingColor(item.standing))
        }
        .task {
            // agent 行无本地图标，异步加载头像
            guard item.iconFileName == nil, portraitImage == nil else { return }
            if let uiImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
                characterId: item.id, size: 128, forceRefresh: false, catchImage: true
            ) {
                portraitImage = Image(uiImage: uiImage)
            }
        }
    }

    private var typeTag: some View {
        let (text, color): (String, Color) = {
            switch item.type {
            case "faction":
                return (NSLocalizedString("Character_Tag_Faction", comment: "势力标签"), .blue)
            case "npc_corp":
                return (NSLocalizedString("Character_Tag_Corporation", comment: "军团标签"), .teal)
            default:
                return (NSLocalizedString("Character_Tag_Agent", comment: "代理人标签"), .orange)
            }
        }()

        return Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

/// 联系人行：图标（faction 本地 / 人物头像行级 / 军团/联盟 logo 走缓存）
/// + 名称（右侧内联 watched/blocked 图标）+ 归属行（读缓存）+ 声望着色（固定行尾最右）
private struct ContactRowView: View {
    let item: ContactRowItem
    let character: EVECharacterInfo
    @ObservedObject var cache: ContactEntityCache

    /// 人物联系人头像（行级按需，数量与联系人数一致不适合全量预载）
    @State private var iconImage: Image?

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name)
                        .lineLimit(1)

                    if item.isWatched {
                        Image("contacts")
                            .resizable()
                            .frame(width: 16, height: 16)
                    }

                    if item.isBlocked {
                        Image("restriction")
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }

                ForEach(cache.affiliations[item.id] ?? []) { entry in
                    HStack(spacing: 4) {
                        if let logo = cache.logos[entry.id] {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .cornerRadius(2)
                        } else {
                            Image(systemName: "square.dashed")
                                .resizable()
                                .frame(width: 14, height: 14)
                                .foregroundColor(.gray)
                        }

                        Text(entry.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(formatStandingValue(item.standing))
                .foregroundColor(standingColor(item.standing))
        }
        .contextMenu {
            // 主体详情（faction 无详情页）
            switch item.contactType {
            case "character":
                NavigationLink {
                    CharacterDetailView(characterId: item.id, character: character)
                } label: {
                    Label(
                        NSLocalizedString("View Character", comment: ""),
                        systemImage: "info.circle"
                    )
                }
            case "corporation":
                NavigationLink {
                    CorporationDetailView(corporationId: item.id, character: character)
                } label: {
                    Label(
                        NSLocalizedString("View Corporation", comment: ""),
                        systemImage: "info.circle"
                    )
                }
            case "alliance":
                NavigationLink {
                    AllianceDetailView(allianceId: item.id, character: character)
                } label: {
                    Label(
                        NSLocalizedString("View Alliance", comment: ""),
                        systemImage: "info.circle"
                    )
                }
            default:
                EmptyView()
            }

            // 归属跳转（人物 → 军团/联盟；军团 → 联盟），与雇佣历史菜单设计一致
            ForEach(cache.affiliations[item.id] ?? []) { entry in
                if entry.isAlliance {
                    NavigationLink {
                        AllianceDetailView(allianceId: entry.id, character: character)
                    } label: {
                        Label(
                            NSLocalizedString("View Alliance", comment: ""),
                            systemImage: "info.circle"
                        )
                    }
                } else {
                    NavigationLink {
                        CorporationDetailView(corporationId: entry.id, character: character)
                    } label: {
                        Label(
                            NSLocalizedString("View Corporation", comment: ""),
                            systemImage: "info.circle"
                        )
                    }
                }
            }
        }
        .task {
            await loadPortraitIfNeeded()
        }
    }

    /// 行首图标：faction → SDE 本地；character → 行级头像；corporation/alliance → 缓存 logo
    @ViewBuilder
    private var leadingIcon: some View {
        switch item.contactType {
        case "faction":
            if let faction = SDEMemoryStore.faction(for: item.id) {
                IconManager.shared.loadImage(for: faction.iconName)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
        case "character":
            if let iconImage {
                iconImage
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            } else {
                Image("default_char")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
        default:
            // corporation / alliance：读页面级缓存 logo（@Published 驱动自动刷新）
            if let logo = cache.logos[item.id] {
                Image(uiImage: logo)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            } else {
                Image("default_char")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
        }
    }

    private func loadPortraitIfNeeded() async {
        guard item.contactType == "character", iconImage == nil else { return }
        if let uiImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
            characterId: item.id, size: 128, forceRefresh: false, catchImage: true
        ) {
            iconImage = Image(uiImage: uiImage)
        }
    }
}
