import SwiftUI

/// 声望视图
private struct AllianceStandingsView: View {
    @Environment(\.timeZone) private var displayTimeZone
    let allianceId: Int
    let allianceName: String
    let character: EVECharacterInfo
    let personalStandings: [Int: Double]
    let corpStandings: [Int: Double]
    let allianceStandings: [Int: Double]
    let myCorpInfo: (name: String, icon: UIImage?)?
    let myAllianceInfo: (name: String, icon: UIImage?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Alliance Standings", comment: ""))
                .font(.headline)
                .padding(.bottom, 4)

            // 我对目标联盟
            StandingRowView(
                leftPortrait: (id: character.CharacterID, type: .character),
                rightPortrait: (id: allianceId, type: .alliance),
                leftName: character.CharacterName,
                rightName: allianceName,
                standing: personalStandings[allianceId]
            )

            // 我军团对目标联盟
            if let corpId = character.corporationId {
                StandingRowView(
                    leftPortrait: (id: corpId, type: .corporation),
                    rightPortrait: (id: allianceId, type: .alliance),
                    leftName: myCorpInfo?.name
                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                    rightName: allianceName,
                    standing: corpStandings[allianceId]
                )
            }

            // 我联盟对目标联盟
            if let myAllianceId = character.allianceId {
                StandingRowView(
                    leftPortrait: (id: myAllianceId, type: .alliance),
                    rightPortrait: (id: allianceId, type: .alliance),
                    leftName: myAllianceInfo?.name
                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                    rightName: allianceName,
                    standing: allianceStandings[allianceId]
                )
            }
        }
    }
}

struct AllianceDetailView: View {
    @Environment(\.timeZone) private var displayTimeZone
    let allianceId: Int
    let character: EVECharacterInfo

    @State private var allianceInfo: AllianceInfo?
    @State private var allianceLogo: UIImage?
    @State private var creatorCorpInfo: (name: String, icon: UIImage?)?
    @State private var executorCorpInfo: (name: String, icon: UIImage?)?
    @State private var creatorInfo: (name: String, icon: UIImage?)?
    @State private var factionInfo: (name: String, iconName: String)?

    @State private var personalStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var allianceStandings: [Int: Double] = [:]

    @State private var myCorpInfo: (name: String, icon: UIImage?)?
    @State private var myAllianceInfo: (name: String, icon: UIImage?)?

    @State private var error: Error?
    @State private var isLoading = true
    @State private var standingsLoaded = false

    /// 导航辅助方法
    @ViewBuilder
    private func navigationDestination(for id: Int, type: String) -> some View {
        switch type {
        case "character":
            CharacterDetailView(characterId: id, character: character)
        case "corporation":
            CorporationDetailView(corporationId: id, character: character)
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
            } else if let allianceInfo = allianceInfo {
                // 联盟基本信息
                Section {
                    HStack(spacing: 16) {
                        // 联盟图标
                        if let logo = allianceLogo {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.primary, lineWidth: 1)
                                        .opacity(0.3)
                                )
                        } else {
                            Image(systemName: "square.dashed")
                                .resizable()
                                .frame(width: 96, height: 96)
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            // 联盟名称和代号
                            VStack(alignment: .leading, spacing: 4) {
                                Text(allianceInfo.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("[\(allianceInfo.ticker)]")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            // 执行军团
                            if let executorInfo = executorCorpInfo {
                                HStack(spacing: 4) {
                                    if let icon = executorInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text("\(executorInfo.name)")
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                }
                            }

                            // 创建者军团
                            if let creatorCorpInfo = creatorCorpInfo {
                                HStack(spacing: 4) {
                                    if let icon = creatorCorpInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(
                                        "\(NSLocalizedString("Creator Corp", comment: "")): \(creatorCorpInfo.name)"
                                    )
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                }
                            }

                            // 创建者
                            if let creatorInfo = creatorInfo {
                                HStack(spacing: 4) {
                                    if let icon = creatorInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(
                                        "\(NSLocalizedString("Creator", comment: "")): \(creatorInfo.name)"
                                    )
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = allianceInfo.name
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Alliance", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }

                        Divider()

                        NavigationLink {
                            navigationDestination(
                                for: allianceInfo.executor_corporation_id, type: "corporation"
                            )
                        } label: {
                            Label(
                                "\(NSLocalizedString("View", comment: "")) \(NSLocalizedString("Executor Corp", comment: ""))",
                                systemImage: "info.circle"
                            )
                        }

                        NavigationLink {
                            navigationDestination(
                                for: allianceInfo.creator_corporation_id, type: "corporation"
                            )
                        } label: {
                            Label(
                                "\(NSLocalizedString("View", comment: "")) \(NSLocalizedString("Creator Corp", comment: ""))",
                                systemImage: "info.circle"
                            )
                        }

                        NavigationLink {
                            navigationDestination(
                                for: allianceInfo.creator_id, type: "character"
                            )
                        } label: {
                            Label(
                                "\(NSLocalizedString("View", comment: "")) \(NSLocalizedString("Creator", comment: ""))",
                                systemImage: "info.circle"
                            )
                        }
                    }
                } footer: {
                    EntityIdCopyFooter(entityId: allianceId)
                }

                // 联盟基本信息
                Section {
                    // 势力信息
                    if let faction = factionInfo {
                        EntityFactionRow(factionInfo: faction)
                    }
                    // 成立时间
                    if let date = ISO8601DateFormatter().date(from: allianceInfo.date_founded) {
                        HStack {
                            Text("\(NSLocalizedString("Main_Founded", comment: ""))")
                            Spacer()
                            Text(date, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 添加外部链接按钮
                Section {
                    EntityExternalLinkButtons(entityId: allianceId, linkType: .alliance)
                }

                // 声望信息
                Section {
                    AllianceStandingsView(
                        allianceId: allianceId,
                        allianceName: allianceInfo.name,
                        character: character,
                        personalStandings: personalStandings,
                        corpStandings: corpStandings,
                        allianceStandings: allianceStandings,
                        myCorpInfo: myCorpInfo,
                        myAllianceInfo: myAllianceInfo
                    )
                } header: {
                    Text(NSLocalizedString("Standings", comment: ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAllianceDetails()

            if !standingsLoaded {
                await loadStandings()
                standingsLoaded = true
            }
        }
    }

    private func loadAllianceDetails() async {
        isLoading = true

        do {
            // 加载联盟基本信息和图标
            async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(
                allianceId: allianceId
            )
            async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(
                allianceID: allianceId, size: 128
            )

            let (info, logo) = try await (allianceInfoTask, allianceLogoTask)

            // 加载执行军团信息
            async let executorCorpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: info.executor_corporation_id
            )
            async let executorCorpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: info.executor_corporation_id
            )

            // 加载创建者军团信息
            async let creatorCorpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: info.creator_corporation_id
            )
            async let creatorCorpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: info.creator_corporation_id
            )

            // 加载创建者信息
            let creatorNames = try await UniverseAPI.shared.getNamesWithFallback(ids: [
                info.creator_id,
            ])
            let creatorName =
                creatorNames[info.creator_id]?.name ?? NSLocalizedString("Unknown", comment: "")
            let creatorIcon = try? await CharacterAPI.shared.fetchCharacterPortrait(
                characterId: info.creator_id, catchImage: false
            )

            // 等待所有信息加载完成
            let (executorCorpInfo, executorCorpLogo) = try await (
                executorCorpInfoTask, executorCorpLogoTask
            )
            let (creatorCorpInfo, creatorCorpLogo) = try await (
                creatorCorpInfoTask, creatorCorpLogoTask
            )

            // 加载势力信息
            if let factionId = info.faction_id,
               let faction = SDEMemoryStore.faction(for: factionId)
            {
                Logger.success("成功加载势力信息: \(faction.name)")
                factionInfo = (name: faction.name, iconName: faction.iconName)
            }

            // 更新UI
            await MainActor.run {
                self.allianceInfo = info
                self.allianceLogo = logo
                self.executorCorpInfo = (name: executorCorpInfo.name, icon: executorCorpLogo)
                self.creatorCorpInfo = (name: creatorCorpInfo.name, icon: creatorCorpLogo)
                self.creatorInfo = (name: creatorName, icon: creatorIcon)
            }

        } catch {
            Logger.error("加载联盟详细信息失败: \(error)")
            self.error = error
        }

        isLoading = false
        Logger.info("联盟详细信息加载完成")
    }

    private func loadStandings() async {
        let data = await StandingsLoader.loadStandings(for: character)
        myCorpInfo = data.myCorpInfo
        myAllianceInfo = data.myAllianceInfo
        personalStandings = data.personalStandings
        corpStandings = data.corpStandings
        allianceStandings = data.allianceStandings
    }
}
