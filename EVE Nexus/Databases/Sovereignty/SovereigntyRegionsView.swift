import SwiftUI

/// 主权势力星域列表（第二级：该主权拥有的星系分布在哪些星域，各行显示星系数量）
struct SovereigntyRegionsView: View {
    @Environment(\.timeZone) private var displayTimeZone
    @ObservedObject var databaseManager: DatabaseManager
    let sovereigntyInfo: SovereigntyInfo

    /// 星域分组：该主权在此星域内的全部星系
    struct RegionGroup: Identifiable {
        let regionId: Int
        let regionName: String
        let systems: [SolarSystemInfo]
        var id: Int {
            regionId
        }
    }

    @State private var regions: [RegionGroup] = []
    @State private var isLoading = true
    @State private var hasLoadedInitialData = false
    @State private var mapNavigation: RegionNavigation?
    @State private var errorMessage: String?
    @State private var showError = false

    // 势力信息（联盟型走 ESI 联盟端点，派系型走 universe/factions，失败静默降级）
    @State private var entityLogo: UIImage?
    @State private var entityTicker: String?
    @State private var executorCorpInfo: (name: String, icon: Image?)?
    @State private var foundedDate: Date?
    @State private var capitalSystemName: String?
    @State private var isEntityInfoLoading = false

    init(databaseManager: DatabaseManager, sovereigntyInfo: SovereigntyInfo) {
        self.databaseManager = databaseManager
        self.sovereigntyInfo = sovereigntyInfo
    }

    var body: some View {
        VStack {
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("Loading_Sovereignty", comment: "加载主权信息中..."))
                    .foregroundColor(.gray)
                Spacer()
            } else {
                SovereigntySearchScope {
                    List {
                        entityInfoSection

                        // 第二 section：主权星域列表
                        Section {
                            if regions.isEmpty {
                                NoDataSection()
                            } else {
                                ForEach(regions) { region in
                                    regionRow(region)
                                }
                            }
                        } header: {
                            Text(NSLocalizedString("Sovereignty_Regions", comment: "主权星域"))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .refreshable {
            await loadRegions(forceRefresh: true)
            await loadEntityInfo(forceRefresh: true)
        }
        .onAppear {
            // 只在第一次进入时加载，避免从第三级返回时重复加载
            if !hasLoadedInitialData {
                Task {
                    await loadRegions(forceRefresh: false)
                }
                Task {
                    await loadEntityInfo()
                }
                hasLoadedInitialData = true
            }
        }
        .navigationDestination(item: $mapNavigation) { navigation in
            switch navigation {
            case let .regionMap(regionId, regionName, systemIds):
                RegionSystemMapView(
                    databaseManager: databaseManager,
                    regionId: regionId,
                    regionName: regionName,
                    highlightSystemIds: systemIds
                )
            }
        }
        .alert(
            NSLocalizedString("Load_Error", comment: "加载错误"),
            isPresented: $showError,
            actions: {
                Button(NSLocalizedString("OK", comment: "确定"), role: .cancel) {
                    showError = false
                }
            },
            message: {
                if let errorMsg = errorMessage {
                    Text(errorMsg)
                } else {
                    Text(NSLocalizedString("Unknown_Error", comment: "未知错误"))
                }
            }
        )
    }

    /// 星域行：星域名 + 星系数量 + 查看地图，点按进入第三级
    private func regionRow(_ region: RegionGroup) -> some View {
        NavigationLink(
            destination: SovereigntySystemsView(
                regionName: region.regionName,
                systems: region.systems
            )
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.regionName)
                        .foregroundColor(.primary)
                    Text(
                        "\(region.systems.count) \(NSLocalizedString("Sovereignty_Systems", comment: "个星系"))"
                    )
                    .font(.caption)
                    .foregroundColor(.gray)
                }

                Spacer()

                // 仅当地图数据包含该星域时显示（虫洞等星域不在地图中，SDE 初始化预载的内存集合）
                if StarMapRegionAvailability.isAvailable(region.regionId) {
                    Button {
                        // 高亮该主权在此星域内的所有星系
                        mapNavigation = .regionMap(
                            region.regionId,
                            region.regionName,
                            region.systems.map(\.systemId)
                        )
                    } label: {
                        Text(NSLocalizedString("LP_Show_Map", comment: ""))
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // MARK: - 势力信息 section

    /// 势力信息 section（第一 section，无 header）：联盟型与派系型共用布局，字段按各自可得性显示
    private var entityInfoSection: some View {
        Section {
            entityInfoRow
        } footer: {
            EntityIdCopyFooter(entityId: sovereigntyInfo.id)
        }
    }

    /// 左图标卡片，右侧名称第一行，其余字段依次往下
    /// 加载中的字段用等几何占位（尺寸与最终内容一致），数据到位后原位替换，避免视觉抖动
    private var entityInfoRow: some View {
        HStack(spacing: 16) {
            entityIconImage
                .resizable()
                .scaledToFit()
                .foregroundColor(.gray) // 仅对 SF Symbol 占位生效（位图 logo 为原始渲染，不受影响）
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.primary, lineWidth: 1)
                        .opacity(0.3)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(sovereigntyInfo.name)
                        .font(.headline)
                        .lineLimit(1)

                    // 缩写徽章（联盟型才有）
                    if let ticker = entityTicker, !ticker.isEmpty {
                        Text("[\(ticker)]")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .lineLimit(1)
                    } else if isEntityInfoLoading, sovereigntyInfo.isAlliance {
                        EntitySkeletonBar(width: 48, height: 18, cornerRadius: 9)
                    }
                }

                // 执行军团（联盟型为 executor，派系型为主军团）
                if let executorInfo = executorCorpInfo {
                    HStack(spacing: 4) {
                        if let icon = executorInfo.icon {
                            icon
                                .resizable()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(executorInfo.name)
                            .font(.system(size: 14))
                            .lineLimit(1)
                    }
                } else if isEntityInfoLoading {
                    // 与真实行同几何：20×20 图标块 + 文本条
                    HStack(spacing: 4) {
                        EntitySkeletonBar(width: 20, height: 20)
                        EntitySkeletonBar(width: 120, height: 12)
                    }
                }

                // 成立时间（联盟型）
                if let foundedDate {
                    attributeRow(
                        label: NSLocalizedString("Main_Founded", comment: ""),
                        value: Text(foundedDate, style: .date)
                    )
                } else if isEntityInfoLoading, sovereigntyInfo.isAlliance {
                    attributeSkeletonRow
                }

                // 首都星系（派系型）
                if let capitalSystemName {
                    attributeRow(
                        label: NSLocalizedString("Sovereignty_Capital", comment: "首都星系"),
                        value: Text(capitalSystemName)
                    )
                } else if isEntityInfoLoading, !sovereigntyInfo.isAlliance {
                    attributeSkeletonRow
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                UIPasteboard.general.string = sovereigntyInfo.name
            } label: {
                Label(
                    NSLocalizedString("Misc_Copy", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
    }

    /// 属性行骨架：左标签条 + 右值条，高度对齐 subheadline 行高
    private var attributeSkeletonRow: some View {
        HStack {
            EntitySkeletonBar(width: 64, height: 14)
            Spacer()
            EntitySkeletonBar(width: 88, height: 14)
        }
    }

    /// 图标：联盟型优先 ESI logo（失败用占位图标），派系型用本地 SDE 图标
    private var entityIconImage: Image {
        if let logo = entityLogo {
            Image(uiImage: logo)
        } else if sovereigntyInfo.isAlliance {
            Image(systemName: "square.dashed")
        } else if let icon = sovereigntyInfo.icon {
            icon
        } else {
            Image("faction_default")
        }
    }

    /// 属性行：左标签右值（成立时间 / 首都星系共用）
    private func attributeRow(label: String, value: Text) -> some View {
        HStack {
            Text(label)
            Spacer()
            value.foregroundColor(.secondary)
        }
        .font(.subheadline)
    }

    /// 加载势力信息（与星域加载并行，失败静默降级，不影响星域列表）
    private func loadEntityInfo(forceRefresh: Bool = false) async {
        isEntityInfoLoading = true
        defer { isEntityInfoLoading = false }

        if sovereigntyInfo.isAlliance {
            await loadAllianceInfo(forceRefresh: forceRefresh)
        } else {
            await loadFactionInfo(forceRefresh: forceRefresh)
        }
    }

    /// 拉取军团名称与图标：SDE 命中（NPC 军团）本地直出零网络，未命中走 ESI（尽力而为，失败返回 nil）
    private func fetchCorpInfo(corporationId: Int, forceRefresh: Bool) async -> (
        name: String, icon: Image?
    )? {
        // NPC 军团：本地 SDE 名称 + 图标
        if let npc = SDEMemoryStore.npcCorporation(for: corporationId) {
            return (name: npc.name, icon: IconManager.shared.loadImage(for: npc.iconFilename))
        }

        // 玩家军团：ESI 信息 + 图标
        guard let info = try? await CorporationAPI.shared.fetchCorporationInfo(
            corporationId: corporationId,
            forceRefresh: forceRefresh
        ) else {
            return nil
        }
        let logo = try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: corporationId)
        return (name: info.name, icon: logo.map { Image(uiImage: $0) })
    }

    /// 联盟型：ticker / 成立时间 / 执行军团（ESI 联盟端点，公开无 token）
    private func loadAllianceInfo(forceRefresh: Bool) async {
        do {
            async let infoTask = AllianceAPI.shared.fetchAllianceInfo(
                allianceId: sovereigntyInfo.id,
                forceRefresh: forceRefresh
            )
            async let logoTask = AllianceAPI.shared.fetchAllianceLogo(
                allianceID: sovereigntyInfo.id,
                size: 128,
                forceRefresh: forceRefresh
            )

            let info = try await infoTask
            entityTicker = info.ticker
            foundedDate = ISO8601DateFormatter().date(from: info.date_founded)
            entityLogo = try? await logoTask

            // 执行军团（失败仅隐藏该行）
            executorCorpInfo = await fetchCorpInfo(
                corporationId: info.executor_corporation_id,
                forceRefresh: forceRefresh
            )
        } catch {
            Logger.error("加载主权联盟信息失败（静默降级）: \(error.localizedDescription)")
        }
    }

    /// 派系型：主军团 / 首都星系（universe/factions + 本地 SDE，公开无 token）
    private func loadFactionInfo(forceRefresh: Bool) async {
        do {
            let faction = try await SovereigntyDataAPI.shared.fetchFactionInfo(
                factionId: sovereigntyInfo.id,
                forceRefresh: forceRefresh
            )

            // 首都星系名（本地 SDE 查询）
            if let systemId = faction?.solar_system_id {
                capitalSystemName = SDEMemoryStore.solarSystemName(for: systemId)
            }

            // 主军团（失败仅隐藏该行）
            if let corpId = faction?.corporation_id {
                executorCorpInfo = await fetchCorpInfo(
                    corporationId: corpId,
                    forceRefresh: forceRefresh
                )
            }
        } catch {
            Logger.error("加载主权派系信息失败（静默降级）: \(error.localizedDescription)")
        }
    }

    /// 加载该主权的全部星系并按星域分组
    private func loadRegions(forceRefresh: Bool) async {
        if !forceRefresh {
            isLoading = true
        }

        do {
            let systems = try await SovereigntySearchEngine.shared.systemInfos(
                forSovereigntyId: sovereigntyInfo.id,
                forceRefresh: forceRefresh
            )

            let grouped = Dictionary(grouping: systems) { $0.regionId }
                .map { regionId, regionSystems -> RegionGroup in
                    RegionGroup(
                        regionId: regionId,
                        regionName: regionSystems.first?.regionName
                            ?? SDEMemoryStore.regionName(for: regionId) ?? "Region \(regionId)",
                        systems: regionSystems.sorted { $0.systemName < $1.systemName }
                    )
                }
                .sorted { $0.regionName < $1.regionName }

            regions = grouped
            isLoading = false
        } catch {
            Logger.error("加载主权星域数据失败: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }
}
