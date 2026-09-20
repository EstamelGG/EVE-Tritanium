import SwiftUI

// MARK: - 数据模型

struct MarketStructure: Identifiable, Codable {
    var id = UUID()
    let structureId: Int
    let structureName: String
    /// characterId/characterName 为 var，以支持在已添加建筑上更换归属角色
    var characterId: Int
    var characterName: String
    let systemId: Int
    let regionId: Int
    let security: Double
    let addedDate: Date
    let structureTypeId: Int?

    init(
        id: UUID = UUID(),
        structureId: Int, structureName: String, characterId: Int, characterName: String,
        systemId: Int, regionId: Int, security: Double, addedDate: Date = Date(),
        structureTypeId: Int? = nil
    ) {
        self.id = id
        self.structureId = structureId
        self.structureName = structureName
        self.characterId = characterId
        self.characterName = characterName
        self.systemId = systemId
        self.regionId = regionId
        self.security = security
        self.addedDate = addedDate
        self.structureTypeId = structureTypeId
    }

    var iconFileName: String {
        guard let structureTypeId else { return IconManager.defaultItemIcon }
        return DatabaseManager.shared.getItemIconFileName(for: structureTypeId)
            ?? IconManager.defaultItemIcon
    }

    var systemName: String {
        SDEMemoryStore.solarSystemName(for: systemId) ?? "Unknown System"
    }

    var regionName: String {
        SDEMemoryStore.regionName(for: regionId) ?? "Unknown Region"
    }
}

// MARK: - 市场建筑管理器

class MarketStructureManager: ObservableObject {
    static let shared = MarketStructureManager()

    @Published var structures: [MarketStructure] = []
    /// 最近一次建筑信息刷新时间，作为 StructureRowView 重新计算缓存状态的信号
    @Published var lastStructureInfoRefresh: Date? = nil
    /// 防止重入（非 @Published，仅逻辑控制）
    private var _isRefreshing = false

    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let structureDirectory: URL
    private let configFilePath: URL

    private init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        structureDirectory = documentsDirectory.appendingPathComponent("Structure_Market")
        configFilePath = structureDirectory.appendingPathComponent("selected_structures.json")

        createDirectoryIfNeeded()
        loadStructures()
    }

    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: structureDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: structureDirectory, withIntermediateDirectories: true
                )
                Logger.info("创建市场建筑目录: \(structureDirectory.path)")
            } catch {
                Logger.error("创建市场建筑目录失败: \(error)")
            }
        }
    }

    func loadStructures() {
        guard fileManager.fileExists(atPath: configFilePath.path) else {
            structures = []
            return
        }

        do {
            let data = try Data(contentsOf: configFilePath)
            // 不再按 addedDate 排序，保留用户拖动调整后的顺序
            structures = try JSONDecoder().decode([MarketStructure].self, from: data)
            Logger.info("加载了 \(structures.count) 个市场建筑")
        } catch {
            Logger.error("加载市场建筑失败: \(error)")
            structures = []
        }
    }

    func saveStructures() {
        do {
            let data = try JSONEncoder().encode(structures)
            try data.write(to: configFilePath)
            Logger.info("保存了 \(structures.count) 个市场建筑")
        } catch {
            Logger.error("保存市场建筑失败: \(error)")
        }
    }

    func addStructure(_ structure: MarketStructure) {
        if !structures.contains(where: { $0.structureId == structure.structureId }) {
            structures.append(structure)
            saveStructures()
        }
    }

    func removeStructure(_ structure: MarketStructure) {
        structures.removeAll { $0.id == structure.id }
        saveStructures()
    }

    /// 更换建筑所属角色（仅修改本地保存的 characterId/characterName，不刷新 ESI）
    func changeStructureCharacter(structureId: Int, newCharacterId: Int, newCharacterName: String) {
        guard let index = structures.firstIndex(where: { $0.structureId == structureId }) else {
            return
        }
        structures[index].characterId = newCharacterId
        structures[index].characterName = newCharacterName
        saveStructures()
        Logger.info("已更换建筑 \(structureId) 的角色为 \(newCharacterName)(\(newCharacterId))")
    }

    /// 调整建筑顺序（拖动排序），持久化保存以便在各市场选择器中复用
    func moveStructure(from source: IndexSet, to destination: Int) {
        structures.move(fromOffsets: source, toOffset: destination)
        saveStructures()
    }

    /// 强制刷新单个已保存建筑的基本信息
    @MainActor
    func refreshStructureInfo(structureId: Int, characterId: Int) async {
        guard let index = structures.firstIndex(where: { $0.structureId == structureId }) else {
            return
        }
        structures[index] = await Self.fetchUpdatedStructure(
            from: structures[index], characterId: characterId
        )
        saveStructures()
    }

    /// 强制从 ESI 重新拉取所有已保存建筑的信息
    /// 刷新完成后通过 lastStructureInfoRefresh 通知各 StructureRowView 自行触发订单刷新
    @MainActor
    func refreshStructureInfos() async {
        guard !structures.isEmpty, !_isRefreshing else { return }
        _isRefreshing = true
        defer { _isRefreshing = false }

        let current = structures
        var refreshed = current

        await withTaskGroup(of: (Int, MarketStructure).self) { group in
            for (index, structure) in current.enumerated() {
                group.addTask {
                    (
                        index,
                        await Self.fetchUpdatedStructure(
                            from: structure, characterId: structure.characterId
                        )
                    )
                }
            }
            for await (index, structure) in group {
                refreshed[index] = structure
            }
        }

        structures = refreshed
        saveStructures()
        lastStructureInfoRefresh = Date()
        Logger.info("已刷新 \(refreshed.count) 个市场建筑信息")
    }

    private static func fetchUpdatedStructure(
        from structure: MarketStructure, characterId: Int
    ) async -> MarketStructure {
        do {
            let info = try await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: Int64(structure.structureId),
                characterId: characterId,
                forceRefresh: true
            )
            let systemInfo = await getSolarSystemInfo(
                solarSystemId: info.solar_system_id,
                databaseManager: DatabaseManager.shared
            )
            return MarketStructure(
                id: structure.id,
                structureId: structure.structureId,
                structureName: info.name,
                characterId: structure.characterId,
                characterName: structure.characterName,
                systemId: info.solar_system_id,
                regionId: systemInfo?.regionId ?? structure.regionId,
                security: systemInfo?.security ?? structure.security,
                addedDate: structure.addedDate,
                structureTypeId: info.type_id
            )
        } catch {
            Logger.error("刷新建筑信息失败 - ID: \(structure.structureId), 错误: \(error)")
            return structure
        }
    }
}

// MARK: - 主视图

struct MarketStructureSettingsView: View {
    @StateObject private var manager = MarketStructureManager.shared
    @State private var showingAddStructureSheet = false

    var body: some View {
        List {
            Section {
                Button(action: {
                    showingAddStructureSheet = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)

                        Text(NSLocalizedString("Main_Setting_Market_Structure_Add", comment: ""))
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }

            if !manager.structures.isEmpty {
                Section(
                    header: Text(
                        String(
                            format: NSLocalizedString(
                                "Main_Setting_Market_Structure_Added_Count", comment: ""
                            ),
                            manager.structures.count
                        )
                    )
                ) {
                    ForEach(manager.structures) { structure in
                        StructureRowView(structure: structure)
                    }
                    .onMove { from, to in
                        manager.moveStructure(from: from, to: to)
                    }
                    .onDelete(perform: deleteStructures)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await manager.refreshStructureInfos()
        }
        .navigationTitle(
            NSLocalizedString("Main_Setting_Market_Structure_Settings_Title", comment: "")
        )
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if !manager.structures.isEmpty {
                        EditButton()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddStructureSheet) {
            AddMarketStructureSheet()
        }
        .task {
            guard !manager.structures.isEmpty else { return }
            await manager.refreshStructureInfos()
        }
    }

    private func deleteStructures(offsets: IndexSet) {
        for index in offsets {
            manager.removeStructure(manager.structures[index])
        }
    }
}

// MARK: - 建筑行视图

struct StructureRowView: View {
    let structure: MarketStructure

    @ObservedObject private var manager = MarketStructureManager.shared
    @State private var isLoadingOrders = false
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil
    @State private var cacheStatus: StructureMarketManager.CacheStatus = .noData
    @State private var showingReloadAlert = false
    @State private var showingCharacterChangeSheet = false
    @State private var pendingCharacter: EVECharacterInfo? = nil
    @State private var lastUpdateDate: Date? = nil
    @State private var ordersCount: Int? = nil
    @State private var itemTypesCount: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标
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
                    .lineLimit(1)

                // 位置信息（安全等级 + 星系 / 星域）
                HStack(spacing: 4) {
                    Text(formatSystemSecurity(structure.security))
                        .foregroundColor(getSecurityColor(structure.security))
                    Text("\(structure.systemName) / \(structure.regionName)")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)

                // 归属角色（头像 + 名称）
                HStack(spacing: 4) {
                    UniversePortrait(
                        id: structure.characterId,
                        type: .character,
                        size: 32,
                        displaySize: 18,
                        cornerRadius: 4
                    )
                    Text(structure.characterName)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)

                // 缓存统计
                cacheSummaryText
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.25), value: lastUpdateDate)
            }

            Spacer()

            // 缓存状态和加载进度指示器
            statusIndicator
                .animation(.easeInOut(duration: 0.25), value: cacheStatus)
                .animation(.easeInOut(duration: 0.25), value: isLoadingOrders)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLoadingOrders {
                showingReloadAlert = true
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = structure.structureName
            } label: {
                Label(
                    NSLocalizedString("Misc_Copy_Structure", comment: ""), systemImage: "doc.on.doc"
                )
            }
            Button {
                Task { await loadStructureOrders() }
            } label: {
                if isLoadingOrders {
                    Label(
                        NSLocalizedString("Structure_Orders_Loading", comment: ""),
                        systemImage: "arrow.clockwise"
                    )
                } else {
                    Label(
                        NSLocalizedString("Structure_Orders_Load", comment: ""),
                        systemImage: "chart.bar.xaxis"
                    )
                }
            }
            .disabled(isLoadingOrders)
            // 更换建筑所属角色
            Button {
                showingCharacterChangeSheet = true
            } label: {
                Label(
                    NSLocalizedString(
                        "Main_Setting_Market_Structure_Change_Character", comment: ""
                    ),
                    systemImage: "person.crop.circle.badge.checkmark"
                )
            }

            Divider()

            Button(role: .destructive) {
                manager.removeStructure(structure)
            } label: {
                Label(
                    NSLocalizedString("Misc_Delete", comment: ""),
                    systemImage: "trash"
                )
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            refreshCacheState()
            Task { await loadLocalOrdersStatistics() }
        }
        .onChange(of: manager.lastStructureInfoRefresh) {
            Task { await loadStructureOrders() }
        }
        .alert(
            NSLocalizedString("Structure_Orders_Reload_Title", comment: ""),
            isPresented: $showingReloadAlert
        ) {
            Button(NSLocalizedString("Structure_Orders_Reload_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Structure_Orders_Reload_Confirm", comment: "")) {
                Task { await loadStructureOrders() }
            }
        } message: {
            Text(NSLocalizedString("Structure_Orders_Reload_Message", comment: ""))
        }
        .sheet(isPresented: $showingCharacterChangeSheet) {
            CharacterSelectorSheet(selectedCharacter: $pendingCharacter)
        }
        .onChange(of: pendingCharacter) { _, newValue in
            // 选中新角色后立即更新并清空待选状态
            guard let newValue else { return }
            manager.changeStructureCharacter(
                structureId: structure.structureId,
                newCharacterId: newValue.CharacterID,
                newCharacterName: newValue.CharacterName
            )
            pendingCharacter = nil
        }
    }

    /// 缓存统计文本（时间 + 订单数 + 物品数合并展示）
    @ViewBuilder
    private var cacheSummaryText: some View {
        if let updateDate = lastUpdateDate {
            let minutesAgo = Int(Date().timeIntervalSince(updateDate) / 60)
            if minutesAgo >= 0 {
                Text(cacheSummaryString(minutesAgo: minutesAgo))
                    .fontWeight(.semibold)
                    .transition(.opacity)
            }
        } else {
            Text(NSLocalizedString("Structure_Orders_No_Cache", comment: ""))
                .transition(.opacity)
        }
    }

    /// 拼接缓存统计文本（已加载时间 + 订单数 + 物品数）
    private func cacheSummaryString(minutesAgo: Int) -> String {
        var parts: [String] = [
            FormatUtil.formatMinutesSinceUpdate(
                minutesAgo,
                justUpdated: NSLocalizedString("Structure_Orders_Just_Updated", comment: ""),
                minutesAgoFormat: NSLocalizedString("Structure_Orders_Minutes_Ago", comment: "")
            ),
        ]
        if let ordersCount = ordersCount {
            parts.append(String.localizedStringWithFormat(
                NSLocalizedString("Structure_Orders_Count", comment: ""), ordersCount
            ))
        }
        if let itemTypesCount = itemTypesCount {
            parts.append(String.localizedStringWithFormat(
                NSLocalizedString("Structure_Orders_Item_Types", comment: ""), itemTypesCount
            ))
        }
        return parts.joined(separator: " · ")
    }

    /// 右侧缓存状态/加载进度指示器
    @ViewBuilder
    private var statusIndicator: some View {
        if isLoadingOrders {
            if let progress = structureOrdersProgress {
                switch progress {
                case let .loading(currentPage, totalPages):
                    VStack(spacing: 2) {
                        ProgressView().scaleEffect(0.8)
                        Text("\(currentPage)/\(totalPages)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                case .completed:
                    ProgressView().scaleEffect(0.8).transition(.opacity)
                }
            } else {
                ProgressView().scaleEffect(0.8).transition(.opacity)
            }
        } else {
            switch cacheStatus {
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                    .transition(.scale.combined(with: .opacity))
            case .expired, .noData:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// 加载建筑市场订单
    private func loadStructureOrders() async {
        isLoadingOrders = true
        structureOrdersProgress = nil

        do {
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: true,
                progressCallback: { progress in
                    Task { @MainActor in
                        structureOrdersProgress = progress
                    }
                }
            )

            let statistics = await StructureMarketManager.shared.getOrdersStatistics(orders: orders)

            // 显示成功消息
            await MainActor.run {
                Logger.info(
                    "建筑 \(structure.structureName) 的市场订单已加载: 买单 \(statistics.buyOrders) 个, 卖单 \(statistics.sellOrders) 个, 总交易量 \(statistics.totalVolume)"
                )
            }

        } catch {
            Logger.error("加载建筑市场订单失败: \(error)")
        }

        // 更新缓存状态和更新时间
        refreshCacheState()

        // 更新订单统计信息
        await loadLocalOrdersStatistics()

        isLoadingOrders = false
        structureOrdersProgress = nil
    }

    /// 重新计算缓存状态和更新时间
    private func refreshCacheState() {
        cacheStatus = StructureMarketManager.getCacheStatus(
            structureId: Int64(structure.structureId)
        )
        lastUpdateDate = StructureMarketManager.getLocalOrdersModificationDate(
            structureId: Int64(structure.structureId)
        )
    }

    /// 加载本地订单统计信息
    private func loadLocalOrdersStatistics() async {
        // 先检查是否有本地缓存文件（无论是否过期）
        let hasLocal = await StructureMarketManager.shared.hasLocalOrders(structureId: Int64(structure.structureId))
        guard hasLocal else {
            await MainActor.run {
                ordersCount = nil
                itemTypesCount = nil
            }
            return
        }

        do {
            // 尝试从本地缓存加载订单数据（不强制刷新，优先使用本地缓存）
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: false
            )

            // 计算订单总数和物品类别数
            let totalOrders = orders.count
            let uniqueItemTypes = Set(orders.map { $0.typeId }).count

            await MainActor.run {
                ordersCount = totalOrders
                itemTypesCount = uniqueItemTypes
            }
        } catch {
            // 如果加载失败，清空统计信息
            await MainActor.run {
                ordersCount = nil
                itemTypesCount = nil
            }
        }
    }
}
