import SwiftUI

// MARK: - ViewModel

@MainActor
final class SovereigntyViewModel: ObservableObject {
    @Published private(set) var preparedCampaigns: [PreparedSovereignty] = []
    @Published private(set) var groupedCampaigns: [String: [PreparedSovereignty]] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?
    private var initialLoadDone = false

    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var iconLoadingTasks: [Int: Task<Void, Never>] = [:]

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await fetchSovereignty()
        }
    }

    deinit {
        loadingTask?.cancel()
        iconLoadingTasks.values.forEach { $0.cancel() }
    }

    func fetchSovereignty(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                Logger.info("开始获取主权争夺数据")
                let campaigns = try await SovereigntyCampaignsAPI.shared.fetchSovereigntyCampaigns(
                    forceRefresh: forceRefresh
                )

                if Task.isCancelled { return }

                await processCampaigns(campaigns)

                if Task.isCancelled { return }

                // 更新分组数据
                updateGroupedCampaigns()

                self.isLoading = false
                self.initialLoadDone = true

            } catch {
                Logger.error("获取主权争夺数据失败: \(error)")
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    private func processCampaigns(_ campaigns: [SovereigntyCampaign]) async {
        // 取消所有现有的图标加载任务
        iconLoadingTasks.values.forEach { $0.cancel() }
        iconLoadingTasks.removeAll()

        // 提取所有需要查询的星系ID
        let solarSystemIds = campaigns.map { $0.solar_system_id }

        // 一次性获取所有星系信息
        let systemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: solarSystemIds,
            databaseManager: databaseManager
        )

        // 创建PreparedSovereignty对象
        var prepared: [PreparedSovereignty] = []

        for campaign in campaigns {
            if let systemInfo = systemInfoMap[campaign.solar_system_id] {
                let locationInfo = PreparedSovereignty.LocationInfo(
                    systemName: systemInfo.systemName,
                    security: systemInfo.security,
                    constellationName: systemInfo.constellationName,
                    regionName: systemInfo.regionName,
                    regionId: systemInfo.regionId
                )

                let preparedCampaign = PreparedSovereignty(
                    campaign: campaign,
                    location: locationInfo
                )

                prepared.append(preparedCampaign)
            }
        }

        // 按星域名称排序
        prepared.sort { $0.location.regionName < $1.location.regionName }

        if !prepared.isEmpty {
            Logger.success("成功准备 \(prepared.count) 条数据")
            preparedCampaigns = prepared
            // 加载所有联盟图标
            loadAllIcons()
        } else {
            Logger.error("没有可显示的完整数据")
        }
    }

    private func updateGroupedCampaigns() {
        groupedCampaigns = Dictionary(grouping: preparedCampaigns) {
            $0.location.regionName
        }
    }

    private func loadAllIcons() {
        // 按联盟ID分组
        let allianceGroups = Dictionary(grouping: preparedCampaigns) { $0.campaign.defender_id }

        // 加载联盟图标
        for (allianceId, campaigns) in allianceGroups {
            let task = Task {
                if campaigns.first != nil {
                    do {
                        Logger.debug("开始加载联盟图标: \(allianceId)，影响 \(campaigns.count) 个战役")
                        let uiImage = try await AllianceAPI.shared.fetchAllianceLogo(
                            allianceID: allianceId
                        )

                        if Task.isCancelled { return }

                        let icon = Image(uiImage: uiImage)
                        // 更新所有使用这个联盟图标的战役
                        for campaign in campaigns {
                            campaign.icon = icon
                        }
                        Logger.debug("联盟图标加载成功: \(allianceId)")
                    } catch {
                        if (error as NSError).code == NSURLErrorCancelled {
                            Logger.debug("联盟图标加载已取消: \(allianceId)")
                        } else {
                            Logger.error("加载联盟图标失败: \(allianceId), error: \(error)")
                        }
                    }
                    // 更新所有相关战役的加载状态
                    if !Task.isCancelled {
                        for campaign in campaigns {
                            campaign.isLoadingIcon = false
                        }
                    }
                }
            }
            iconLoadingTasks[allianceId] = task
            // 设置所有相关战役的加载状态
            for campaign in campaigns {
                campaign.isLoadingIcon = true
            }
        }
    }
}

// MARK: - Views

struct SovereigntyCell: View {
    @ObservedObject var sovereignty: PreparedSovereignty

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .center) {
                // 背景圆环
                Circle()
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 4)
                    .frame(width: 56, height: 56)

                // 进度圆环
                Circle()
                    .trim(from: 0, to: CGFloat(sovereignty.campaign.attackers_score ?? 0))
                    .stroke(Color.red, lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                // 联盟图标
                if sovereignty.isLoadingIcon {
                    ProgressView()
                        .frame(width: 48, height: 48)
                } else if let icon = sovereignty.icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(getEventTypeText(sovereignty.campaign.event_type))
                    Text(
                        "[\(String(format: "%.1f", (sovereignty.campaign.attackers_score ?? 0) * 100))%]"
                    )
                    .foregroundColor(.secondary)
                    Text("[\(sovereignty.remainingTimeText)]")
                        .foregroundColor(.secondary)
                }
                .font(.headline)
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(formatSystemSecurity(sovereignty.location.security))
                            .foregroundColor(getSecurityColor(sovereignty.location.security))
                            .font(.system(.subheadline, design: .monospaced))
                        Text(sovereignty.location.systemName)
                            .fontWeight(.semibold)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = sovereignty.location.systemName
                                } label: {
                                    Label(
                                        NSLocalizedString("Misc_Copy_Location", comment: ""),
                                        systemImage: "doc.on.doc"
                                    )
                                }
                            }
                    }

                    Text(
                        "\(sovereignty.location.constellationName) / \(sovereignty.location.regionName)"
                    )
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 8)
    }

    private func getEventTypeText(_ type: String) -> String {
        switch type {
        case "tcu_defense": return "TCU"
        case "ihub_defense": return "IHub"
        case "station_defense": return "Station"
        case "station_freeport": return "Freeport"
        default: return type
        }
    }
}

struct SovereigntyView: View {
    @StateObject private var viewModel: SovereigntyViewModel
    @State private var mapNavigation: RegionNavigation?
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        _viewModel = StateObject(
            wrappedValue: SovereigntyViewModel(databaseManager: databaseManager)
        )
    }

    var body: some View {
        List {
            Section(
                header: Text(NSLocalizedString("Sovereignty_All", comment: "主权势力列表"))
            ) {
                NavigationLink(
                    destination: SovereigntyListView(databaseManager: DatabaseManager.shared)
                ) {
                    Text(NSLocalizedString("Sovereignty_List", comment: "主权势力列表"))
                        .foregroundColor(.primary)
                }
            }

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.preparedCampaigns.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                ForEach(Array(viewModel.groupedCampaigns.keys.sorted()), id: \.self) { regionName in
                    Section(
                        header: HStack {
                            let regionCampaigns = viewModel.groupedCampaigns[regionName]
                            Text(regionName)
                            Text("(\(regionCampaigns?.count ?? 0))")
                                .foregroundColor(.secondary)
                            Spacer()
                            if let regionCampaigns,
                               let regionId = regionCampaigns.first?.location.regionId,
                               StarMapRegionAvailability.isAvailable(regionId)
                            {
                                Button {
                                    // 高亮该星域内所有正在发生主权争夺的星系
                                    mapNavigation = .regionMap(
                                        regionId,
                                        regionName,
                                        regionCampaigns.map(\.campaign.solar_system_id)
                                    )
                                } label: {
                                    Text(NSLocalizedString("LP_Show_Map", comment: ""))
                                        .font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    ) {
                        ForEach(
                            viewModel.groupedCampaigns[regionName]?.sorted(by: {
                                $0.location.systemName < $1.location.systemName
                            }) ?? []
                        ) { campaign in
                            SovereigntyCell(sovereignty: campaign)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.fetchSovereignty(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Sovereignty", comment: ""))
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
    }
}
