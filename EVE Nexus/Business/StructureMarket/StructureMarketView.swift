import SwiftUI

// MARK: - 建筑市场主视图

struct StructureMarketView: View {
    @StateObject private var manager = MarketStructureManager.shared
    @State private var showingAddStructureSheet = false
    @StateObject private var allianceIconLoader = AllianceIconLoader()

    var body: some View {
        List {
            if manager.structures.isEmpty {
                // 空状态
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "building.2")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text(NSLocalizedString("Structure_Market_Empty_Title", comment: "暂无建筑"))
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(NSLocalizedString("Structure_Market_Empty_Message", comment: "点击右上角的加号按钮添加市场建筑"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                // 建筑列表
                ForEach(manager.structures) { structure in
                    StructureMarketRowViewWithNavigation(
                        structure: structure,
                        allianceIconLoader: allianceIconLoader
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            manager.removeStructure(structure)
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await manager.refreshStructureInfos()
        }
        .navigationTitle(NSLocalizedString("Main_Structure_Market", comment: "建筑市场"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingAddStructureSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(.body)
                }
            }
        }
        .sheet(isPresented: $showingAddStructureSheet) {
            AddMarketStructureSheet()
        }
        .onDisappear {
            allianceIconLoader.cancelAllTasks()
        }
    }
}

// MARK: - 建筑市场行视图

struct StructureMarketRowView: View {
    let structure: MarketStructure
    @ObservedObject var allianceIconLoader: AllianceIconLoader
    @Binding var isAccessDenied: Bool // 标记建筑是否无法访问

    init(structure: MarketStructure, allianceIconLoader: AllianceIconLoader, isAccessDenied: Binding<Bool> = .constant(false)) {
        self.structure = structure
        self.allianceIconLoader = allianceIconLoader
        _isAccessDenied = isAccessDenied
    }

    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标（按 typeId 查询）
            IconManager.shared.loadImage(for: structure.iconFileName)
                .resizable()
                .frame(width: 40, height: 40)
                .cornerRadius(8)

            // 建筑信息
            VStack(alignment: .leading, spacing: 4) {
                // 建筑名称
                Text(structure.structureName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = structure.structureName
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Structure", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }

                // 位置信息
                HStack(spacing: 4) {
                    Text(formatSystemSecurity(structure.security))
                        .foregroundColor(getSecurityColor(structure.security))
                        .font(.caption)

                    Text("\(structure.systemName) / \(structure.regionName)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                // 如果建筑无法访问，显示提示
                if isAccessDenied {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption2)
                        Text(NSLocalizedString("Structure_Market_Access_Denied", comment: "无法访问此建筑"))
                            .foregroundColor(.red)
                            .font(.caption2)
                    }
                }
            }

            Spacer()

            // 建筑拥有者图标（联盟或军团）
            StructureOwnerIconView(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                allianceIconLoader: allianceIconLoader,
                onAccessDenied: {
                    isAccessDenied = true
                }
            )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 带导航链接的建筑行视图（根据访问状态决定是否可点击）

struct StructureMarketRowViewWithNavigation: View {
    let structure: MarketStructure
    @ObservedObject var allianceIconLoader: AllianceIconLoader
    @State private var isAccessDenied = false

    var body: some View {
        if isAccessDenied {
            // 建筑无法访问，禁用跳转
            StructureMarketRowView(
                structure: structure,
                allianceIconLoader: allianceIconLoader,
                isAccessDenied: $isAccessDenied
            )
        } else {
            // 建筑可访问，允许跳转
            NavigationLink(destination: StructureMarketDetailView(structure: structure)) {
                StructureMarketRowView(
                    structure: structure,
                    allianceIconLoader: allianceIconLoader,
                    isAccessDenied: $isAccessDenied
                )
            }
        }
    }
}

// MARK: - 建筑拥有者图标视图

struct StructureOwnerIconView: View {
    let structureId: Int64
    let characterId: Int
    @ObservedObject var allianceIconLoader: AllianceIconLoader

    /// 回调：当检测到建筑无法访问时通知父视图
    var onAccessDenied: (() -> Void)? = nil

    // 拥有者信息
    @State private var ownerInfo: OwnerInfo? = nil
    @State private var corporationLogo: UIImage? = nil
    @State private var isLoadingOwner = false
    @State private var isAccessDenied = false // 标记建筑是否无法访问

    struct OwnerInfo {
        let corporationId: Int
        let allianceId: Int?
    }

    var body: some View {
        Group {
            if isAccessDenied {
                // 建筑无法访问，显示错误图标
                errorIconView()
            } else if let info = ownerInfo {
                // 已获取拥有者信息
                if let allianceId = info.allianceId {
                    // 有联盟，显示联盟图标
                    allianceIconView(allianceId: allianceId)
                } else {
                    // 无联盟，显示军团图标
                    corporationIconView()
                }
            } else {
                // 正在加载拥有者信息
                loadingIndicator()
            }
        }
        .frame(width: 32, height: 32)
        .task {
            await loadOwnerInfo()
        }
    }

    // MARK: - 视图组件

    @ViewBuilder
    private func allianceIconView(allianceId: Int) -> some View {
        if let icon = allianceIconLoader.icons[allianceId] {
            // 已加载的联盟图标
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
        } else {
            // 联盟图标未加载，触发加载并显示加载指示器
            loadingIndicator()
                .onAppear {
                    allianceIconLoader.loadIcon(for: allianceId)
                }
        }
    }

    @ViewBuilder
    private func corporationIconView() -> some View {
        if let logo = corporationLogo {
            // 已加载的军团图标
            Image(uiImage: logo)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
        } else {
            // 正在加载军团图标
            loadingIndicator()
        }
    }

    private func loadingIndicator() -> some View {
        ProgressView()
            .frame(width: 32, height: 32)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
    }

    private func errorIconView() -> some View {
        Image(systemName: "xmark.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
            .foregroundColor(.red)
            .background(Color.white)
            .cornerRadius(6)
    }

    // MARK: - 数据加载

    private func loadOwnerInfo() async {
        // 如果已有信息或正在加载，则跳过
        guard ownerInfo == nil, !isLoadingOwner else { return }

        await MainActor.run {
            isLoadingOwner = true
        }

        do {
            // 1. 获取建筑信息（包含 owner_id）
            let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: structureId,
                characterId: characterId,
                forceRefresh: false
            )

            let corporationId = structureInfo.owner_id

            // 2. 获取军团信息（包含 alliance_id）
            let corpInfo = try await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corporationId,
                forceRefresh: false
            )

            let allianceId = corpInfo.alliance_id

            // 更新拥有者信息
            await MainActor.run {
                ownerInfo = OwnerInfo(
                    corporationId: corporationId,
                    allianceId: allianceId
                )
                isLoadingOwner = false
            }

            // 如果没有联盟，加载军团图标
            if allianceId == nil {
                await loadCorporationLogo(corporationId: corporationId)
            }
        } catch {
            Logger.error("加载建筑拥有者信息失败 - 建筑ID: \(structureId), 错误: \(error)")

            // 任何错误都视为建筑无法访问
            await MainActor.run {
                isAccessDenied = true
                isLoadingOwner = false
            }
            // 通知父视图建筑无法访问
            onAccessDenied?()
        }
    }

    private func loadCorporationLogo(corporationId: Int) async {
        // 如果已有图标，则跳过
        guard corporationLogo == nil else { return }

        do {
            let logo = try await CorporationAPI.shared.fetchCorporationLogo(
                corporationId: corporationId,
                size: 64,
                forceRefresh: false
            )

            await MainActor.run {
                corporationLogo = logo
            }
        } catch {
            Logger.error("加载军团图标失败 - 军团ID: \(corporationId), 错误: \(error)")
        }
    }
}
