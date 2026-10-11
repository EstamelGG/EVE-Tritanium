import Foundation
import SwiftUI
import UserNotifications

@main
struct EVE_NexusApp: App {
    @AppStorage("selectedLanguage") private var selectedLanguage: String?
    @AppStorage("selectedDatabaseLanguage") private var selectedDatabaseLanguage: String?
    @AppStorage("selectedTimeZone") private var selectedTimeZone = "local"
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @StateObject private var databaseManager = DatabaseManager()
    @StateObject private var rateLimitAlertManager = RateLimitAlertManager.shared
    @State private var isInitialized = false
    /// 开屏加载状态
    @State private var startupStage: StartupStage = .checking
    @State private var startupProgress: Double?
    @State private var startupDetailText: String?
    @State private var hasStartedLoading = false

    private func getLanguageCode(_ language: String) -> String {
        return language.hasPrefix("zh-Hans") ? "zh-Hans" : "en"
    }

    init() {
        // Hosted unit tests prepare their own bundled data; avoid concurrent SDE loads,
        // OTA updates and account/network side effects while the test runner is active.
        if Self.isUnitTestHost {
            return
        }
        // 配置 Pulse 日志系统（必须在其他初始化之前）
        Logger.configure()

        // 隐藏 PulseUI 中的支持相关按钮，避免用户误以为是给应用开发者发送反馈
        UserDefaults.standard.set(true, forKey: "pulse-disable-support-prompts")
        UserDefaults.standard.set(true, forKey: "pulse-disable-report-issue-prompts")

        configureLanguage()
        setupNotifications()
        initializeLanguageMapSettings()
        Logger.info("App start at \(Date())")
        auditUserDefaultsStorage()

        // 初始化数据库
        _ = CharacterDatabaseManager.shared // 确保角色数据库被初始化

        // 加载本地化账单信息的文本数据
        LocalizationManager.shared.loadAccountingEntryTypes()
        validateRefreshTokens()
        scheduleBackgroundTasks()

        // 初始化内购管理器并加载商品数据
        Task { @MainActor in
            await PurchaseManager.shared.loadProducts()
        }
    }

    private func auditUserDefaultsStorage() {
        // 审计 UserDefaults 中的键值大小
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()

        // 使用 PropertyListSerialization 来获取实际的序列化大小
        var sizeMap: [(key: String, size: Int)] = []
        var totalSize = 0

        for (key, value) in dictionary {
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: value, format: .binary, options: 0
            ) {
                let size = data.count
                totalSize += size
                sizeMap.append((key: key, size: size))

                // 检查单个键值对是否过大（比如超过1MB）
                if size > 1_000_000 {
                    Logger.error(
                        "警告：键 '\(key)' 的数据大小(\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))过大"
                    )
                }
            }
        }

        // 检查总大小是否接近限制（4MB）
        if totalSize > 3_072_000 {
            Logger.warning(
                "警告：UserDefaults 总大小(\(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)))接近限制(4MB)"
            )
            // 按大小排序并只打印超过1MB的键
            sizeMap.sort { $0.size > $1.size }
            for item in sizeMap where item.size > 1_000_000 {
                Logger.info(
                    "键: \(item.key), 大小: \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))"
                )
            }
        } else {
            Logger.success(
                "UserDefaults 总大小: \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file))"
            )
        }
    }

    private func scheduleBackgroundTasks() {
        BackgroundTaskManager.shared.scheduleDataRefresh()
        BackgroundTaskManager.shared.scheduleAssetJsonRefresh()
        BackgroundTaskManager.shared.scheduleContractRefresh()
        BackgroundTaskManager.shared.scheduleStructureOrdersRefresh()
        BackgroundTaskManager.shared.scheduleIndustryRefresh()
        BackgroundTaskManager.shared.scheduleWalletRefresh()
    }

    private func setupNotifications() {
        // 设置通知代理
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        Logger.info("通知代理设置完成")
    }

    private func configureLanguage() {
        // 只在首次启动或语言未设置时配置
        if selectedLanguage == nil {
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            let languageCode = getLanguageCode(systemLanguage)
            selectedLanguage = languageCode
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logger.debug("首次启动，设置为系统语言: \(systemLanguage) -> \(languageCode)")
        } else {
            // 使用已保存的语言设置
            UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logger.debug("使用已保存的语言设置: \(String(describing: selectedLanguage))")
        }

        // 配置数据库语言，如果未设置则与应用语言保持一致
        if selectedDatabaseLanguage == nil {
            selectedDatabaseLanguage = selectedLanguage
            Logger.debug("首次启动，设置数据库语言与应用语言一致: \(String(describing: selectedDatabaseLanguage))")
        } else {
            Logger.debug("使用已保存的数据库语言设置: \(String(describing: selectedDatabaseLanguage))")
        }

        // 激活自定义 Bundle 以支持运行时语言切换及回退英文
        let langToUse = selectedLanguage ?? "en"
        if Bundle.main.path(forResource: langToUse, ofType: "lproj") != nil {
            Bundle.setLanguage(langToUse)
        }
    }

    private func initializeLanguageMapSettings() {
        // 检查是否已经设置过语言映射配置
        if UserDefaults.standard.object(forKey: LanguageMapConstants.languageMapDefaultsKey) == nil {
            // 首次使用，设置默认语言映射配置
            UserDefaults.standard.set(
                LanguageMapConstants.languageMapDefaultLanguages,
                forKey: LanguageMapConstants.languageMapDefaultsKey
            )
            Logger.info("首次使用，初始化语言映射配置为默认值: \(LanguageMapConstants.languageMapDefaultLanguages)")
        } else {
            Logger.debug("语言映射配置已存在，跳过初始化")
        }
    }

    private func validateRefreshTokens() {
        // 获取所有有效的 token
        let characterIdsWithValidRefreshToken = SecureStorage.shared.listValidRefreshTokens()
        Logger.info("App初始化: 找到 \(characterIdsWithValidRefreshToken.count) 个不为空的 refresh token")

        // 获取当前保存的所有角色
        let characters = EVELogin.shared.loadCharacters()
        let characterIds = characters.map { $0.character.CharacterID }
        Logger.info("App初始化: UserDefaults 中保存了 \(characters.count) 个角色，ID列表: \(characterIds)")

        // 清理不存在于角色列表中的 token（孤儿 token）
        let validCharacterIds = Set(characterIds)
        for tokenCharacterId in characterIdsWithValidRefreshToken {
            if !validCharacterIds.contains(tokenCharacterId) {
                Logger.warning("App初始化: 发现孤儿 token (角色ID: \(tokenCharacterId))，该角色已不在登录列表，正在清理...")
                Task {
                    await AuthTokenManager.shared.clearAllTokens(for: tokenCharacterId)
                }
            }
        }

        // 打印详细信息
        for character in characters {
            let characterId = character.character.CharacterID
            let hasValidRefreshToken = characterIdsWithValidRefreshToken.contains(characterId)
            Logger.info(
                "App初始化: 角色 \(character.character.CharacterName) (\(characterId)) - \(hasValidRefreshToken ? "有 refresh token" : "无 refresh token")"
            )

            // 如果没有有效的 token，标记为过期
            if !hasValidRefreshToken {
                Logger.info(
                    "App初始化: 标记角色token过期 - \(character.character.CharacterName) (\(characterId))"
                )
                let characterToUpdate = character.character
                Task {
                    var updatedCharacter = characterToUpdate
                    updatedCharacter.refreshTokenExpired = true
                    try? await EVELogin.shared.saveCharacterInfo(updatedCharacter)
                }
            }
        }
    }

    private func checkAndPrepareStaticResources() async {
        let downloader = SDEDownloader()
        await MainActor.run {
            startupStage = .checking
            startupProgress = nil
            startupDetailText = nil
        }
        let needFullSeed = StaticResourceManager.shared.needsSeedSDEExtraction()
        let needIconsOnly = !needFullSeed && shouldExtractIcons()
        Logger.info("[SDE初始化] 校验结果: needFullSeed=\(needFullSeed), needIconsOnly=\(needIconsOnly)")

        if !needFullSeed, !needIconsOnly {
            Logger.info("SDE / icons 已就绪，跳过解压")
            LocalSDELayout.purgeLegacyInstallArtifacts()
            await initializeApp()
            return
        }

        // 明确日志：说明触发原因和即将释放的资源
        if needFullSeed {
            Logger.info("触发 SDE 完整重播（首装 / 损坏 / Bundle 种子更新），将释放 sde.zip + icons.zip")
        } else if needIconsOnly {
            Logger.info("触发图标更新，将释放 icons.zip")
        }
        await MainActor.run {
            startupStage = .extracting
            startupProgress = 0
        }

        do {
            if needFullSeed {
                Logger.info("开始从 Bundle 播种 SDE（sde.zip + icons.zip）")
                try await downloader.seedFromBundle { progress in
                    updateUnzipProgress(progress)
                }
                Logger.info("Bundle SDE 播种完成")
            } else if needIconsOnly {
                Logger.info("开始从 Bundle 解压 icons.zip")
                try await downloader.extractBundledIcons { progress in
                    updateUnzipProgress(progress)
                }
                Logger.info("Bundle icons 解压完成")
                if let bundleMetadata = MetadataManager.shared.readMetadataFromBundle() {
                    try MetadataManager.shared.saveLocalMetadata(bundleMetadata)
                }
                LocalSDELayout.purgeLegacyInstallArtifacts()
            }

            // 与"重置 SDE"流程保持一致的收尾：清空可能残留的内存/查询缓存，
            // 确保首次解压后使用的内存状态是干净的（首次安装时这些缓存为空，无副作用）
            await MainActor.run {
                IconManager.shared.clearCache()
                DatabaseManager.shared.clearCache()
            }
            await initializeApp()
        } catch {
            Logger.error("静态资源解压失败: \(error)")
            IconManager.shared.isExtractionComplete = false
            await initializeApp()
        }
    }

    private func updateUnzipProgress(_ progress: Double) {
        Task { @MainActor in
            if case .extracting = startupStage {
                startupProgress = progress
            }
        }
    }

    /// 检查是否需要用 Bundle 内置图标覆盖本地图标（不重装整库时）
    private func shouldExtractIcons() -> Bool {
        let destinationPath = LocalSDELayout.iconsDirectory
        let iconsExist = FileManager.default.fileExists(atPath: destinationPath.path)
        let iconContents = (try? FileManager.default.contentsOfDirectory(atPath: destinationPath.path)) ?? []
        let hasContents = !iconContents.isEmpty

        var checkLog = SDECheckLog(title: "[图标初始化] 版本检查")
        checkLog.append(
            "本地状态: path=\(destinationPath.path), exists=\(iconsExist), count=\(iconContents.count), extractionComplete=\(IconManager.shared.isExtractionComplete)"
        )

        guard iconsExist, hasContents, IconManager.shared.isExtractionComplete else {
            checkLog.append("结果: 图标目录缺失、为空或标记未完成，需要解压")
            checkLog.emit()
            return true
        }

        guard let bundleMetadata = MetadataManager.shared.readMetadataFromBundle() else {
            checkLog.append("结果: 无法读取 Bundle metadata，保留本地图标")
            checkLog.emit(isWarning: true)
            return false
        }
        checkLog.append("Bundle metadata: \(bundleMetadata.debugSummary)")

        guard let localMetadata = MetadataManager.shared.readLocalMetadata() else {
            checkLog.append("结果: 本地 metadata 不存在，需要刷新 icons/metadata")
            checkLog.emit()
            return true
        }
        checkLog.append("本地 metadata: \(localMetadata.debugSummary)")

        let comparison = compareBundleIconsWithLocal(
            bundle: bundleMetadata, local: localMetadata
        )
        checkLog.append("比较结果: \(comparison.reason)")
        checkLog.append("最终结果: needExtraction=\(comparison.needExtraction)")
        checkLog.emit()
        return comparison.needExtraction
    }

    /// Bundle 是否比本地图标更新（逻辑对齐 SDE：优先 build/patch，再比 icon_version）
    private func compareBundleIconsWithLocal(bundle: CloudKitMetadata, local: CloudKitMetadata)
        -> (needExtraction: Bool, reason: String)
    {
        if bundle.buildNumber != local.buildNumber {
            let result = bundle.buildNumber > local.buildNumber
            return (result, "build 不同: Bundle=\(bundle.buildNumber), Local=\(local.buildNumber)")
        }
        if bundle.patchNumber != local.patchNumber {
            let result = bundle.patchNumber > local.patchNumber
            return (result, "patch 不同: Bundle=\(bundle.patchNumber), Local=\(local.patchNumber)")
        }
        if bundle.iconVersion != local.iconVersion {
            let result = bundle.iconVersion > local.iconVersion
            return (result, "icon_version 不同: Bundle=\(bundle.iconVersion), Local=\(local.iconVersion)")
        }
        if bundle.iconSha256.isEmpty {
            return (false, "Bundle 缺少 icon_sha256，跳过 SHA256 比较")
        }
        if bundle.iconSha256 != local.iconSha256 {
            return (
                true,
                "icon_sha256 不同: Bundle=\(bundle.iconSha256Short), Local=\(local.iconSha256Short)"
            )
        }
        return (false, "build、patch、icon_version 和 icon_sha256 均一致")
    }

    private func initializeApp() async {
        // 在图标解压完成后加载主权数据
        // _ = try await SovereigntyDataAPI.shared.fetchSovereigntyData()

        // 异步加载保险价格数据，不阻塞主进程
        Task.detached(priority: .background) {
            do {
                _ = try await InsurancePricesAPI.shared.fetchInsurancePrices()
            } catch {
                Logger.error("后台加载保险价格数据失败: \(error)")
            }
        }

        // 异步加载可用模型列表，不阻塞主进程
        Task.detached(priority: .background) {
            do {
                _ = try await AvailableModelsAPI.shared.fetchAvailableModels()
            } catch {
                Logger.error("后台加载可用模型列表失败: \(error)")
            }
        }

        // 后台预加载 GitHub 市场价格数据，成功后整个会话期间使用
        Task.detached(priority: .background) {
            await GitHubMarketPriceAPI.shared.preloadData()
        }

        // 阶段4：三步并行加载（不在 MainActor，真正并行）
        let clock = ContinuousClock()
        let stageStart = clock.now
        func ms(_ d: Duration) -> Int64 {
            let (s, a) = d.components
            return s * 1000 + a / 1_000_000_000_000_000
        }

        await MainActor.run {
            startupStage = .loadingDB
            startupProgress = 0
            startupDetailText = nil
        }

        let dbManager = databaseManager
        async let mainDBDuration: Duration = Task.detached(priority: .userInitiated) { () -> Duration in
            let duration = ContinuousClock().measure {
                dbManager.loadDatabase { completed, total in
                    Task { @MainActor in
                        startupProgress = Double(completed) / Double(total)
                        startupDetailText = "\(completed)/\(total)"
                    }
                }
            }

            // 依赖主库的初始化（原在主线程执行，是首帧前卡顿主因；两者均为纯内存构建，可安全后台执行）
            await MainActor.run {
                startupStage = .initializing
                startupProgress = nil
                startupDetailText = nil
            }
            SkillTreeManager.shared.initialize(databaseManager: dbManager)
            Logger.info("技能树初始化完成")
            PIResourceCache.shared.preloadResourceInfo()
            Logger.info("行星资源缓存初始化完成")

            return duration
        }.value
        async let itemTextDuration: Duration = Task.detached(priority: .userInitiated) { () -> Duration in
            ContinuousClock().measure { ItemTextStore.shared.syncWithActiveSDE() }
        }.value
        async let charDBDuration: Duration = Task.detached(priority: .userInitiated) { () -> Duration in
            ContinuousClock().measure { CharacterDatabaseManager.shared.loadDatabase() }
        }.value

        let mainDBMs = ms(await mainDBDuration)
        Logger.info("主数据库加载完成 (\(mainDBMs)ms)")

        let itemTextMs = ms(await itemTextDuration)
        Logger.info("物品文本同步完成 (\(itemTextMs)ms)")

        let charDBMs = ms(await charDBDuration)
        Logger.info("角色数据库加载完成 (\(charDBMs)ms)")

        let totalMs = ms(stageStart.duration(to: clock.now))
        Logger.info("数据库阶段加载完成: 总耗时 \(totalMs)ms (主库 \(mainDBMs)ms / 文本 \(itemTextMs)ms / 角色库 \(charDBMs)ms)")

        await MainActor.run {
            // 清理钱包旧数据（在后台线程执行，不阻塞初始化）
            Task.detached(priority: .background) {
                let journalDeleted = WalletJournalAPI.shared.cleanupOldData()
                let transactionsDeleted = WalletTransactionsAPI.shared.cleanupOldData()
                if journalDeleted > 0 || transactionsDeleted > 0 {
                    Logger.info("钱包数据清理完成 - 流水: \(journalDeleted)条, 交易: \(transactionsDeleted)条")
                }
            }

            isInitialized = true
        }

        // 在数据库加载完成后检查SDE更新
        Task { @MainActor in
            await SDEUpdateChecker.shared.checkForUpdates()
        }
    }

    /// 主题映射：selectedTheme(system/light/dark) → ColorScheme；nil 表示跟随系统。
    /// 收敛于此并挂在根视图上，开屏页（含 ContentView 挂载之前）与主界面首帧即获得正确主题
    private var preferredColorScheme: ColorScheme? {
        switch selectedTheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if Self.isUnitTestHost {
                    Color.clear
                } else if isInitialized {
                    ContentView(databaseManager: databaseManager)
                        .transition(.opacity)
                } else {
                    StartupSplashView(
                        stage: startupStage,
                        progress: startupProgress,
                        detailText: startupDetailText
                    )
                    .transition(.opacity)
                    .onAppear {
                        guard !hasStartedLoading else { return }
                        hasStartedLoading = true
                        Task {
                            await checkAndPrepareStaticResources()
                        }
                    }
                }
            }
            // 初始化完成后开屏与主界面交叉淡入淡出
            .animation(.easeInOut(duration: 0.5), value: isInitialized)
            // 主题统一在根视图生效，开屏页与主界面共享同一份映射（@AppStorage 变化即时刷新）
            .preferredColorScheme(preferredColorScheme)
            .environment(\.locale, Locale(identifier: selectedLanguage ?? "en"))
            .environment(\.timeZone, FormatUtil.displayTimeZone(for: selectedTimeZone))
            .environment(\.calendar, FormatUtil.appCalendar)
            .alert(NSLocalizedString("RateLimit_Alert_Title", comment: ""), isPresented: $rateLimitAlertManager.shouldShowRateLimitAlert) {
                Button(NSLocalizedString("RateLimit_Alert_OK", comment: "")) {}
            } message: {
                Text(NSLocalizedString("RateLimit_Alert_Message", comment: ""))
            }
        }
    }

    private static var isUnitTestHost: Bool {
        #if DEBUG
            NSClassFromString("XCTestCase") != nil
        #else
            false
        #endif
    }
}
