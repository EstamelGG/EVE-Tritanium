import Combine
import Foundation

/// 删除缓存项，包含删除时间信息
struct DeletedFittingItem {
    let fittingId: Int
    let deletedAt: Date

    /// 检查是否已过期（超过5分钟）
    var isExpired: Bool {
        Date().timeIntervalSince(deletedAt) > 300 // 5分钟 = 300秒
    }
}

/// 删除缓存管理器 - 单例模式，在应用生命周期中持久化
@MainActor
final class FittingDeletionCacheManager: ObservableObject {
    static let shared = FittingDeletionCacheManager()

    /// 存储已删除配置的信息，按角色ID分组
    private var deletedFittingItems: [Int: [DeletedFittingItem]] = [:]

    private init() {}

    /// 添加已删除的配置ID
    func addDeletedFitting(fittingId: Int, characterId: Int) {
        let deletedItem = DeletedFittingItem(fittingId: fittingId, deletedAt: Date())

        if deletedFittingItems[characterId] == nil {
            deletedFittingItems[characterId] = []
        }

        // 移除已存在的相同ID（如果有的话）
        deletedFittingItems[characterId]?.removeAll { $0.fittingId == fittingId }

        // 添加新的删除记录
        deletedFittingItems[characterId]?.append(deletedItem)
    }

    /// 检查配置是否已被删除且未过期
    func isDeleted(fittingId: Int, characterId: Int) -> Bool {
        guard let items = deletedFittingItems[characterId] else {
            return false
        }

        // 先清理过期项
        cleanExpiredItems(for: characterId)

        // 查找匹配的删除记录，且未过期
        return items.contains { $0.fittingId == fittingId && !$0.isExpired }
    }

    /// 清理指定角色的过期缓存项
    private func cleanExpiredItems(for characterId: Int) {
        deletedFittingItems[characterId]?.removeAll { $0.isExpired }

        // 如果数组为空，移除整个角色的记录
        if deletedFittingItems[characterId]?.isEmpty == true {
            deletedFittingItems[characterId] = nil
        }
    }

    /// 获取缓存统计信息（用于调试）
    func getCacheStats() -> [Int: Int] {
        var stats: [Int: Int] = [:]
        for (characterId, _) in deletedFittingItems {
            // 先清理过期项
            cleanExpiredItems(for: characterId)

            // 获取清理后的有效项数量
            if let items = deletedFittingItems[characterId], !items.isEmpty {
                stats[characterId] = items.count
            }
        }
        return stats
    }

    /// 打印缓存统计信息（用于调试）
    func printCacheStats() {
        let stats = getCacheStats()
        if stats.isEmpty {
            Logger.debug("删除缓存为空")
        } else {
            for (characterId, count) in stats {
                Logger.debug("角色 \(characterId) 有 \(count) 个有效的删除缓存项")
            }
        }
    }
}

/// 配置来源类型
enum FittingSourceType {
    case local
    case online
}

/// 本地配置视图模型
@MainActor
final class LocalFittingViewModel: ObservableObject {
    /// 预构造导航树（唯一列表数据源）
    @Published private(set) var tree: [FittingGroupNode] = []
    /// 无法解析的装配（仅提醒展示，不可打开）
    @Published private(set) var unreadableFittings: [UnreadableFitting] = []
    @Published private(set) var shipInfo: [Int: FittingShipInfo] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func loadLocalFittings() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try FitConvert.loadAllLocalFittings()
            apply(result.fittings, fileUnreadable: result.unreadable)
        } catch {
            Logger.error("加载本地配置失败: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 由全量装配重建树与字典；SDE 查不到飞船的装配归入无法解析列表（文件保留）
    private func apply(
        _ localFittings: [LocalFitting], fileUnreadable: [UnreadableFitting] = []
    ) {
        let entries: [FittingCatalogEntry] = localFittings.map {
            (ref: .local($0.fitting_id), name: $0.name, shipTypeId: $0.ship_type_id)
        }

        let catalog = FittingTreeBuilder.catalog(from: entries)

        // SDE 缺失该飞船：无法构建层级，标记提醒（不删除文件）
        let skippedUnreadable = catalog.skipped.compactMap { entry -> UnreadableFitting? in
            guard case let .local(uuid) = entry.ref else { return nil }
            return UnreadableFitting(
                fileName: fileName(for: uuid),
                name: entry.name,
                shipTypeId: entry.shipTypeId
            )
        }

        shipInfo = catalog.shipInfo
        tree = FittingTreeBuilder.build(
            items: catalog.items, shipInfo: catalog.shipInfo, groupByType: catalog.groupByType
        )
        unreadableFittings = fileUnreadable + skippedUnreadable
    }

    /// 搜索：匹配飞船本地化名称 / 装配名称 / 飞船 typeID，按飞船名、装配名排序
    func searchMatches(query: String) -> [FittingItemNode] {
        FittingTreeBuilder.searchMatches(tree: tree, shipInfo: shipInfo, query: query)
    }

    private func fileName(for fittingId: UUID) -> String {
        (try? FitConvert.localFittingFileURL(fittingId: fittingId).lastPathComponent)
            ?? "local_fitting_\(fittingId.uuidString).json"
    }

    func deleteFitting(fittingId: UUID) {
        _ = deleteFittings(fittingIds: [fittingId])
    }

    /// 单条和批量共用删除结果，失败项由目录保留以便重试。
    func deleteFittings(fittingIds: Set<UUID>) -> Set<UUID> {
        let files = fittingIds.map { (id: $0, name: fileName(for: $0)) }
        let deleted = deleteFiles(matchingFileNames: files.map(\.name))
        return Set(files.filter { deleted.contains($0.name) }.map(\.id))
    }

    /// 删除无法解析的装配文件（按文件名定位；仅清列表不清正常数据）
    func deleteUnreadableFitting(fileName: String) {
        deleteFiles(matchingFileNames: [fileName])
    }

    /// 一键清除全部无法解析的装配文件
    func deleteAllUnreadableFittings() {
        deleteFiles(matchingFileNames: unreadableFittings.map(\.fileName))
    }

    /// 按文件名批量删除装配文件，随后重载列表
    @discardableResult
    private func deleteFiles(matchingFileNames fileNames: [String]) -> Set<String> {
        guard !fileNames.isEmpty,
              let documentsDirectory = FileManager.default.urls(
                  for: .documentDirectory, in: .userDomainMask
              ).first
        else { return [] }

        let fittingsDirectory = documentsDirectory.appendingPathComponent("Fitting")
        var deleted: Set<String> = []
        errorMessage = nil
        for fileName in Set(fileNames).sorted() {
            do {
                let fileURL = fittingsDirectory.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                deleted.insert(fileName)
            } catch {
                Logger.error("删除装配文件失败 \(fileName): \(error.localizedDescription)")
            }
        }
        if deleted.count != Set(fileNames).count {
            errorMessage = NSLocalizedString("Error_Delete_Fitting", comment: "")
        }

        // 重载：正常装配与无法解析列表同步刷新
        do {
            let result = try FitConvert.loadAllLocalFittings()
            apply(result.fittings, fileUnreadable: result.unreadable)
        } catch {
            Logger.error("重载本地配置失败: \(error)")
        }
        return deleted
    }
}

/// 在线配置视图模型
@MainActor
final class OnlineFittingViewModel: ObservableObject {
    /// 预构造导航树（唯一列表数据源）
    @Published private(set) var tree: [FittingGroupNode] = []
    /// 全量装配字典（详情零二次加载、零竞态）
    @Published private(set) var fittingsByID: [Int: CharacterFitting] = [:]
    @Published private(set) var shipInfo: [Int: FittingShipInfo] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var initialLoadDone = false
    private var loadingTask: Task<Void, Never>?
    private let fetchFittings: (Int, Bool) async throws -> [CharacterFitting]

    let characterId: Int?
    let databaseManager: DatabaseManager

    init(
        characterId: Int?, databaseManager: DatabaseManager,
        fetchFittings: @escaping (Int, Bool) async throws -> [CharacterFitting] = {
            try await CharacterFittingAPI.getCharacterFittings(characterID: $0, forceRefresh: $1)
        }
    ) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        self.fetchFittings = fetchFittings
    }

    deinit {
        loadingTask?.cancel()
    }

    func loadOnlineFittings(forceRefresh: Bool = false) async {
        // 如果没有角色ID，则直接返回
        guard let characterId = characterId else {
            Logger.error("尝试加载在线配置但没有characterId")
            return
        }

        let loadID = UUID().uuidString.prefix(8)
        Logger.info("[在线装配加载 \(loadID)] 开始：角色=\(characterId)，forceRefresh=\(forceRefresh)，调用方已取消=\(Task.isCancelled)，现有装配=\(fittingsByID.count)，现有分组=\(tree.count)")

        if initialLoadDone, !forceRefresh {
            Logger.info("[在线装配加载 \(loadID)] 复用已加载目录：装配=\(fittingsByID.count)，分组=\(tree.count)")
            return
        }
        if let loadingTask, !forceRefresh {
            Logger.info("[在线装配加载 \(loadID)] 等待正在进行的预加载")
            await loadingTask.value
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                // 获取在线配置数据（ESI 返回全量 items）
                let fittings = try await fetchFittings(characterId, forceRefresh)
                Logger.info("[在线装配加载 \(loadID)] 数据返回：数量=\(fittings.count)，任务已取消=\(Task.isCancelled)")

                if Task.isCancelled {
                    Logger.debug("[在线装配加载 \(loadID)] 数据返回后任务取消，保留现有目录")
                    return
                }

                var byID: [Int: CharacterFitting] = [:]
                var entries: [FittingCatalogEntry] = []

                for fitting in fittings {
                    if FittingDeletionCacheManager.shared.isDeleted(
                        fittingId: fitting.fitting_id, characterId: characterId
                    ) {
                        Logger.debug("跳过已删除的配置 ID: \(fitting.fitting_id)")
                        continue
                    }

                    byID[fitting.fitting_id] = fitting
                    entries.append(
                        (ref: .online(fitting.fitting_id), name: fitting.name, shipTypeId: fitting.ship_type_id)
                    )
                }

                let catalog = FittingTreeBuilder.catalog(from: entries)
                Logger.info("[在线装配加载 \(loadID)] 分组准备：删除过滤=\(fittings.count - entries.count)，有效条目=\(catalog.items.count)，缺少飞船信息=\(catalog.skipped.count)")
                if !catalog.skipped.isEmpty {
                    Logger.warning("[在线装配加载 \(loadID)] 缺少目录信息的飞船：\(Set(catalog.skipped.map(\.shipTypeId)).sorted())")
                }

                if Task.isCancelled {
                    Logger.debug("[在线装配加载 \(loadID)] 分组后任务取消，保留现有目录")
                    return
                }

                self.fittingsByID = byID
                self.shipInfo = catalog.shipInfo
                self.tree = FittingTreeBuilder.build(
                    items: catalog.items, shipInfo: catalog.shipInfo, groupByType: catalog.groupByType
                )

                // 打印缓存统计信息（调试用）
                FittingDeletionCacheManager.shared.printCacheStats()

                self.initialLoadDone = true
                Logger.info("[在线装配加载 \(loadID)] 目录更新：装配=\(fittingsByID.count)，飞船=\(shipInfo.count)，分组=\(tree.count)")
            } catch {
                if !Task.isCancelled {
                    Logger.error("[在线装配加载 \(loadID)] 失败：\(error)，保留装配=\(fittingsByID.count)，分组=\(tree.count)")
                    self.errorMessage = error.localizedDescription
                } else {
                    Logger.debug("[在线装配加载 \(loadID)] 异常返回时任务已取消：\(error)")
                }
            }

            if !Task.isCancelled {
                self.isLoading = false
                self.loadingTask = nil
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    /// 搜索：匹配飞船本地化名称 / 装配名称 / 飞船 typeID，按飞船名、装配名排序
    func searchMatches(query: String) -> [FittingItemNode] {
        FittingTreeBuilder.searchMatches(tree: tree, shipInfo: shipInfo, query: query)
    }

    /// 单条删除沿用批量流程，确保缓存和目录更新时机一致。
    func deleteFitting(fittingId: Int) {
        Task { _ = await deleteFittings(fittingIds: [fittingId]) }
    }

    /// 顺序请求避免大量并发删除；成功项即时从目录移除，失败项保留。
    func deleteFittings(fittingIds: Set<Int>) async -> Set<Int> {
        guard let characterId else { return [] }
        var deleted: Set<Int> = []
        for fittingId in fittingIds.sorted() {
            do {
                try await CharacterFittingAPI.deleteCharacterFitting(
                    characterID: characterId, fittingID: fittingId
                )
                FittingDeletionCacheManager.shared.addDeletedFitting(
                    fittingId: fittingId, characterId: characterId
                )
                deleted.insert(fittingId)
                refreshDisplayedFittings()
            } catch {
                Logger.error("批量删除在线装配失败 \(fittingId): \(error)")
            }
        }
        return deleted
    }

    /// 刷新显示的配置列表（基于删除标记过滤后重建树）
    func refreshDisplayedFittings() {
        guard let characterId = characterId else { return }

        let kept = fittingsByID.values.filter {
            !FittingDeletionCacheManager.shared.isDeleted(
                fittingId: $0.fitting_id, characterId: characterId
            )
        }

        let catalog = FittingTreeBuilder.catalog(
            from: kept.map {
                (ref: .online($0.fitting_id), name: $0.name, shipTypeId: $0.ship_type_id)
            }
        )

        var byID: [Int: CharacterFitting] = [:]
        for fitting in kept {
            byID[fitting.fitting_id] = fitting
        }

        fittingsByID = byID
        shipInfo = catalog.shipInfo
        tree = FittingTreeBuilder.build(
            items: catalog.items, shipInfo: catalog.shipInfo, groupByType: catalog.groupByType
        )
    }
}
