import Foundation
import SafariServices
import SwiftUI
import WebKit

struct ContentView: View {
    enum HeaderFrame {}

    @StateObject var viewModel = MainViewModel()
    @ObservedObject var databaseManager: DatabaseManager
    @AppStorage("currentCharacterId") var currentCharacterId: Int = 0
    @AppStorage("showCorporationAffairs") var showCorporationAffairs: Bool = false
    @AppStorage("lastVersion") var lastVersion: String = ""

    // 功能自定义相关状态
    @AppStorage("hiddenFeatures") var hiddenFeaturesData: Data = .init()
    @AppStorage("pinnedFeatures") var pinnedFeaturesData: Data = .init()
    @State var isCustomizeMode: Bool = false
    @State var hiddenFeatures: Set<String> = []
    @State var pinnedFeatures: [String] = [] // 使用数组保持顺序
    @State var columnVisibility = NavigationSplitViewVisibility.all
    @State var selectedItem: String? = nil
    @State var showUpdateAlert = false
    @State var shouldNavigateToUpdateLog = false
    @State var isRefreshTokenExpired = false // 添加token过期状态
    @State var navigationAvatarItemVisible = false
    @State var hasInitialLayout = false // 添加初始布局标记
    @StateObject var sdeUpdateChecker = SDEUpdateChecker.shared // 观察SDE更新状态
    @State var showingSDEUpdateSheet = false // 控制SDE更新sheet显示

    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                ScrollViewReader { _ in
                    List(selection: $selectedItem) {
                        // 登录部分
                        loginSection
                            .framePreference(in: .global, HeaderFrame.self)

                        // 常用功能部分（置顶功能）
                        if !isCustomizeMode && hasVisiblePinnedFeatures {
                            pinnedFeaturesSection
                        }

                        // 角色功能部分
                        if currentCharacterId != 0 || isCustomizeMode {
                            characterSection

                            // 军团部分（仅在开启设置且已登录时显示）
                            if showCorporationAffairs || isCustomizeMode {
                                corporationSection
                            }
                        }

                        // 数据库部分(始终显示)
                        databaseSection

                        // 商业部分(登录后显示)
                        businessSection

                        // 战斗部分(登录后显示)
                        if currentCharacterId != 0 || isCustomizeMode {
                            KillBoardSection
                        }
                        // 装配部分(无需登录)
                        FittingSection
                        // 其他设置(始终显示)
                        otherSection
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        Logger.info("强制刷新基本数据")
                        await viewModel.refreshAllBasicData(forceRefresh: true)
                    }
                }
                .navigationTitle(NSLocalizedString("Main_Home", comment: ""))
                .task {
                    // 首次加载时刷新数据，在后台异步执行，不阻塞 UI
                    Logger.info("Sidebar appeared, refreshing data...")
                    // 立即更新 token 状态
                    updateTokenStatus()
                    // 不等待刷新完成，让数据在后台加载
                    Task {
                        await viewModel.refreshAllBasicData()
                    }
                }
                .toolbar {
                    toolbarContent
                }
                .navigationSplitViewColumnWidth(min: 300, ideal: geometry.size.width * 0.35)
                .onFrameChange(HeaderFrame.self) { frames in
                    // 确保初始布局完成后再开始检测滚动
                    if !hasInitialLayout {
                        hasInitialLayout = true
                        return
                    }

                    // 只有在初始布局完成后才更新头像可见性
                    let shouldShow = (frames.first?.minY ?? -100) < -35

                    // 使用动画来平滑切换状态
                    withAnimation(.easeInOut(duration: 0.25)) {
                        navigationAvatarItemVisible = shouldShow
                    }
                }
            } detail: {
                NavigationStack {
                    detailContent
                }
                .onChange(of: shouldNavigateToUpdateLog) { _, newValue in
                    if newValue {
                        selectedItem = FeatureID.updateHistory.rawValue
                        shouldNavigateToUpdateLog = false
                    }
                }
                // 访问功能日志：仅在选中项实际变化时记录一次，
                // 避免 GeometryReader 每帧重评估 body 导致的日志刷屏
                .onChange(of: selectedItem) { _, newValue in
                    guard let newValue else { return }
                    logSelectedItem(newValue)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // 检查当前选择的角色是否在已登录列表中
            Logger.debug("Check current character: \(currentCharacterId)")
            if currentCharacterId != 0 {
                let auth = EVELogin.shared.getCharacterByID(currentCharacterId)
                if auth == nil {
                    // 如果找不到认证信息，说明角色已退出
                    currentCharacterId = 0
                    viewModel.resetCharacterInfo()
                    // 清除技能数据
                    Task {
                        SharedSkillsManager.shared.clearSkillData()
                    }
                }
            }

            // 加载隐藏功能列表
            loadHiddenFeatures()

            // 加载置顶功能列表
            loadPinnedFeatures()

            // 检查应用版本更新
            checkAppVersionUpdate()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))
        ) { _ in
            // 语言变更时的处理
            // 需要等待刷新完成，以确保界面文字立即更新，保持视觉一致性
            Logger.info("语言变更，刷新数据")
            Task {
                await viewModel.refreshAllBasicData()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("CharacterLoggedOut"))
        ) { _ in
            // 收到角色登出通知时执行登出操作
            currentCharacterId = 0
            viewModel.resetCharacterInfo()
            selectedItem = nil
            // 清除技能数据
            Task {
                SharedSkillsManager.shared.clearSkillData()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            // App 从后台返回前台时刷新数据
            Logger.info("App entering foreground, refreshing data...")

            // 立即更新 token 状态
            updateTokenStatus()

            // 不等待刷新完成，让它在后台异步执行，避免阻塞 UI
            Task {
                await viewModel.refreshAllBasicData()
            }
        }
        .onChange(of: viewModel.selectedCharacter) { _, _ in
            // 当选中的角色变化时，更新token状态
            updateTokenStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("CharacterDetailsUpdated")
            )
        ) { notification in
            // 后台 API 调用触发 token 过期/恢复时，实时更新主界面图标
            if let character = notification.userInfo?["character"] as? EVECharacterInfo,
               character.CharacterID == viewModel.selectedCharacter?.CharacterID
            {
                isRefreshTokenExpired = character.refreshTokenExpired
            }
        }
        .alert(
            NSLocalizedString("App_Updated_Title", comment: "App已更新"), isPresented: $showUpdateAlert
        ) {
            Button(NSLocalizedString("App_Updated_OK", comment: "好的"), role: .cancel) {
                // 只关闭弹窗
            }
            Button(NSLocalizedString("App_Updated_View_Changes", comment: "查看更新")) {
                shouldNavigateToUpdateLog = true
            }
        } message: {
            Text(NSLocalizedString("App_Updated_Message", comment: "应用已更新到新版本"))
        }
        .sheet(isPresented: $showingSDEUpdateSheet, onDismiss: {
            // 更新完成后重新检查更新状态
            Task { @MainActor in
                await SDEUpdateChecker.shared.checkForUpdates()
            }
        }) {
            SDEInformationView()
        }
    }

    @ViewBuilder
    var detailContent: some View {
        if selectedItem == nil {
            Text(NSLocalizedString("Select_Item", comment: ""))
                .foregroundColor(.gray)
        } else if selectedItem == "accounts" {
            AccountsView(
                databaseManager: databaseManager,
                mainViewModel: viewModel,
                selectedItem: $selectedItem
            ) { character, portrait in
                viewModel.resetCharacterInfo()
                viewModel.selectedCharacter = character
                viewModel.characterPortrait = portrait
                currentCharacterId = character.CharacterID
                Task {
                    SharedSkillsManager.shared.clearSkillData()
                    await viewModel.refreshAllBasicData()
                }
            }
        } else if let featureID = selectedItem.flatMap(FeatureID.init(rawValue:)) {
            featureID.destination(
                databaseManager: databaseManager,
                viewModel: viewModel,
                currentCharacterId: currentCharacterId
            )
        } else {
            Text(NSLocalizedString("Select_Item", comment: ""))
                .foregroundColor(.gray)
        }
    }

    func logSelectedItem(_ item: String?) {
        guard let item = item else { return }
        Logger.info("=== 用户访问功能: \(item) ===")
    }

    func updateTokenStatus() {
        if let character = viewModel.selectedCharacter {
            if let auth = EVELogin.shared.getCharacterByID(character.CharacterID) {
                isRefreshTokenExpired = auth.character.refreshTokenExpired
            } else {
                isRefreshTokenExpired = false
            }
        } else {
            isRefreshTokenExpired = false
        }
    }

    func checkAppVersionUpdate() {
        let currentVersion = AppConfiguration.Version.fullVersion

        // 如果lastVersion为空，说明是首次安装，记录版本号但不显示更新提示
        if lastVersion.isEmpty {
            lastVersion = currentVersion
            Logger.info("首次安装应用，记录当前版本: \(currentVersion)")
        }
        // 如果版本不同，显示更新提示
        else if lastVersion != currentVersion {
            Logger.info("检测到应用版本更新: \(lastVersion) -> \(currentVersion)")
            showUpdateAlert = true
            // 立即更新存储的版本号，确保提示只显示一次
            lastVersion = currentVersion
        }
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        // 在导航栏左侧显示人物头像（仅当滚动且已登录时）
        ToolbarItem(placement: .navigationBarLeading) {
            if currentCharacterId != 0, viewModel.selectedCharacter != nil,
               navigationAvatarItemVisible
            {
                Button(action: {
                    // 跳转到人物选择页面
                    selectedItem = "accounts"
                }) {
                    NavigationBarAvatarView(
                        characterPortrait: viewModel.characterPortrait,
                        isRefreshTokenExpired: isRefreshTokenExpired,
                        isRefreshing: viewModel.isRefreshing
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)),
                        removal: .opacity.combined(with: .scale(scale: 0.8))
                    )
                )
            }
        }

        // 右侧工具栏按钮组（登出按钮或退出自定义模式按钮）
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // 登出按钮或退出自定义模式按钮
            if isCustomizeMode {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isCustomizeMode = false
                    }
                }) {
                    Text(NSLocalizedString("Features_Exit_Customize", comment: ""))
                        .foregroundColor(.blue)
                }
            } else if currentCharacterId != 0 {
                logoutButton
            }
        }
    }

    var logoutButton: some View {
        Button {
            currentCharacterId = 0
            viewModel.resetCharacterInfo()
            // 清除技能数据
            Task {
                SharedSkillsManager.shared.clearSkillData()
            }
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .resizable()
                .frame(width: 28, height: 24)
                .foregroundColor(.red)
        }
    }
}
