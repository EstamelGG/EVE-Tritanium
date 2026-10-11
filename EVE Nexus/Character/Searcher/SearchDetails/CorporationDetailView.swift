import SwiftUI

struct CorporationDetailView: View {
    let corporationId: Int
    let character: EVECharacterInfo
    @State private var logo: UIImage?
    @State private var corporationInfo: CorporationInfo?
    @State private var allianceInfo: (name: String, icon: UIImage?)?
    @State private var factionInfo: (name: String, iconName: String)?
    @State private var ceoInfo: CharacterPublicInfo?
    @State private var ceoPortrait: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    // 声望相关的状态
    @State private var personalStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var allianceStandings: [Int: Double] = [:]
    @State private var myCorpInfo: (name: String, icon: UIImage?)?
    @State private var myAllianceInfo: (name: String, icon: UIImage?)?
    @State private var standingsLoaded = false
    @State private var selectedTab = 0 // 添加选项卡状态
    @State private var allianceHistory: [CorporationAllianceHistory] = []
    @State private var allianceNamesCache: [Int: String] = [:]
    @State private var allianceIconsCache: [Int: UIImage] = [:]
    @State private var isLoadingAllianceNames: Bool = false

    /// 导航辅助方法
    @ViewBuilder
    private func navigationDestination(for id: Int, type: String) -> some View {
        switch type {
        case "character":
            CharacterDetailView(characterId: id, character: character)
        case "alliance":
            AllianceDetailView(allianceId: id, character: character)
        default:
            EmptyView()
        }
    }

    var body: some View {
        List {
            if isLoading {
                DetailLoadingSection()
            } else if let error = error {
                DetailErrorSection(error: error)
            } else if let corporationInfo = corporationInfo {
                // 基本信息和组织信息
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        // 左侧Logo
                        if let logo = logo {
                            Image(uiImage: logo)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.primary, lineWidth: 1)
                                        .opacity(0.3)
                                )
                        }

                        // 右侧信息
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer()
                                .frame(height: 8)

                            // 军团名称
                            Text(corporationInfo.name)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)

                            // 军团代号
                            Text("[\(corporationInfo.ticker)]")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .padding(.top, 2)

                            Spacer()
                                .frame(minHeight: 8)

                            // CEO信息
                            if let ceoInfo = ceoInfo {
                                HStack(spacing: 8) {
                                    if let portrait = ceoPortrait {
                                        Image(uiImage: portrait)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text("\(NSLocalizedString("CEO", comment: "")): ")
                                        .font(.system(size: 14))
                                    Text(ceoInfo.name)
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                }
                            }

                            // 联盟信息
                            HStack(spacing: 8) {
                                if let allianceInfo = allianceInfo, let icon = allianceInfo.icon {
                                    Image(uiImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(allianceInfo.name)
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                } else {
                                    Image(systemName: "square.dashed")
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.gray)
                                    Text("\(NSLocalizedString("No Alliance", comment: ""))")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.top, 4)

                            Spacer()
                                .frame(height: 8)
                        }
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = corporationInfo.name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_CorpID", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }

                            Divider()

                            if ceoInfo != nil {
                                NavigationLink {
                                    navigationDestination(
                                        for: corporationInfo.ceo_id, type: "character"
                                    )
                                } label: {
                                    Label(
                                        NSLocalizedString("View CEO", comment: ""),
                                        systemImage: "info.circle"
                                    )
                                }
                            }
                            if corporationInfo.alliance_id != nil {
                                NavigationLink {
                                    navigationDestination(
                                        for: corporationInfo.alliance_id!, type: "alliance"
                                    )
                                } label: {
                                    Label(
                                        NSLocalizedString("View Alliance", comment: ""),
                                        systemImage: "info.circle"
                                    )
                                }
                            }
                        }
                        .frame(height: 96) // 与Logo等高
                    }
                    .padding(.vertical, 4)
                } footer: {
                    EntityIdCopyFooter(entityId: corporationId)
                }

                // 军团基本信息
                Section {
                    // 势力信息
                    if let faction = factionInfo {
                        EntityFactionRow(factionInfo: faction)
                    }

                    // 成员数量
                    HStack {
                        Text("\(NSLocalizedString("Member Count", comment: ""))")
                        Spacer()
                        Text("\(corporationInfo.member_count)")
                            .foregroundColor(.secondary)
                    }

                    // 税率
                    HStack {
                        Text("\(NSLocalizedString("Tax Rate", comment: ""))")
                        Spacer()
                        Text(String(format: "%.1f%%", corporationInfo.tax_rate * 100))
                            .foregroundColor(.secondary)
                    }

                    // 成立时间
                    if let dateFoundedStr = corporationInfo.date_founded,
                       let dateFounded = ISO8601DateFormatter().date(from: dateFoundedStr)
                    {
                        HStack {
                            Text("\(NSLocalizedString("Main_Founded", comment: ""))")
                            Spacer()
                            Text(dateFounded, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 添加外部链接按钮
                Section {
                    EntityExternalLinkButtons(entityId: corporationId, linkType: .corporation)
                }

                // 军团描述
                if !corporationInfo.description.isEmpty {
                    let description = TextProcessingUtil.processDescription(
                        corporationInfo.description
                    )
                    Section(header: Text("\(NSLocalizedString("Description", comment: ""))")) {
                        Text(description)
                            .font(.system(size: 14))
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = description
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }
                    }
                }
                // 添加Picker组件
                Section {
                    Picker(selection: $selectedTab, label: Text("")) {
                        Text(NSLocalizedString("Standings", comment: ""))
                            .tag(0)
                        Text(NSLocalizedString("Alliance History", comment: ""))
                            .tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if selectedTab == 0 {
                        StandingsView(
                            corporationId: corporationId,
                            character: character,
                            corporationInfo: corporationInfo,
                            allianceInfo: allianceInfo,
                            personalStandings: personalStandings,
                            corpStandings: corpStandings,
                            allianceStandings: allianceStandings,
                            myCorpInfo: myCorpInfo,
                            myAllianceInfo: myAllianceInfo
                        )
                    } else if selectedTab == 1 {
                        AllianceHistoryView(
                            history: allianceHistory, corporationId: corporationId,
                            corporationLogo: logo, allianceNamesCache: allianceNamesCache,
                            allianceIconsCache: $allianceIconsCache,
                            character: character,
                            isLoadingAllianceNames: isLoadingAllianceNames
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCorporationDetails()
        }
    }

    private func loadCorporationDetails() async {
        Logger.info("开始加载军团详细信息 - 军团ID: \(corporationId)")
        isLoading = true
        error = nil

        do {
            // 并发加载所有需要的数据
            Logger.info("开始并发加载军团信息、Logo和联盟历史")
            async let corporationInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corporationId, forceRefresh: true
            )
            async let logoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: corporationId
            )
            async let allianceHistoryTask = CorporationAPI.shared.fetchAllianceHistory(
                corporationId: corporationId
            )

            // 等待所有数据加载完成
            let (info, logo, history) = try await (
                corporationInfoTask, logoTask, allianceHistoryTask
            )
            Logger.success("成功加载军团基本信息")

            // 更新状态
            corporationInfo = info
            self.logo = logo
            allianceHistory = history

            // 加载CEO信息
            if let ceoInfo = try? await CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: info.ceo_id
            ) {
                Logger.success("成功加载CEO信息: \(ceoInfo.name)")
                let ceoPortrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: info.ceo_id, catchImage: false
                )
                self.ceoInfo = ceoInfo
                self.ceoPortrait = ceoPortrait
            }

            // 加载联盟信息
            if let allianceId = info.alliance_id {
                let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [
                    allianceId,
                ])
                if let allianceName = allianceNames?[allianceId]?.name {
                    Logger.success("成功加载联盟信息: \(allianceName)")
                    let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(
                        allianceID: allianceId
                    )
                    allianceInfo = (name: allianceName, icon: allianceIcon)
                }
            }

            // 加载势力信息
            if let factionId = info.faction_id,
               let faction = SDEMemoryStore.faction(for: factionId)
            {
                Logger.success("成功加载势力信息: \(faction.name)")
                factionInfo = (name: faction.name, iconName: faction.iconName)
            }

            // 异步加载联盟历史中的联盟名称（不阻塞UI显示）
            Task {
                await loadAllianceHistoryNames()
            }

            // 加载声望数据
            if !standingsLoaded {
                await loadStandings()
                standingsLoaded = true
            }

        } catch {
            Logger.error("加载军团详细信息失败: \(error)")
            self.error = error
        }

        isLoading = false
        Logger.info("军团详细信息加载完成")
    }

    private func loadAllianceHistoryNames() async {
        await MainActor.run {
            isLoadingAllianceNames = true
        }

        Logger.info(" 开始 loadAllianceHistoryNames")

        // 收集所有联盟历史中的联盟ID（已去重）
        let allianceIds = Array(Set(allianceHistory.compactMap { $0.alliance_id }))
        Logger.info(" 开始批量加载 \(allianceIds.count) 个联盟的名称")

        // 如果没有联盟，直接返回
        if allianceIds.isEmpty {
            Logger.info("[-] 没有联盟需要加载")
            await MainActor.run {
                isLoadingAllianceNames = false
            }
            return
        }

        // 批量获取所有联盟名称
        do {
            let namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: allianceIds)
            await MainActor.run {
                for (allianceId, info) in namesMap {
                    allianceNamesCache[allianceId] = info.name
                }
                Logger.info(" 批量加载联盟历史名称成功，数量: \(namesMap.count)")
            }
        } catch {
            Logger.error("批量获取联盟名称失败: \(error)")
        }

        await MainActor.run {
            isLoadingAllianceNames = false
            Logger.info(" loadAllianceHistoryNames 完成")
        }
    }

    private func loadStandings() async {
        let data = await StandingsLoader.loadStandings(for: character)
        myCorpInfo = data.myCorpInfo
        myAllianceInfo = data.myAllianceInfo
        personalStandings = data.personalStandings
        corpStandings = data.corpStandings
        allianceStandings = data.allianceStandings
    }

    /// 声望详情视图
    struct StandingsView: View {
        let corporationId: Int
        let character: EVECharacterInfo
        let corporationInfo: CorporationInfo
        let allianceInfo: (name: String, icon: UIImage?)?
        let personalStandings: [Int: Double]
        let corpStandings: [Int: Double]
        let allianceStandings: [Int: Double]
        let myCorpInfo: (name: String, icon: UIImage?)?
        let myAllianceInfo: (name: String, icon: UIImage?)?

        var body: some View {
            VStack {
                VStack(alignment: .leading, spacing: 8) {
                    // 军团声望
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Corporation Standings", comment: ""))
                            .font(.headline)
                            .padding(.bottom, 4)

                        // 我对目标军团
                        StandingRowView(
                            leftPortrait: (id: character.CharacterID, type: .character),
                            rightPortrait: (id: corporationId, type: .corporation),
                            leftName: character.CharacterName,
                            rightName: corporationInfo.name,
                            standing: personalStandings[corporationId]
                        )

                        // 我军团对目标军团
                        if let corpId = character.corporationId {
                            StandingRowView(
                                leftPortrait: (id: corpId, type: .corporation),
                                rightPortrait: (id: corporationId, type: .corporation),
                                leftName: myCorpInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                rightName: corporationInfo.name,
                                standing: corpStandings[corporationId]
                            )
                        }

                        // 我联盟对目标军团
                        if let allianceId = character.allianceId {
                            StandingRowView(
                                leftPortrait: (id: allianceId, type: .alliance),
                                rightPortrait: (id: corporationId, type: .corporation),
                                leftName: myAllianceInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                rightName: corporationInfo.name,
                                standing: allianceStandings[corporationId]
                            )
                        }
                    }

                    if let targetAllianceId = corporationInfo.alliance_id {
                        Divider()

                        // 联盟声望
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("Alliance Standings", comment: ""))
                                .font(.headline)
                                .padding(.bottom, 4)

                            // 我对目标联盟
                            StandingRowView(
                                leftPortrait: (id: character.CharacterID, type: .character),
                                rightPortrait: (id: targetAllianceId, type: .alliance),
                                leftName: character.CharacterName,
                                rightName: allianceInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                standing: personalStandings[targetAllianceId]
                            )

                            // 我军团对目标联盟
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (id: targetAllianceId, type: .alliance),
                                    leftName: myCorpInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: allianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: corpStandings[targetAllianceId]
                                )
                            }

                            // 我联盟对目标联盟
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (id: targetAllianceId, type: .alliance),
                                    leftName: myAllianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: allianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: allianceStandings[targetAllianceId]
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 联盟历史视图
struct AllianceHistoryView: View {
    let history: [CorporationAllianceHistory]
    let corporationId: Int
    let corporationLogo: UIImage?
    let allianceNamesCache: [Int: String]
    @Binding var allianceIconsCache: [Int: UIImage]
    let character: EVECharacterInfo
    let isLoadingAllianceNames: Bool

    var body: some View {
        // 过滤掉没有联盟的记录（alliance_id为nil的记录）
        let filteredHistory = history.filter { $0.alliance_id != nil }

        if filteredHistory.isEmpty {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("Misc_No_Data", comment: "无数据"),
                    systemImage: "exclamationmark.triangle"
                )
            }
        } else {
            ForEach(Array(filteredHistory.enumerated()), id: \.element.record_id) { index, record in
                if let startDate = parseDate(record.start_date),
                   let allianceId = record.alliance_id
                {
                    let endDate = index > 0 ? parseDate(filteredHistory[index - 1].start_date) : nil

                    VStack(spacing: 0) {
                        AllianceHistoryRowView(
                            allianceId: allianceId,
                            startDate: startDate,
                            endDate: endDate,
                            corporationId: corporationId,
                            corporationLogo: corporationLogo,
                            allianceNamesCache: allianceNamesCache,
                            allianceIconsCache: $allianceIconsCache,
                            character: character,
                            isLoadingAllianceNames: isLoadingAllianceNames
                        )
                    }
                }
            }
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        return dateFormatter.date(from: dateString)
    }
}

/// 联盟历史行视图
struct AllianceHistoryRowView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let allianceId: Int
    let startDate: Date
    let endDate: Date?
    let corporationId: Int
    let corporationLogo: UIImage?
    let allianceNamesCache: [Int: String]
    @Binding var allianceIconsCache: [Int: UIImage]
    let character: EVECharacterInfo
    let isLoadingAllianceNames: Bool
    @State private var allianceIcon: UIImage?

    var body: some View {
        HStack(spacing: 6) {
            // 联盟图标
            if let icon = allianceIcon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(3)
            } else {
                Color.gray
                    .frame(width: 32, height: 32)
                    .cornerRadius(3)
            }

            // 右侧信息
            VStack(alignment: .leading, spacing: 2) {
                // 联盟名称
                if isLoadingAllianceNames {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(NSLocalizedString("Misc_Loading", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(allianceNamesCache[allianceId] ?? NSLocalizedString("Unknown", comment: ""))
                        .font(.system(size: 12))
                        .lineLimit(1)
                }

                // 时间信息
                HStack(spacing: 4) {
                    Text(FormatUtil.formatHistoryDateRange(start: startDate, end: endDate))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(FormatUtil.formatHistoryDuration(start: startDate, end: endDate))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            // 只有当联盟信息加载完成时才显示跳转按钮
            if !isLoadingAllianceNames {
                NavigationLink {
                    AllianceDetailView(allianceId: allianceId, character: character)
                } label: {
                    Label(
                        NSLocalizedString("View Alliance", comment: ""),
                        systemImage: "info.circle"
                    )
                }
            }
        }
        .task {
            await loadAllianceIcon()
        }
    }

    private func loadAllianceIcon() async {
        // 先检查缓存
        if let cachedIcon = allianceIconsCache[allianceId] {
            await MainActor.run {
                self.allianceIcon = cachedIcon
            }
            return
        }

        // 等待名称加载完成后再加载图标
        // 如果名称还在加载中，等待一下
        var attempts = 0
        while isLoadingAllianceNames, attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }

        // 从API加载联盟图标
        if let icon = try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId) {
            await MainActor.run {
                self.allianceIcon = icon
                // 保存到缓存
                self.allianceIconsCache[allianceId] = icon
            }
        }
    }
}
