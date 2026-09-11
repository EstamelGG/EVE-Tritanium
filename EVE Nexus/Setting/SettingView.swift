import CommonCrypto
import SwiftUI
import UIKit

// MARK: - 数据模型

struct SettingItem: Identifiable {
    /// 使用 title 作为 ID，避免每次重建
    var id: String {
        title
    }

    let title: String
    let detail: String?
    let icon: String?
    let iconColor: Color
    let action: () -> Void
    var customView: ((SettingItem) -> AnyView)?

    init(
        title: String, detail: String? = nil, icon: String? = nil, iconColor: Color = .blue,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
        customView = nil
    }

    init<V: View>(
        title: String, detail: String? = nil, icon: String? = nil, iconColor: Color = .blue,
        action: @escaping () -> Void, @ViewBuilder customView: @escaping (SettingItem) -> V
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
        self.customView = { AnyView(customView($0)) }
    }
}

// MARK: - 设置组

struct SettingGroup: Identifiable {
    /// 使用 header 作为 ID，避免每次重建
    var id: String {
        header
    }

    let header: String
    let items: [SettingItem]
}

// MARK: - 缓存管理器

class CacheManager {
    static let shared = CacheManager()
    private let fileManager = FileManager.default

    /// 定义需要清理的缓存键前缀
    private let cachePrefixes = [
        "character_portrait_",
    ]

    /// 定义需要清理的目录列表
    private let cacheDirs = [
        "StructureCache", // 建筑缓存
        "AssetCache", // 资产缓存
        "StaticDataSet", // 临时静态数据
        "ContactsCache", // 声望
        "kb", // 战斗日志（zkillboard 列表数据）
        "BRKillmails", // 战斗日志细节（旧格式，保留兼容）
        "ESIKillmails", // ESI 战斗日志详情缓存
        "MarketCache", // 市场价格细节
        "Planetary", // 行星开发
        "CharacterOrders", // 人物市场订单
        "fw", // 势力战争
        "CorpCache", // 军团缓存
        "char_standings", // 人物声望
        "Structure_Orders", // 建筑订单
        "IndustryJobs", // 工业项目
        "CharacterSkills", // 角色技能相关缓存（技能、技能队列、属性、克隆体、植入体、忠诚点）
        "CorpAllianceHistory", // 雇佣历史
        "AllianceCache", // 联盟信息
        "IncursionsCache", // 萨沙入侵缓存
        "CharWallet", // 个人钱包
        "CorpWallet", // 军团钱包
        "image_cache", // 图片缓存（ImageCacheManager）
        "github_market_cache", // Jita 订单汇总缓存
    ]

    /// 获取缓存目录列表
    func getCacheDirs() -> [String] {
        return cacheDirs
    }

    /// 清理指定前缀的缓存
    private func clearCacheWithPrefixes() {
        let defaults = UserDefaults.standard
        let allKeys = defaults.dictionaryRepresentation().keys

        // 遍历所有键
        for key in allKeys {
            // 检查是否有匹配的前缀
            if cachePrefixes.contains(where: { key.hasPrefix($0) }) {
                Logger.debug("正在清理缓存键: \(key)")
                defaults.removeObject(forKey: key)
            }
        }
        defaults.synchronize()
        Logger.info("基于前缀的缓存清理完成")
    }

    /// 清理指定目录
    private func clearCacheDirectories() async {
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var totalFilesRemoved = 0

        for dirName in cacheDirs {
            let dirPath = documentPath.appendingPathComponent(dirName)

            do {
                if fileManager.fileExists(atPath: dirPath.path) {
                    // 统计目录中的所有文件数量（包括子目录）
                    var fileCount = 0

                    if let enumerator = fileManager.enumerator(
                        at: dirPath,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            do {
                                let resourceValues = try fileURL.resourceValues(forKeys: [
                                    .isRegularFileKey,
                                ])
                                // 只计算文件，不计算目录本身
                                if resourceValues.isRegularFile == true {
                                    fileCount += 1
                                }
                            } catch {
                                Logger.error("获取文件属性失败 - \(fileURL.path): \(error)")
                            }
                        }
                    }

                    // 删除并重建目录
                    try fileManager.removeItem(at: dirPath)
                    try fileManager.createDirectory(at: dirPath, withIntermediateDirectories: true)

                    // 更新总计数
                    totalFilesRemoved += fileCount

                    // 记录日志
                    Logger.success("成功清理并重建目录: \(dirName)，删除了 \(fileCount) 个文件")
                }
            } catch {
                Logger.error("清理目录失败 - \(dirName): \(error)")
            }
        }

        Logger.info("目录缓存清理完成，共删除 \(totalFilesRemoved) 个文件")
    }

    /// 清理图片缓存
    private func clearImageCaches() async {
        // 清理自定义图片缓存管理器
        await ImageCacheManager.shared.clearAllCache()
        Logger.info("图片缓存清理完成")
    }

    /// 清理所有缓存
    func clearAllCaches() async {
        // 1. 清理 NetworkManager 缓存
        await NetworkManager.shared.clearAllCaches()

        // 2. 清理临时文件
        let tempPath = NSTemporaryDirectory()
        do {
            let files = try await MainActor.run {
                try self.fileManager.contentsOfDirectory(atPath: tempPath)
            }
            for file in files {
                let filePath = (tempPath as NSString).appendingPathComponent(file)
                try? await MainActor.run {
                    try self.fileManager.removeItem(atPath: filePath)
                }
            }
        } catch {
            Logger.error("清理临时文件失败: \(error)")
        }

        // 3. 清理基于前缀的缓存
        await MainActor.run {
            clearCacheWithPrefixes()
        }

        // 4. 清理目录缓存
        await clearCacheDirectories()

        // 5. 清理静态资源
        do {
            try StaticResourceManager.shared.clearAllStaticData()
        } catch {
            Logger.error("清理静态资源失败: \(error)")
        }

        // 6. 清理建筑物缓存
        await UniverseStructureAPI.shared.clearCache()

        // 7. 清理图片缓存
        await clearImageCaches()

        // 8. 清理 Swift URLCache
        await MainActor.run {
            URLCache.shared.removeAllCachedResponses()
            Logger.info("URLCache 清理完成")
        }

        Logger.info("所有缓存清理完成")
    }
}

// MARK: - 设置视图

struct SettingView: View {
    // MARK: - 界面组件

    private let fileManager = FileManager.default

    /// SDE 重置全屏进度页：纯展示，关闭由 resetSDEAndIcons 的成功/失败路径直接控制
    private struct FullScreenCover: View {
        let progress: Double

        var body: some View {
            StartupSplashView(stage: .extracting, progress: progress)
                .edgesIgnoringSafeArea(.all)
                .interactiveDismissDisabled()
        }
    }

    // MARK: - 属性定义

    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @AppStorage("enableLogging") private var enableLogging: Bool = false
    @State private var showingCleanCacheAlert = false
    @State private var showingCleanCharacterDatabaseAlert = false
    @State private var showingLanguageView = false
    @State private var cacheSize: String = NSLocalizedString("Misc_Calculating", comment: "")
    @ObservedObject var databaseManager: DatabaseManager
    @State private var isCleaningCache = false
    @State private var isCleaningCharacterDatabase = false
    @State private var isResettingSDE = false
    @State private var unzipProgress: Double = 0
    @State private var showingLoadingView = false
    @State private var settingGroups: [SettingGroup] = []
    @State private var showResetSDEDatabaseAlert = false
    @State private var showResetSDEDatabaseSuccessAlert = false
    @State private var showingESIStatusView = false
    @State private var showingRateLimitMonitorView = false
    @State private var showingLogsBrowserView = false
    @State private var showingMarketStructureView = false
    @State private var showingEVEStatusIncidentsView = false
    @State private var isCalculatingCache = false // 缓存计算状态
    @State private var showingTokenScopesView = false // 显示 token scopes sheet
    @State private var showingTokenViewerView = false // 显示 token 查看页
    @State private var showingFittingDefaultSkillView = false
    @State private var showingNotificationsManagerView = false

    // MARK: - 数据更新函数

    private func updateAllData() {
        Task {
            // 标记开始计算
            await MainActor.run {
                isCalculatingCache = true
            }

            // 目录统计信息结构
            struct DirectoryStats {
                let name: String
                var fileCount: Int = 0
                var totalSize: Int64 = 0
            }

            var totalSize: Int64 = 0
            var fileCount = 0
            let largeFileThreshold: Int64 = 10 * 1024 * 1024 // 10MB
            let fileCountThreshold = 200
            var directoryStats: [DirectoryStats] = []

            // 计算缓存目录大小
            let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            // 使用CacheManager中的缓存目录列表（包含StaticDataSet）
            let cacheDirs = CacheManager.shared.getCacheDirs()

            for dirName in cacheDirs {
                let dirPath = documentPath.appendingPathComponent(dirName)
                var dirStats = DirectoryStats(name: dirName)

                if fileManager.fileExists(atPath: dirPath.path),
                   let enumerator = fileManager.enumerator(
                       at: dirPath,
                       includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                       options: [.skipsHiddenFiles]
                   )
                {
                    while let fileURL = enumerator.nextObject() as? URL {
                        do {
                            // 使用 resourceValues 一次性获取所有需要的信息
                            let resourceValues = try fileURL.resourceValues(forKeys: [
                                .fileSizeKey,
                                .isRegularFileKey,
                            ])
                            // 只统计文件，跳过目录
                            if resourceValues.isRegularFile == true {
                                if let fileSize = resourceValues.fileSize {
                                    let size = Int64(fileSize)
                                    totalSize += size
                                    fileCount += 1
                                    dirStats.fileCount += 1
                                    dirStats.totalSize += size

                                    // 只有当文件大小超过10MB时才记录警告
                                    if size > largeFileThreshold {
                                        Logger.warning(
                                            "大文件: \(fileURL.path) - \(FormatUtil.formatFileSize(size))"
                                        )
                                    }
                                }
                            }
                        } catch {
                            Logger.error(
                                "计算文件大小失败 - \(fileURL.path): \(error)"
                            )
                        }
                    }
                }

                if dirStats.fileCount > 0 {
                    directoryStats.append(dirStats)
                }
            }

            // 如果文件总数超过阈值，记录警告并显示前3个文件最多的目录
            if fileCount > fileCountThreshold {
                // 按文件数排序，取前3个
                let topDirectories = directoryStats
                    .sorted { $0.fileCount > $1.fileCount }
                    .prefix(3)

                var warningMessage = "缓存文件较多（\(fileCount)个），文件数最多的目录："
                for (index, dir) in topDirectories.enumerated() {
                    if index > 0 {
                        warningMessage += "、"
                    }
                    warningMessage += "\(dir.name)(\(dir.fileCount)个文件, \(FormatUtil.formatFileSize(dir.totalSize)))"
                }
                Logger.warning(warningMessage)
            }

            // 更新界面
            await MainActor.run {
                let formattedSize = FormatUtil.formatFileSize(totalSize)
                self.cacheSize = formattedSize
                self.isCalculatingCache = false
                self.updateSettingGroups()
            }
        }
    }

    private func updateSettingGroups() {
        settingGroups = [
            createAppearanceGroup(),
            createCorporationAffairsGroup(),
            createMarketStructureGroup(),
            createFittingSimulationGroup(),
            createOthersGroup(),
            createLogsGroup(),
            createCacheGroup(),
            createSDEResetGroup(),
        ]
    }

    // MARK: - 设置组创建函数

    private func createAppearanceGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Main_Setting_Appearance", comment: ""),
            items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_ColorMode", comment: ""),
                    detail: getAppearanceDetail(), // 将当前主题状态作为详情文本
                    icon: getThemeIcon(),
                    iconColor: .blue,
                    action: toggleAppearance
                ),
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Language", comment: ""),
                    detail: NSLocalizedString("Main_Setting_Select_your_language", comment: ""),
                    icon: "translate",
                    action: { showingLanguageView = true }
                ),
            ]
        )
    }

    private func toggleAppearance() {
        switch selectedTheme {
        case "light":
            selectedTheme = "dark"
        case "dark":
            selectedTheme = "system"
        case "system":
            selectedTheme = "light"
        default:
            break
        }
    }

    private struct CorporationAffairsToggle: View {
        @AppStorage("showCorporationAffairs") private var showCorporationAffairs: Bool = false

        var body: some View {
            HStack {
                Toggle(isOn: $showCorporationAffairs) {
                    VStack(alignment: .leading) {
                        Text(
                            NSLocalizedString("Main_Setting_Show_Corporation_Affairs", comment: "")
                        )
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        Text(
                            NSLocalizedString(
                                "Main_Setting_Show_Corporation_Affairs_detail", comment: ""
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    }
                }
                .tint(.green)
            }
        }
    }

    private struct ShowImportantAttributesToggle: View {
        @State private var showImportantOnly: Bool = AttributeDisplayConfig.showImportantOnly

        var body: some View {
            HStack {
                Toggle(isOn: $showImportantOnly) {
                    VStack(alignment: .leading) {
                        Text(
                            NSLocalizedString(
                                "Main_Database_Show_Important_Only", comment: "只显示重要属性"
                            )
                        )
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        Text(
                            NSLocalizedString(
                                "Main_Database_Show_Important_Only_Detail",
                                comment: "只显示有display_name的属性"
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    }
                }
                .tint(.green)
                .onChange(of: showImportantOnly) { _, newValue in
                    AttributeDisplayConfig.showImportantOnly = newValue
                }
            }
        }
    }

    private func createCorporationAffairsGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Main_Setting_Function", comment: ""),
            items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Show_Corporation_Affairs", comment: ""),
                    detail: nil,
                    iconColor: .blue,
                    action: {}
                ) { _ in
                    AnyView(CorporationAffairsToggle())
                },
            ]
        )
    }

    #if DEBUG
        /// GitHub SDE 更新开关（仅 Debug 构建可见；开启后检查与下载均改用 GitHub Release）
        private struct GitHubSDESourceToggle: View {
            @AppStorage(SDEUpdateChecker.useGitHubKey) private var useGitHubSDE = false

            var body: some View {
                HStack {
                    Toggle(isOn: $useGitHubSDE) {
                        VStack(alignment: .leading) {
                            Text(NSLocalizedString("Main_Setting_Use_GitHub_SDE", comment: "使用 GitHub 更新 SDE"))
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            Text(NSLocalizedString("Main_Setting_Use_GitHub_SDE_Detail", comment: "检查与下载改用 GitHub Release（仅调试）"))
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    .tint(.green)
                    .onChange(of: useGitHubSDE) { _, isOn in
                        guard isOn else { return }
                        // 开启后立即用新数据源强制检查一次（绕过节流）
                        Task { await SDEUpdateChecker.shared.forceCheckForUpdates() }
                    }
                }
            }
        }
    #endif

    private func createOthersGroup() -> SettingGroup {
        var items = [
            SettingItem(
                title: NSLocalizedString("Main_Setting_Notification_Manage", comment: ""),
                detail: NSLocalizedString("Main_Setting_Notification_Manage_Detail", comment: ""),
                icon: "bell.badge",
                iconColor: .blue,
                action: { showingNotificationsManagerView = true }
            ),
            SettingItem(
                title: NSLocalizedString("Main_Setting_ESI_Status", comment: ""),
                detail: NSLocalizedString("Main_Setting_ESI_Status_Detail", comment: ""),
                icon: "waveform.path.ecg.rectangle",
                iconColor: .blue,
                action: { showingESIStatusView = true }
            ),
            SettingItem(
                title: NSLocalizedString("RateLimit_Monitor_Title", comment: ""),
                detail: NSLocalizedString("RateLimit_Monitor_Detail", comment: ""),
                icon: "gauge.with.dots.needle.67percent",
                iconColor: .blue,
                action: { showingRateLimitMonitorView = true }
            ),
            SettingItem(
                title: NSLocalizedString("EVE_Status_Incidents_Title", comment: "EVE Online 故障通知"),
                detail: NSLocalizedString("EVE_Status_Incidents_Detail", comment: "查看EVE Online服务状态和故障通知"),
                icon: "exclamationmark.triangle",
                iconColor: .orange,
                action: { showingEVEStatusIncidentsView = true }
            ),
            SettingItem(
                title: NSLocalizedString("Main_Database_Attribute_Settings", comment: "属性显示设置"),
                detail: nil,
                iconColor: .blue,
                action: {}
            ) { _ in
                AnyView(ShowImportantAttributesToggle())
            },
        ]

        #if DEBUG
            items.append(
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Use_GitHub_SDE", comment: "使用 GitHub 更新 SDE"),
                    detail: nil,
                    iconColor: .purple,
                    action: {}
                ) { _ in
                    AnyView(GitHubSDESourceToggle())
                }
            )
        #endif

        return SettingGroup(
            header: NSLocalizedString("Main_Setting_Others", comment: ""),
            items: items
        )
    }

    private func createFittingSimulationGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Fitting_Setting_Simulation_Section", comment: "装配模拟"),
            items: [
                SettingItem(
                    title: NSLocalizedString("Fitting_Setting_Default_Character", comment: "默认角色"),
                    detail: NSLocalizedString("Fitting_Setting_Default_Character_Detail", comment: "默认使用哪个角色的技能数据来计算属性"),
                    icon: "person.crop.circle",
                    iconColor: .blue,
                    action: { showingFittingDefaultSkillView = true }
                ),
            ]
        )
    }

    private func createMarketStructureGroup() -> SettingGroup {
        SettingGroup(
            header: NSLocalizedString("Main_Setting_Market_Structure_Section", comment: ""),
            items: [
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Market_Structure_Manage", comment: ""),
                    detail: NSLocalizedString(
                        "Main_Setting_Market_Structure_Manage_Detail", comment: ""
                    ),
                    action: { showingMarketStructureView = true }
                ),
            ]
        )
    }

    /// 日志开关组件
    private struct LoggingToggle: View {
        @Binding var enableLogging: Bool

        var body: some View {
            HStack {
                Toggle(isOn: $enableLogging) {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("Main_Setting_Enable_Logging", comment: ""))
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        Text(NSLocalizedString("Main_Setting_Enable_Logging_Detail", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                .tint(.green)
            }
        }
    }

    private func createLogsGroup() -> SettingGroup {
        var items: [SettingItem] = [
            SettingItem(
                title: NSLocalizedString("Main_Setting_Enable_Logging", comment: ""),
                detail: nil,
                iconColor: .blue,
                action: {}
            ) { _ in
                AnyView(LoggingToggle(enableLogging: $enableLogging))
            },
        ]

        // 只有在启用日志时才显示"查看日志"和"查看 token scopes"按钮
        if enableLogging {
            items.append(
                SettingItem(
                    title: NSLocalizedString("Main_Setting_View_Logs", comment: ""),
                    detail: NSLocalizedString("Main_Setting_View_Logs_Detail", comment: ""),
                    icon: "doc.text.magnifyingglass",
                    iconColor: .blue,
                    action: { showingLogsBrowserView = true }
                )
            )
            items.append(
                SettingItem(
                    title: NSLocalizedString("Main_Setting_View_Token_Scopes", comment: "查看 Token scopes"),
                    detail: NSLocalizedString("Main_Setting_View_Token_Scopes_Detail", comment: "查看所有已保存人物的 token scopes"),
                    icon: "key.fill",
                    iconColor: .blue,
                    action: { showingTokenScopesView = true }
                )
            )
            items.append(
                SettingItem(
                    title: NSLocalizedString("Main_Setting_View_Token", comment: "查看 Token"),
                    detail: NSLocalizedString("Main_Setting_View_Token_Detail", comment: "查看 refresh token 与 access token"),
                    icon: "lock.doc",
                    iconColor: .blue,
                    action: { showingTokenViewerView = true }
                )
            )
        }

        return SettingGroup(
            header: NSLocalizedString("Main_Setting_Logs_Section", comment: ""),
            items: items
        )
    }

    private func createCacheGroup() -> SettingGroup {
        var items: [SettingItem] = [
            SettingItem(
                title: NSLocalizedString("Main_Setting_Clean_Cache", comment: ""),
                detail: cacheSize,
                icon: isCleaningCache ? "arrow.triangle.2.circlepath" : "trash",
                iconColor: .orange,
                action: {
                    if !isCalculatingCache, !isCleaningCache {
                        showingCleanCacheAlert = true
                    }
                }
            ),
        ]

        // 只有在启用调试模式（日志）时才显示清理人物数据按钮
        if enableLogging {
            items.append(
                SettingItem(
                    title: NSLocalizedString("Main_Setting_Clean_Character_Database", comment: ""),
                    detail: NSLocalizedString("Main_Setting_Clean_Character_Database_Detail", comment: ""),
                    icon: isCleaningCharacterDatabase ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.minus",
                    iconColor: .red,
                    action: {
                        if !isCleaningCharacterDatabase {
                            showingCleanCharacterDatabaseAlert = true
                        }
                    }
                )
            )
        }

        return SettingGroup(
            header: NSLocalizedString("Main_Setting_Cache", comment: ""),
            items: items
        )
    }

    private func createSDEResetGroup() -> SettingGroup {
        return SettingGroup(
            header: NSLocalizedString("SDE_Reset_Section", comment: "重置 SDE"),
            items: [
                SettingItem(
                    title: NSLocalizedString("SDE_Reset_Database", comment: ""),
                    detail: isResettingSDE
                        ? String(format: "%.0f%%", unzipProgress * 100)
                        : NSLocalizedString("SDE_Reset_Database_Detail", comment: ""),
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .red,
                    action: { showResetSDEDatabaseAlert = true }
                ),
            ]
        )
    }

    /// 列表项渲染组件
    private struct SettingItemView: View {
        let item: SettingItem
        let isCleaningCache: Bool
        let isCleaningCharacterDatabase: Bool
        let showingLoadingView: Bool
        let isCalculatingCache: Bool
        let isResettingSDE: Bool

        private var isLoading: Bool {
            (item.title == NSLocalizedString("Main_Setting_Clean_Cache", comment: "") && isCleaningCache) ||
                (item.title == NSLocalizedString("Main_Setting_Clean_Character_Database", comment: "") && isCleaningCharacterDatabase) ||
                (item.title == NSLocalizedString("SDE_Reset_Database", comment: "") && isResettingSDE)
        }

        var body: some View {
            if let customView = item.customView {
                customView(item)
                    .disabled(isCleaningCache || isCleaningCharacterDatabase || showingLoadingView)
            } else {
                Button(action: item.action) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)

                            if item.title == NSLocalizedString("Main_Setting_Clean_Cache", comment: "") && isCalculatingCache {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(item.detail ?? "")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            } else if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                        if let icon = item.icon {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 36)
                            } else {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .frame(width: 36)
                                    .foregroundColor(item.iconColor)
                            }
                        }
                    }
                }
                .disabled(
                    isCleaningCache || isCleaningCharacterDatabase || showingLoadingView || isResettingSDE ||
                        (item.title == NSLocalizedString("Main_Setting_Clean_Cache", comment: "") && isCalculatingCache)
                )
            }
        }
    }

    // MARK: - 视图主体

    var body: some View {
        List {
            ForEach(settingGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        SettingItemView(
                            item: item,
                            isCleaningCache: isCleaningCache,
                            isCleaningCharacterDatabase: isCleaningCharacterDatabase,
                            showingLoadingView: showingLoadingView,
                            isCalculatingCache: isCalculatingCache,
                            isResettingSDE: isResettingSDE
                        )
                    }
                } header: {
                    Text(group.header)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(isPresented: $showingLanguageView) {
            SelectLanguageView(databaseManager: databaseManager)
        }
        .navigationDestination(isPresented: $showingESIStatusView) {
            ESIStatusView()
        }
        .navigationDestination(isPresented: $showingRateLimitMonitorView) {
            RateLimitMonitorView()
        }
        .navigationDestination(isPresented: $showingLogsBrowserView) {
            LogsBrowserView()
        }
        .navigationDestination(isPresented: $showingMarketStructureView) {
            MarketStructureSettingsView()
        }
        .navigationDestination(isPresented: $showingFittingDefaultSkillView) {
            FittingDefaultSkillSettingView()
        }
        .navigationDestination(isPresented: $showingEVEStatusIncidentsView) {
            EVEStatusIncidentsView()
        }
        .navigationDestination(isPresented: $showingNotificationsManagerView) {
            NotificationsManagerView()
        }
        .sheet(isPresented: $showingTokenScopesView) {
            TokenScopesListView()
        }
        .navigationDestination(isPresented: $showingTokenViewerView) {
            TokenViewerView()
        }
        .alert(
            NSLocalizedString("Main_Setting_Clean_Cache_Title", comment: ""),
            isPresented: $showingCleanCacheAlert
        ) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Main_Setting_Clean", comment: ""), role: .destructive) {
                cleanCache()
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Clean_Cache_Message", comment: ""))
        }
        .alert(
            NSLocalizedString("Main_Setting_Clean_Character_Database_Title", comment: ""),
            isPresented: $showingCleanCharacterDatabaseAlert
        ) {
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Main_Setting_Clean", comment: ""), role: .destructive) {
                cleanCharacterDatabase()
            }
        } message: {
            Text(NSLocalizedString("Main_Setting_Clean_Character_Database_Message", comment: ""))
        }
        .alert(
            NSLocalizedString("SDE_Reset_Confirm_Title", comment: ""),
            isPresented: $showResetSDEDatabaseAlert
        ) {
            Button(NSLocalizedString("SDE_Reset_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("SDE_Reset_Confirm", comment: ""), role: .destructive) {
                resetSDEAndIcons()
            }
        } message: {
            Text(NSLocalizedString("SDE_Reset_Message", comment: ""))
        }
        .alert(
            NSLocalizedString("SDE_Reset_Success_Title", comment: ""),
            isPresented: $showResetSDEDatabaseSuccessAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("SDE_Reset_Success_Message", comment: ""))
        }
        .onAppear {
            // 立即显示骨架界面（此时 cacheSize 是 "计算中..."）
            updateSettingGroups()
            // 在后台异步计算缓存大小
            updateAllData()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            updateAllData() // 从后台返回时更新
        }
        .onChange(of: selectedTheme) { _, _ in
            updateSettingGroups() // 主题改变时更新
        }
        .onChange(of: enableLogging) { _, _ in
            updateSettingGroups() // 日志开关改变时更新
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .fullScreenCover(isPresented: $showingLoadingView) {
            FullScreenCover(progress: unzipProgress)
        }
    }

    // MARK: - 主题管理

    private func getThemeIcon() -> String {
        switch selectedTheme {
        case "light":
            return "sun.max.fill"
        case "dark":
            return "moon.fill"
        case "system":
            return "circle.lefthalf.fill"
        default:
            return "circle.lefthalf.fill"
        }
    }

    private func getAppearanceDetail() -> String {
        switch selectedTheme {
        case "light":
            return NSLocalizedString("Main_Setting_Light", comment: "")
        case "dark":
            return NSLocalizedString("Main_Setting_Dark", comment: "")
        case "system":
            return NSLocalizedString("Main_Setting_Auto", comment: "")
        default:
            return NSLocalizedString("Main_Setting_Auto", comment: "")
        }
    }

    // MARK: - 缓存管理

    private func cleanCache() {
        Task {
            isCleaningCache = true
            defer { isCleaningCache = false }

            do {
                // 清理所有缓存
                await CacheManager.shared.clearAllCaches()

                // 更新UI
                await MainActor.run {
                    updateAllData()
                }

                Logger.info("Cache cleaned successfully")
            }
        }
    }

    // MARK: - 人物数据管理

    private func cleanCharacterDatabase() {
        Task {
            isCleaningCharacterDatabase = true
            defer { isCleaningCharacterDatabase = false }

            do {
                // 重置角色数据库
                CharacterDatabaseManager.shared.resetDatabase()

                Logger.info("Character database cleaned successfully")
            }
        }
    }

    // MARK: - SDE/图标重置

    /// 重置SDE数据库（同时重新解压SDE数据包与图标包，并清空相关内存缓存）
    private func resetSDEAndIcons() {
        Task {
            isResettingSDE = true
            showingLoadingView = true
            unzipProgress = 0

            do {
                // 删除本地SDE目录（包含数据库与图标）
                try StaticResourceManager.shared.resetSDEDatabase()

                // 从Bundle重新解压SDE + icons
                try await SDEDownloader().seedFromBundle { progress in
                    Task { @MainActor in
                        self.unzipProgress = progress
                    }
                }

                // 清空所有相关内存/查询缓存，确保旧数据不会继续显示
                await MainActor.run {
                    IconManager.shared.clearCache()
                    DatabaseManager.shared.clearCache()
                    self.reloadDataWithNewSDE()
                    SDEUpdateChecker.shared.clearCheckCache()
                    // 完成后直接关闭全屏进度页并刷新数据（原 loadingState 中间层已移除）
                    self.showingLoadingView = false
                    self.updateAllData() // SDE/图标重置完成后更新
                    self.isResettingSDE = false
                    self.showResetSDEDatabaseSuccessAlert = true
                }

                Logger.info("SDE与图标数据重置完成")
            } catch {
                Logger.error("重置SDE与图标数据失败: \(error)")
                await MainActor.run {
                    self.isResettingSDE = false
                    self.showingLoadingView = false
                }
            }
        }
    }

    /// 重新加载数据以使用新的SDE数据
    private func reloadDataWithNewSDE() {
        Logger.info("Reloading data with new SDE...")

        LocalizationManager.shared.loadAccountingEntryTypes()
        DatabaseManager.shared.loadDatabase()
        ItemTextStore.shared.syncWithActiveSDE()
        AttributeCompareMarketPolicy.reload()

        Logger.info("Data reload completed with new SDE")
    }
}

// MARK: - 下载进度视图

struct DownloadProgressView: View {
    let iconsState: PackageUpdateState
    let sdeState: PackageUpdateState
    let iconsVersion: String
    let sdeVersion: String
    let hasError: Bool
    let isCompleted: Bool
    let onExit: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    PackageUpdateCard(
                        title: NSLocalizedString("SDE_Icon_Package", comment: "图标包"),
                        version: iconsVersion,
                        systemImage: "photo.on.rectangle.angled",
                        state: iconsState
                    )
                    PackageUpdateCard(
                        title: NSLocalizedString("SDE_Data_Package", comment: "SDE数据包"),
                        version: sdeVersion,
                        systemImage: "externaldrive.fill",
                        state: sdeState
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(NSLocalizedString("SDE_Update_Details", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasError || isCompleted {
                    Button(action: onExit) {
                        Text(hasError
                            ? NSLocalizedString("SDE_Exit", comment: "")
                            : NSLocalizedString("SDE_Done", comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hasError ? .red : .green)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: hasError || isCompleted)
        }
    }
}

private struct PackageUpdateCard: View {
    let title: String
    let version: String
    let systemImage: String
    let state: PackageUpdateState

    private var accent: Color {
        switch state.step {
        case .failed: return .red
        case .done, .skipped: return .green
        case .downloading, .verifying, .installing: return .accentColor
        case .pending: return .secondary
        }
    }

    private var statusLabel: String {
        switch state.step {
        case .pending:
            return String(localized: "SDE_Status_Pending", defaultValue: "等待中")
        case .downloading:
            return String(localized: "SDE_Status_Downloading", defaultValue: "正在下载")
        case .verifying:
            return String(localized: "SDE_Status_Verifying", defaultValue: "正在校验")
        case .installing:
            return String(localized: "SDE_Status_Installing", defaultValue: "正在安装")
        case .done, .skipped:
            return String(localized: "SDE_Done", defaultValue: "完成")
        case .failed:
            return String(localized: "SDE_Update_Failed", defaultValue: "更新失败")
        }
    }

    private var percentageLabel: String? {
        switch state.step {
        case .downloading, .installing:
            return "\(Int((state.progress * 100).rounded()))%"
        default:
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            statusIcon

            VStack(alignment: .leading, spacing: 6) {
                Text("\(title) \(version)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(accent)

                    if let percentage = percentageLabel {
                        Text(percentage)
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(accent)
                            .contentTransition(.numericText())
                    }
                }

                if state.step.isActive {
                    ProgressView(value: min(max(state.progress, 0), 1))
                        .tint(accent)
                        .animation(.linear(duration: 0.12), value: state.progress)
                }

                if state.step == .failed, let message = state.errorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: state.step)
    }

    @ViewBuilder
    private var statusIcon: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        switch state.step {
        case .done, .skipped:
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.green, in: shape)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .failed:
            Image(systemName: "xmark")
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.red, in: shape)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .downloading, .verifying, .installing:
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.12), in: shape)
        case .pending:
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: shape)
        }
    }
}

// MARK: - SDE 更新详情视图

struct SDEUpdateDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var updateChecker = SDEUpdateChecker.shared
    @StateObject private var updateManager = SDEUpdateManager.shared

    private var sdeUpToDate: Bool {
        updateChecker.currentSDEVersion == updateChecker.latestSDEVersion
    }

    private var iconsUpToDate: Bool {
        updateChecker.currentIconVersion == updateChecker.latestIconVersion
    }

    var body: some View {
        if updateManager.isDownloading {
            DownloadProgressView(
                iconsState: updateManager.iconsState,
                sdeState: updateManager.sdeState,
                iconsVersion: "v\(updateChecker.latestIconVersion)",
                sdeVersion: updateChecker.latestSDEVersion,
                hasError: updateManager.hasError,
                isCompleted: updateManager.isCompleted,
                onExit: {
                    updateManager.reset()
                    dismiss()
                }
            )
        } else {
            NavigationStack {
                List {
                    Section {
                        HStack {
                            Text(NSLocalizedString("SDE_Current_Version", comment: "当前版本"))
                            Spacer()
                            Text(updateChecker.currentSDEVersion)
                                .fontWeight(.medium)
                                .foregroundStyle(sdeUpToDate ? Color.green : Color.orange)
                        }
                        HStack {
                            Text(NSLocalizedString("SDE_Latest_Version", comment: "最新版本"))
                            Spacer()
                            Text(updateChecker.latestSDEVersion)
                                .fontWeight(.medium)
                                .foregroundStyle(sdeUpToDate ? Color.green : Color.secondary)
                        }
                    } header: {
                        Text(NSLocalizedString("SDE_Data_Package", comment: "SDE数据包"))
                    }

                    Section {
                        HStack {
                            Text(NSLocalizedString("SDE_Current_Version", comment: "当前版本"))
                            Spacer()
                            Text("v\(updateChecker.currentIconVersion)")
                                .fontWeight(.medium)
                                .foregroundStyle(iconsUpToDate ? Color.green : Color.orange)
                        }
                        HStack {
                            Text(NSLocalizedString("SDE_Latest_Version", comment: "最新版本"))
                            Spacer()
                            Text("v\(updateChecker.latestIconVersion)")
                                .fontWeight(.medium)
                                .foregroundStyle(iconsUpToDate ? Color.green : Color.secondary)
                        }
                    } header: {
                        Text(NSLocalizedString("SDE_Icon_Package", comment: "图标包"))
                    }

                    Section {
                        VStack(spacing: 12) {
                            if sdeUpToDate && iconsUpToDate {
                                Button {
                                    dismiss()
                                } label: {
                                    Text(NSLocalizedString("SDE_Done", comment: ""))
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    updateManager.startUpdate()
                                } label: {
                                    Text(NSLocalizedString("SDE_Update", comment: "更新"))
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    dismiss()
                                } label: {
                                    Text(NSLocalizedString("SDE_Exit", comment: "退出"))
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle(NSLocalizedString("SDE_Update_Details", comment: "SDE更新详情"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - Token Scopes 列表视图

struct TokenScopesListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var characters: [CharacterAuth] = []
    @State private var characterPortraits: [Int: UIImage] = [:]
    @State private var isLoading = true
    @State private var selectedCharacter: CharacterAuth?
    @State private var showingDetailView = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if characters.isEmpty {
                    ContentUnavailableView {
                        Label(
                            NSLocalizedString("Misc_No_Data", comment: "无数据"),
                            systemImage: "person.slash"
                        )
                    }
                } else {
                    List {
                        ForEach(characters, id: \.character.CharacterID) { characterAuth in
                            Button {
                                selectedCharacter = characterAuth
                                showingDetailView = true
                            } label: {
                                HStack(spacing: 12) {
                                    // 人物头像
                                    if let portrait = characterPortraits[characterAuth.character.CharacterID] {
                                        Image(uiImage: portrait)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                            )
                                    }

                                    // 人物名称
                                    Text(characterAuth.character.CharacterName)
                                        .font(.system(size: 16))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Setting_View_Token_Scopes", comment: "查看 Token scopes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadCharacters()
            }
            .navigationDestination(isPresented: $showingDetailView) {
                if let character = selectedCharacter {
                    TokenScopesDetailView(character: character)
                }
            }
        }
    }

    private func loadCharacters() async {
        isLoading = true

        // 获取所有已保存的人物
        let allCharacters = EVELogin.shared.loadCharacters()
        await MainActor.run {
            characters = allCharacters
        }

        // 加载所有人物头像
        for characterAuth in allCharacters {
            let characterId = characterAuth.character.CharacterID
            do {
                let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: characterId,
                    catchImage: false
                )
                await MainActor.run {
                    characterPortraits[characterId] = portrait
                }
            } catch {
                Logger.error("加载人物头像失败 (ID: \(characterId)): \(error)")
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - Token Scopes 详情视图

struct TokenScopesDetailView: View {
    let character: CharacterAuth
    @State private var scopes: [String] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText: String = ""

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = error {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(error)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                }
            } else if scopes.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Misc_No_Data", comment: "无数据"))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else {
                Section {
                    ForEach(scopes.filter { searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText) }, id: \.self) { scope in
                        Text(scope)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } header: {
                    Text(String(format: NSLocalizedString("Token_Scopes_Count", comment: "共 %d 个权限"), scopes.count))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(character.character.CharacterName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: NSLocalizedString("Token_Scopes_Search_Placeholder", comment: "搜索权限..."))
        .task {
            await loadScopes()
        }
    }

    private func loadScopes() async {
        isLoading = true
        error = nil

        do {
            // 方法1: 尝试从 JWT token 中解析 scopes
            if let accessToken = try? await AuthTokenManager.shared.getAccessToken(for: character.character.CharacterID) {
                if let characterInfo = JWTTokenValidator.shared.parseToken(accessToken) {
                    let scopesString = characterInfo.Scopes
                    let scopesArray = scopesString.components(separatedBy: " ").filter { !$0.isEmpty }
                    await MainActor.run {
                        self.scopes = scopesArray.sorted()
                        self.isLoading = false
                    }
                    return
                }
            }

            // 方法2: 从保存的 character 信息中获取 scopes
            let scopesString = character.character.Scopes
            if !scopesString.isEmpty {
                let scopesArray = scopesString.components(separatedBy: " ").filter { !$0.isEmpty }
                await MainActor.run {
                    self.scopes = scopesArray.sorted()
                    self.isLoading = false
                }
                return
            }

            // 如果都没有，显示错误
            await MainActor.run {
                self.error = NSLocalizedString("Token_Scopes_Not_Found", comment: "未找到 token scopes")
                self.isLoading = false
            }
        }
    }
}

// MARK: - Token 查看视图

struct TokenViewerView: View {
    @State private var characters: [CharacterAuth] = []
    @State private var characterPortraits: [Int: UIImage] = [:]
    @State private var refreshTokens: [Int: String] = [:]
    @State private var accessTokens: [Int: String] = [:]
    @State private var isLoading = true
    @State private var forceExpireCharacterId: Int?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if characters.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "person.slash"
                    )
                }
            } else {
                List {
                    ForEach(characters, id: \.character.CharacterID) { characterAuth in
                        let characterId = characterAuth.character.CharacterID
                        TokenViewerRow(
                            characterAuth: characterAuth,
                            portrait: characterPortraits[characterId],
                            refreshToken: refreshTokens[characterId],
                            accessToken: accessTokens[characterId],
                            onForceExpire: { forceExpireCharacterId = characterId }
                        )
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_View_Token", comment: "查看 Token"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .alert(
            NSLocalizedString("Token_Viewer_Force_Expire", comment: "强制过期"),
            isPresented: .init(
                get: { forceExpireCharacterId != nil },
                set: { if !$0 { forceExpireCharacterId = nil } }
            )
        ) {
            Button(NSLocalizedString("Common_Cancel", comment: "取消"), role: .cancel) {
                forceExpireCharacterId = nil
            }
            Button(NSLocalizedString("Token_Viewer_Force_Expire", comment: "强制过期"), role: .destructive) {
                if let characterId = forceExpireCharacterId {
                    Task { await forceExpire(characterId: characterId) }
                }
                forceExpireCharacterId = nil
            }
        } message: {
            Text(NSLocalizedString("Token_Viewer_Force_Expire_Confirm", comment: ""))
        }
    }

    private func loadData() async {
        isLoading = true
        let allCharacters = EVELogin.shared.loadCharacters()
        await MainActor.run { characters = allCharacters }

        for characterAuth in allCharacters {
            let characterId = characterAuth.character.CharacterID
            // 加载头像
            do {
                let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: characterId,
                    catchImage: false
                )
                await MainActor.run { characterPortraits[characterId] = portrait }
            } catch {
                Logger.error("加载人物头像失败 (ID: \(characterId)): \(error)")
            }
            // 读取 refresh token（Keychain）
            let refreshToken = try? SecureStorage.shared.loadToken(for: characterId)
            // 读取 access token（内存缓存，不触发刷新）
            let accessToken = await AuthTokenManager.shared.getCachedAccessToken(for: characterId)
            await MainActor.run {
                if let rt = refreshToken { refreshTokens[characterId] = rt }
                if let at = accessToken { accessTokens[characterId] = at }
            }
        }

        await MainActor.run { isLoading = false }
    }

    private func forceExpire(characterId: Int) async {
        // 清除 access token（内存）和 refresh token（Keychain）
        await AuthTokenManager.shared.clearAllTokens(for: characterId)
        // 标记为过期（触发 CharacterDetailsUpdated 通知，UI 自动更新）
        EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(characterId: characterId, expired: true)
        // 刷新本地数据
        await MainActor.run {
            refreshTokens.removeValue(forKey: characterId)
            accessTokens.removeValue(forKey: characterId)
            if let index = characters.firstIndex(where: { $0.character.CharacterID == characterId }) {
                var updated = characters[index]
                updated.character.refreshTokenExpired = true
                characters[index] = updated
            }
        }
        Logger.info("已强制过期角色 \(characterId) 的 token")
    }
}

private struct TokenViewerRow: View {
    let characterAuth: CharacterAuth
    let portrait: UIImage?
    let refreshToken: String?
    let accessToken: String?
    let onForceExpire: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            if let portrait = portrait {
                Image(uiImage: portrait)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Image("default_char")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：人物名 + 过期标记
                HStack(spacing: 6) {
                    Text(characterAuth.character.CharacterName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    if characterAuth.character.refreshTokenExpired {
                        Text(NSLocalizedString("Token_Viewer_Expired_Tag", comment: "已过期"))
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                }

                // 第二行：refresh token
                tokenRow(label: "Refresh", token: refreshToken)

                // 第三行：access token
                tokenRow(label: "Access", token: accessToken)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                onForceExpire()
            } label: {
                Label(
                    NSLocalizedString("Token_Viewer_Force_Expire", comment: "强制过期"),
                    systemImage: "xmark.octagon"
                )
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onForceExpire()
            } label: {
                Label(
                    NSLocalizedString("Token_Viewer_Force_Expire", comment: "强制过期"),
                    systemImage: "xmark.octagon"
                )
            }
        }
    }

    private func tokenRow(label: String, token: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            Text(maskToken(token))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }

    /// 首位各 8 个字符，中间 8 个星号；token 过短则全遮罩
    private func maskToken(_ token: String?) -> String {
        guard let token = token, !token.isEmpty else {
            return NSLocalizedString("Token_Viewer_No_Token", comment: "无")
        }
        guard token.count > 16 else {
            return String(repeating: "*", count: token.count)
        }
        let prefix = token.prefix(8)
        let suffix = token.suffix(8)
        return "\(prefix)********\(suffix)"
    }
}
