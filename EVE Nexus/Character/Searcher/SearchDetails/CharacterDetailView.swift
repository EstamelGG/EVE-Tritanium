import SwiftUI

/// 移除HTML标签的扩展
private extension String {
    func removeHTMLTags() -> String {
        // 移除所有HTML标签
        let text = replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        // 将HTML实体转换为对应字符
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CharacterDetailView: View {
    let characterId: Int
    let character: EVECharacterInfo
    @State private var portrait: UIImage?
    @State private var characterInfo: CharacterPublicInfo?
    @State private var employmentHistory: [CharacterEmploymentHistory] = []
    @State private var corporationInfo: (name: String, icon: UIImage?)?
    @State private var allianceInfo: (name: String, icon: UIImage?)?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var selectedTab = 0 // 添加选项卡状态
    // 添加声望相关的状态
    @State private var personalStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var allianceStandings: [Int: Double] = [:]
    @State private var myCorpInfo: (name: String, icon: UIImage?)?
    @State private var myAllianceInfo: (name: String, icon: UIImage?)?
    @State private var standingsLoaded = false
    @State private var factionInfo: (name: String, iconName: String)?
    @State private var corporationNamesCache: [Int: String] = [:]
    @State private var isLoadingCorpNames: Bool = false
    /// 联盟缓存管理器
    @StateObject private var allianceCache = EmploymentAllianceCache()
    /// NPC 军团 ID 集合
    @State private var npcCorporationIds: Set<Int> = []
    /// 角色描述折叠状态
    @State private var isDescriptionExpanded: Bool = false

    /// 导航辅助方法
    @ViewBuilder
    private func navigationDestination(for id: Int, type: String) -> some View {
        switch type {
        case "corporation":
            CorporationDetailView(corporationId: id, character: character)
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
            } else if let characterInfo = characterInfo {
                // 基本信息和组织信息合并到一个 Section
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        // 左侧头像
                        if let portrait = portrait {
                            Image(uiImage: portrait)
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

                            // 人物名称
                            Text(characterInfo.name)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)

                            // 人物头衔
                            if let title = characterInfo.title, !title.isEmpty {
                                Text(title.removeHTMLTags())
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            } else {
                                Text("[\(NSLocalizedString("Main_No_Title", comment: ""))]")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .padding(.top, 2)
                            }

                            Spacer()
                                .frame(minHeight: 8)

                            // 军团信息
                            if let corpInfo = corporationInfo {
                                HStack(spacing: 8) {
                                    if let icon = corpInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(corpInfo.name)
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
                                UIPasteboard.general.string = characterInfo.name
                            } label: {
                                Label(
                                    NSLocalizedString("Misc_Copy_CharID", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }
                            if let title = characterInfo.title, !title.isEmpty {
                                Button {
                                    UIPasteboard.general.string = title.removeHTMLTags()
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy_Char_Title", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }

                            Divider()

                            NavigationLink {
                                navigationDestination(
                                    for: characterInfo.corporation_id, type: "corporation"
                                )
                            } label: {
                                Label(
                                    NSLocalizedString("View Corporation", comment: ""),
                                    systemImage: "info.circle"
                                )
                            }

                            if characterInfo.alliance_id != nil {
                                NavigationLink {
                                    navigationDestination(
                                        for: characterInfo.alliance_id!, type: "alliance"
                                    )
                                } label: {
                                    Label(
                                        NSLocalizedString("View Alliance", comment: ""),
                                        systemImage: "info.circle"
                                    )
                                }
                            }
                        }
                        .frame(height: 96) // 与头像等高
                    }
                    .padding(.vertical, 4)
                } footer: {
                    EntityIdCopyFooter(entityId: characterId)
                }

                // 角色描述
                if let description = characterInfo.description, !description.isEmpty {
                    Section {
                        DisclosureGroup(
                            isExpanded: $isDescriptionExpanded,
                            content: {
                                RichTextView(
                                    text: TextProcessingUtil.decodeDescription(description),
                                    databaseManager: DatabaseManager.shared
                                )
                            },
                            label: {
                                Text(
                                    NSLocalizedString(
                                        "Character_Description",
                                        comment: "Character description section title"
                                    )
                                )
                            }
                        )
                    }
                }

                // 添加外部链接按钮
                Section {
                    // 势力信息
                    if let faction = factionInfo {
                        EntityFactionRow(factionInfo: faction)
                    }

                    NavigationLink {
                        BRKillMailSearchView(characterId: character.CharacterID, initialResult: SearchResult(
                            id: characterId, name: characterInfo.name, category: .character,
                            imageURL: "https://images.evetech.net/characters/\(characterId)/portrait?size=64",
                            icon: portrait
                        ))
                    } label: {
                        Text(NSLocalizedString("KillMail_View_Title", comment: ""))
                    }

                    EntityExternalLinkButtons(entityId: characterId, linkType: .character)
                }

                // 添加Picker组件
                Section {
                    Picker(selection: $selectedTab, label: Text("")) {
                        Text(NSLocalizedString("Standings", comment: ""))
                            .tag(0)
                        Text(NSLocalizedString("Employment History", comment: ""))
                            .tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if selectedTab == 0 {
                        StandingsView(
                            characterId: characterId,
                            character: character,
                            targetCharacter: characterInfo,
                            corporationInfo: corporationInfo,
                            allianceInfo: allianceInfo,
                            personalStandings: personalStandings,
                            corpStandings: corpStandings,
                            allianceStandings: allianceStandings,
                            myCorpInfo: myCorpInfo,
                            myAllianceInfo: myAllianceInfo
                        )
                    } else if selectedTab == 1 {
                        CharacterEmploymentHistoryView(
                            history: employmentHistory,
                            corporationNamesCache: corporationNamesCache,
                            character: character,
                            isLoadingCorpNames: isLoadingCorpNames,
                            isLoading: false,
                            allianceCache: allianceCache,
                            npcCorporationIds: npcCorporationIds
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard characterInfo == nil || isLoading else { return }
            await loadCharacterDetails()
        }
    }

    private func loadCharacterDetails() async {
        Logger.info("开始加载角色详细信息 - 角色ID: \(characterId)")
        isLoading = true
        error = nil

        do {
            // 并发加载所有需要的数据
            Logger.info("开始并发加载角色信息、头像和雇佣历史")
            async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: characterId, forceRefresh: true
            )
            async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(
                characterId: characterId, catchImage: false
            )
            async let historyTask = CharacterAPI.shared.fetchEmploymentHistory(
                characterId: characterId
            )

            // 等待所有数据加载完成
            let (info, portrait, history) = try await (characterInfoTask, portraitTask, historyTask)
            Logger.success("成功加载角色基本信息")
            Logger.info("雇佣历史记录数: \(history.count)")

            // 更新状态
            characterInfo = info
            self.portrait = portrait
            employmentHistory = history

            // 联盟信息流水线：一次性批量加载（雇佣历史 tab 的联盟行）
            Task {
                await allianceCache.loadIfNeeded(history: history)
            }

            // 加载军团信息
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: info.corporation_id
            ) {
                Logger.success("成功加载军团信息: \(corpInfo.name)")
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: info.corporation_id
                )
                corporationInfo = (name: corpInfo.name, icon: corpIcon)
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

            // NPC 军团名走 SDE 同步查表（零网络），立即填充
            applyNPCCorporationNames()

            // 玩家军团名异步加载，不阻塞 UI，加载完自动刷新
            isLoadingCorpNames = true
            Task { await loadPlayerCorporationNames() }

            // 加载声望数据
            if !standingsLoaded {
                await loadStandings()
                standingsLoaded = true
            }

        } catch {
            Logger.error("加载角色详细信息失败: \(error)")
            self.error = error
        }

        isLoading = false
        Logger.info("角色详细信息加载完成")
    }

    /// 从 SDE 同步填充 NPC 军团名称和 ID 集合（零网络开销）
    private func applyNPCCorporationNames() {
        let corporationIds = Set(employmentHistory.map { $0.corporation_id })
        var npcIds = Set<Int>()

        for corpId in corporationIds {
            if let npc = SDEMemoryStore.npcCorporation(for: corpId) {
                npcIds.insert(corpId)
                corporationNamesCache[corpId] = npc.name
            }
        }

        npcCorporationIds = npcIds
        Logger.info("从内存加载 NPC 军团成功，数量: \(npcIds.count)")
    }

    /// 异步批量加载玩家军团名称
    private func loadPlayerCorporationNames() async {
        defer { isLoadingCorpNames = false }

        let playerCorps = Set(employmentHistory.map { $0.corporation_id })
            .subtracting(npcCorporationIds)

        guard !playerCorps.isEmpty else { return }

        guard let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(
            ids: Array(playerCorps)
        ) else { return }

        for (corpId, info) in namesMap {
            corporationNamesCache[corpId] = info.name
        }
        Logger.info("从 API 加载玩家军团名称成功，数量: \(namesMap.count)")
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
        let characterId: Int
        let character: EVECharacterInfo
        let targetCharacter: CharacterPublicInfo?
        let corporationInfo: (name: String, icon: UIImage?)?
        let allianceInfo: (name: String, icon: UIImage?)?
        let personalStandings: [Int: Double]
        let corpStandings: [Int: Double]
        let allianceStandings: [Int: Double]
        let myCorpInfo: (name: String, icon: UIImage?)?
        let myAllianceInfo: (name: String, icon: UIImage?)?

        var body: some View {
            VStack {
                if let targetCharacter = targetCharacter {
                    VStack(alignment: .leading, spacing: 4) {
                        // 个人声望
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("Personal Standings", comment: ""))
                                .font(.headline)
                                .padding(.bottom, 4)

                            // 我对目标角色
                            StandingRowView(
                                leftPortrait: (id: character.CharacterID, type: .character),
                                rightPortrait: (id: characterId, type: .character),
                                leftName: character.CharacterName,
                                rightName: targetCharacter.name,
                                standing: personalStandings[characterId]
                            )

                            // 我军团对目标角色
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (id: characterId, type: .character),
                                    leftName: myCorpInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: targetCharacter.name,
                                    standing: corpStandings[characterId]
                                )
                            }

                            // 我联盟对目标角色
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (id: characterId, type: .character),
                                    leftName: myAllianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: targetCharacter.name,
                                    standing: allianceStandings[characterId]
                                )
                            }
                        }

                        Divider()

                        // 军团声望
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Corporation Standings", comment: ""))
                                .font(.headline)
                                .padding(.bottom, 4)

                            // 我对目标军团
                            StandingRowView(
                                leftPortrait: (id: character.CharacterID, type: .character),
                                rightPortrait: (
                                    id: targetCharacter.corporation_id, type: .corporation
                                ),
                                leftName: character.CharacterName,
                                rightName: corporationInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                standing: personalStandings[targetCharacter.corporation_id]
                            )

                            // 我军团对目标军团
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (
                                        id: targetCharacter.corporation_id, type: .corporation
                                    ),
                                    leftName: myCorpInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: corporationInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: corpStandings[targetCharacter.corporation_id]
                                )
                            }

                            // 我联盟对目标军团
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (
                                        id: targetCharacter.corporation_id, type: .corporation
                                    ),
                                    leftName: myAllianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: corporationInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: allianceStandings[targetCharacter.corporation_id]
                                )
                            }
                        }

                        if let targetAllianceId = targetCharacter.alliance_id {
                            Divider()

                            // 联盟声望
                            VStack(alignment: .leading, spacing: 4) {
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
}
