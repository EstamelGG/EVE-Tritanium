import SafariServices
import SwiftUI
import WebKit

/// 带有组织徽章的角色头像组件
struct CharacterAvatarWithBadges: View {
    let character: EVECharacterInfo
    let portrait: UIImage?
    let isRefreshing: Bool
    let refreshTokenhasExpired: Bool
    @State private var factionIcon: UIImage?
    @State private var corporationIcon: UIImage?
    @State private var allianceIcon: UIImage?

    private let avatarSize: CGFloat = 64
    private let badgeSize: CGFloat = 20

    var body: some View {
        ZStack {
            // 主要头像
            portraitImage
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())

            // 刷新或过期状态覆盖层
            if isRefreshing {
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: avatarSize, height: avatarSize)

                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
            } else if refreshTokenhasExpired {
                TokenExpiredOverlay()
            }
        }
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 3)
        )
        .background(
            Circle()
                .fill(Color.primary.opacity(0.05))
        )
        .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
        .padding(4)
        .overlay(
            // 组织图标作为overlay，显示在最上层
            ZStack {
                organizationBadge(
                    factionIcon,
                    x: -avatarSize / 2 + badgeSize / 2,
                    y: -avatarSize / 2 + badgeSize / 2
                )
                organizationBadge(
                    corporationIcon,
                    x: -avatarSize / 2 + badgeSize / 2,
                    y: avatarSize / 2 - badgeSize / 2
                )
                organizationBadge(
                    allianceIcon,
                    x: avatarSize / 2 - badgeSize / 2,
                    y: avatarSize / 2 - badgeSize / 2
                )
            }
        )
        .onAppear {
            loadOrganizationIcons()
        }
        .onChange(of: character.CharacterID) { _, _ in
            loadOrganizationIcons()
        }
    }

    /// 主要头像（有缓存用缓存，否则用默认占位图）
    private var portraitImage: Image {
        if let portrait = portrait {
            Image(uiImage: portrait)
        } else {
            Image("default_char")
        }
    }

    /// 组织图标徽章（势力 / 军团 / 联盟共用）
    @ViewBuilder
    private func organizationBadge(_ icon: UIImage?, x: CGFloat, y: CGFloat) -> some View {
        if let icon = icon {
            Image(uiImage: icon)
                .resizable()
                .frame(width: badgeSize, height: badgeSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.8), lineWidth: 1))
                .background(Circle().fill(Color(UIColor.systemBackground)))
                .offset(x: x, y: y)
        }
    }

    private func loadOrganizationIcons() {
        // 加载势力图标
        if let factionId = character.factionId,
           let iconName = SDEMemoryStore.faction(for: factionId)?.iconName
        {
            Task {
                let icon = IconManager.shared.loadUIImage(for: iconName)
                await MainActor.run {
                    self.factionIcon = icon
                }
            }
        }

        // 加载军团图标
        if let corporationId = character.corporationId {
            Task {
                do {
                    let icon = try await CorporationAPI.shared.fetchCorporationLogo(
                        corporationId: corporationId, size: 64
                    )
                    await MainActor.run {
                        self.corporationIcon = icon
                    }
                } catch {
                    Logger.error("加载军团图标失败: \(error)")
                }
            }
        }

        // 加载联盟图标
        if let allianceId = character.allianceId {
            Task {
                do {
                    let icon = try await AllianceAPI.shared.fetchAllianceLogo(
                        allianceID: allianceId, size: 64
                    )
                    await MainActor.run {
                        self.allianceIcon = icon
                    }
                } catch {
                    Logger.error("加载联盟图标失败: \(error)")
                }
            }
        }
    }
}

struct AccountsView: View {
    @StateObject private var viewModel: EVELoginViewModel
    let mainViewModel: MainViewModel
    @State private var isEditing = false
    @State private var characterToRemove: EVECharacterInfo? = nil
    @State private var forceUpdate: Bool = false
    @State private var isRefreshing = false
    @State private var refreshingCharacters: Set<Int> = []
    @State private var refreshingTotal = 0
    @State private var expiredTokenCharacters: Set<Int> = []
    @State private var isLoggingIn = false
    @State private var isRefreshingScopes = false
    @Binding var selectedItem: String?
    @State private var successMessage: String = ""
    @State private var showingSuccess: Bool = false
    @State private var showingSteamLoginSheet: Bool = false

    /// 添加角色选择回调
    var onCharacterSelect: ((EVECharacterInfo, UIImage?) -> Void)?

    init(
        databaseManager: DatabaseManager = DatabaseManager(),
        mainViewModel: MainViewModel,
        selectedItem: Binding<String?>,
        onCharacterSelect: ((EVECharacterInfo, UIImage?) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: EVELoginViewModel(databaseManager: databaseManager))
        self.mainViewModel = mainViewModel
        _selectedItem = selectedItem
        self.onCharacterSelect = onCharacterSelect
    }

    var body: some View {
        List {
            // 添加新角色按钮
            Section {
                Button(action: {
                    Task { @MainActor in
                        // 设置登录状态为true
                        isLoggingIn = true

                        // 检查并更新scopes（如果需要）
                        await checkAndUpdateScopesIfNeeded()

                        guard
                            let scene = UIApplication.shared.connectedScenes.first
                            as? UIWindowScene,
                            let viewController = scene.windows.first?.rootViewController
                        else {
                            isLoggingIn = false // 确保在失败时重置状态
                            return
                        }

                        do {
                            // 尝试使用当前配置的 scopes 进行登录
                            let authState = try await AuthTokenManager.shared.authorize(
                                presenting: viewController,
                                scopes: EVELogin.shared.config?.scopes ?? []
                            )

                            let character = try await EVELogin.shared.processLogin(
                                authState: authState
                            )
                            await finishLoginSuccess(character: character)
                        } catch {
                            // 检查是否是 scope 无效错误
                            if error.localizedDescription.lowercased().contains("invalid_scope") {
                                Logger.info("检测到无效权限，尝试重新获取最新的 scopes")
                                let scopes = await ScopeManager.shared.getLatestScopes(
                                    forceRefresh: true
                                )

                                do {
                                    let authState = try await AuthTokenManager.shared.authorize(
                                        presenting: viewController,
                                        scopes: scopes
                                    )
                                    let character = try await EVELogin.shared.processLogin(
                                        authState: authState
                                    )
                                    await finishLoginSuccess(character: character)
                                } catch {
                                    viewModel.errorMessage =
                                        "登录失败，请稍后重试：\(error.localizedDescription)"
                                    viewModel.showingError = true
                                    Logger.error("使用更新后的权限登录仍然失败: \(error)")
                                }
                            } else {
                                viewModel.errorMessage = error.localizedDescription
                                viewModel.showingError = true
                                Logger.error("登录失败: \(error)")
                            }
                        }

                        // 确保在最后重置登录状态
                        isLoggingIn = false
                    }
                }) {
                    HStack {
                        if isLoggingIn {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 5)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(
                            NSLocalizedString(
                                isLoggingIn ? "Account_Logging_In" : "Account_Add_Character",
                                comment: ""
                            )
                        )
                        Spacer()
                    }
                }
                .disabled(isLoggingIn || isEditing)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(NSLocalizedString("Scopes_refresh_hint", comment: ""))
                        Button(action: {
                            // 添加刷新状态指示
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()

                            // 设置刷新状态
                            isRefreshingScopes = true

                            Task {
                                // 强制刷新 scopes
                                Logger.info("手动强制刷新 scopes")
                                let scopeResult = await ScopeManager.shared.getLatestScopesWithSource(
                                    forceRefresh: true
                                )

                                // 更新 EVELogin 中的 scopes 配置
                                await MainActor.run {
                                    EVELogin.shared.config?.scopes = scopeResult.scopes
                                }
                                Logger.info(
                                    "成功刷新 scopes，获取到 \(scopeResult.scopes.count) 个权限，来源: \(scopeResult.source)"
                                )

                                // 显示成功提示
                                await MainActor.run {
                                    isRefreshingScopes = false // 重置刷新状态

                                    // 根据数据来源选择不同的消息
                                    let messageKey =
                                        scopeResult.source == .network
                                            ? "Scopes_Refresh_Success" : "Scopes_Local_Refresh_Success"
                                    successMessage = String(
                                        format: NSLocalizedString(messageKey, comment: ""),
                                        scopeResult.scopes.count
                                    )
                                    showingSuccess = true
                                }
                            }
                        }) {
                            HStack {
                                if isRefreshingScopes {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .padding(.trailing, 2)
                                }
                                Text("scopes")
                                    .foregroundColor(.blue)
                            }
                        }
                        .disabled(isRefreshingScopes)
                        Text(".")
                    }

                    Button(action: {
                        showingSteamLoginSheet = true
                    }) {
                        Text(NSLocalizedString("Account_Steam_Login_Hint", comment: ""))
                            .foregroundColor(.blue)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }

            // 已登录角色列表
            if !viewModel.characters.isEmpty {
                Section(header: accountListHeader) {
                    ForEach(viewModel.characters, id: \.CharacterID) { character in
                        Button {
                            if isEditing {
                                characterToRemove = character
                            } else {
                                let portrait = viewModel.characterPortraits[character.CharacterID]
                                onCharacterSelect?(character, portrait)
                                selectedItem = nil
                            }
                        } label: {
                            characterRow(for: character)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { from, to in
                        viewModel.moveCharacter(from: from, to: to)
                    }
                    .onDelete { indexSet in
                        // 左滑删除：与点 trash 按钮一致，触发确认 alert
                        if let index = indexSet.first, index < viewModel.characters.count {
                            characterToRemove = viewModel.characters[index]
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .refreshable {
            // 刷新所有角色的ESI信息
            await refreshAllCharacters()
        }
        .navigationTitle(NSLocalizedString("Account_Management", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.characters.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isEditing.toggle()
                    }) {
                        Text(
                            NSLocalizedString(
                                isEditing ? "Main_Market_Done" : "Main_Market_Edit", comment: ""
                            )
                        )
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .alert(
            NSLocalizedString("Account_Login_Failed", comment: ""),
            isPresented: Binding(
                get: { viewModel.showingError },
                set: { viewModel.showingError = $0 }
            )
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert(
            NSLocalizedString("Operation_Success", comment: ""),
            isPresented: $showingSuccess
        ) {
            Button(NSLocalizedString("Common_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .alert(
            NSLocalizedString("Account_Remove_Confirm_Title", comment: ""),
            isPresented: .init(
                get: { characterToRemove != nil },
                set: { if !$0 { characterToRemove = nil } }
            )
        ) {
            Button(NSLocalizedString("Account_Remove_Confirm_Cancel", comment: ""), role: .cancel) {
                characterToRemove = nil
            }
            Button(
                NSLocalizedString("Account_Remove_Confirm_Remove", comment: ""), role: .destructive
            ) {
                if let character = characterToRemove {
                    let characterId = character.CharacterID

                    // 清除所有 token（包括 access token 和 refresh token）
                    Task {
                        await AuthTokenManager.shared.clearAllTokens(for: characterId)
                    }

                    viewModel.removeCharacter(character)
                    // 发送通知，通知其他视图角色已被删除
                    NotificationCenter.default.post(
                        name: Notification.Name("CharacterRemoved"),
                        object: nil,
                        userInfo: ["characterId": characterId]
                    )
                    // 从过期token集合中移除该角色
                    expiredTokenCharacters.remove(characterId)
                    characterToRemove = nil
                }
            }
        } message: {
            if let character = characterToRemove {
                Text(character.CharacterName)
            }
        }
        .sheet(isPresented: $showingSteamLoginSheet) {
            SteamLoginHelpView()
        }
        .onAppear {
            viewModel.loadCharacters()
            let characterAuths = EVELogin.shared.loadCharacters()
            // 同步套上已知过期遮罩，避免首帧先显示正常头像
            expiredTokenCharacters = Set(
                characterAuths.filter(\.character.refreshTokenExpired).map(\.character.CharacterID)
            )

            // 从缓存更新所有角色的数据
            Task { @MainActor in
                for auth in characterAuths {
                    await loadCachedData(for: auth.character.CharacterID)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))
        ) { _ in
            // 强制视图刷新以更新技能名称
            withAnimation {
                forceUpdate.toggle()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("CharacterDetailsUpdated")
            )
        ) { notification in
            // 同步 token 过期状态（后台 API 调用触发 token 过期/恢复时实时更新 UI）
            if let character = notification.userInfo?["character"] as? EVECharacterInfo {
                if character.refreshTokenExpired {
                    expiredTokenCharacters.insert(character.CharacterID)
                } else {
                    expiredTokenCharacters.remove(character.CharacterID)
                }
            }
        }
        .id(forceUpdate)
        .onChange(of: viewModel.characters.isEmpty) { _, newValue in
            if newValue {
                isEditing = false
            }
        }
        .onDisappear {
            // 当视图消失时，从本地快速更新数据
            Task {
                await mainViewModel.quickRefreshFromLocal()
            }
        }
    }

    // MARK: - 列表 header 汇总

    /// 已加载（不在刷新中集合）的人物
    private var loadedCharacters: [EVECharacterInfo] {
        viewModel.characters.filter { !refreshingCharacters.contains($0.CharacterID) }
    }

    private var loadedWalletSum: Double {
        loadedCharacters.reduce(0) { $0 + ($1.walletBalance ?? 0) }
    }

    private var loadedSkillPointSum: Int {
        loadedCharacters.reduce(0) { $0 + ($1.totalSkillPoints ?? 0) }
    }

    private var loadingProgressText: String {
        let done = max(0, refreshingTotal - refreshingCharacters.count)
        return "\(NSLocalizedString("Account_Loading_Progress", comment: "")) \(done)/\(refreshingTotal)"
    }

    private var accountSummaryText: String {
        let wallet = NSLocalizedString("Account_Wallet_value", comment: "")
        let sp = NSLocalizedString("Account_Total_SP", comment: "")
        return "\(wallet) \(FormatUtil.formatISK(loadedWalletSum)) · \(sp) \(formatSkillPoints(loadedSkillPointSum))"
    }

    private var accountListHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(
                    "\(NSLocalizedString("Account_Logged_Characters", comment: "")) (\(viewModel.characters.count))"
                )
                if !refreshingCharacters.isEmpty {
                    Spacer()
                    Text(loadingProgressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.none)
                }
            }
            Text(accountSummaryText)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.none)
        }
    }

    /// 从缓存加载单个角色的全部数据（钱包 / 技能点 / 技能队列 / 位置 / 头像 / 公共信息），并写入 ViewModel
    private func loadCachedData(for characterId: Int) async {
        // 钱包余额
        let cachedBalance = await CharacterWalletAPI.shared.getCachedWalletBalance(
            characterId: characterId
        )
        if let balance = Double(cachedBalance) {
            viewModel.updateCharacter(characterId: characterId) { character in
                character.walletBalance = balance
            }
        }

        // 技能点
        if let skillsInfo = try? await CharacterSkillsAPI.shared.fetchCharacterSkills(
            characterId: characterId,
            forceRefresh: false
        ) {
            viewModel.updateCharacter(characterId: characterId) { character in
                character.totalSkillPoints = skillsInfo.total_sp
                character.unallocatedSkillPoints = skillsInfo.unallocated_sp
            }
        }

        // 技能队列
        if let queue = try? await CharacterSkillsAPI.shared.fetchSkillQueue(
            characterId: characterId,
            forceRefresh: false
        ) {
            viewModel.updateCharacter(characterId: characterId) { character in
                applySkillQueue(queue, to: &character)
            }
        }

        // 位置信息
        if let location = try? await CharacterLocationAPI.shared.fetchCharacterLocation(
            characterId: characterId,
            forceRefresh: false
        ) {
            viewModel.updateCharacter(characterId: characterId) { character in
                character.locationStatus = location.locationStatus
            }

            if let locationInfo = await getSolarSystemInfo(
                solarSystemId: location.solar_system_id,
                databaseManager: viewModel.databaseManager
            ) {
                viewModel.updateCharacter(characterId: characterId) { character in
                    character.location = locationInfo
                }
            }
        }

        // 头像
        if let portrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
            characterId: characterId,
            forceRefresh: false
        ) {
            viewModel.characterPortraits[characterId] = portrait
        }

        // 角色公共信息（组织信息）
        if let publicInfo = try? await CharacterAPI.shared.fetchCharacterPublicInfo(
            characterId: characterId,
            forceRefresh: false
        ) {
            viewModel.updateCharacter(characterId: characterId) { character in
                character.corporationId = publicInfo.corporation_id
                character.allianceId = publicInfo.alliance_id
                character.factionId = publicInfo.faction_id
            }
        }

        await persistCharacterSnapshot(characterId: characterId)
    }

    /// 构造角色行视图（编辑/非编辑模式共用，避免参数列表重复）
    private func characterRow(for character: EVECharacterInfo) -> some View {
        CharacterRowView(
            character: character,
            portrait: viewModel.characterPortraits[character.CharacterID],
            isRefreshing: refreshingCharacters.contains(character.CharacterID),
            isEditing: isEditing,
            refreshTokenhasExpired: expiredTokenCharacters.contains(character.CharacterID),
            formatISK: FormatUtil.formatISK,
            formatSkillPoints: formatSkillPoints,
            formatRemainingTime: formatRemainingTime
        )
    }

    /// 添加一个帮助函数来处理 MainActor.run 的返回值
    @discardableResult
    @Sendable
    private func updateUI<T>(_ operation: @MainActor () -> T) async -> T {
        await MainActor.run { operation() }
    }

    /// 从技能队列提取当前技能信息并写入角色（统一处理 训练中 / 暂停 / 空队列 三种状态）
    private func applySkillQueue(_ queue: [SkillQueueItem], to character: inout EVECharacterInfo) {
        character.skillQueueLength = queue.count

        if let currentSkill = queue.first(where: { $0.isCurrentlyTraining }),
           let skillName = SkillTreeManager.shared.getSkillName(for: currentSkill.skill_id)
        {
            // 训练中
            character.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                skillId: currentSkill.skill_id,
                name: skillName,
                level: currentSkill.skillLevel,
                progress: currentSkill.progress,
                remainingTime: currentSkill.remainingTime
            )
        } else if let firstSkill = queue.first,
                  let skillName = SkillTreeManager.shared.getSkillName(for: firstSkill.skill_id),
                  let trainingStartSp = firstSkill.training_start_sp,
                  let levelEndSp = firstSkill.level_end_sp
        {
            // 暂停状态：根据已花费 SP 计算实际进度
            character.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                skillId: firstSkill.skill_id,
                name: skillName,
                level: firstSkill.skillLevel,
                progress: SkillProgressCalculator.calculateProgress(
                    trainingStartSp: trainingStartSp,
                    levelEndSp: levelEndSp,
                    finishedLevel: firstSkill.finished_level
                ),
                remainingTime: nil
            )
        } else {
            // 队列为空
            character.currentSkill = nil
        }
    }

    /// 将 ViewModel 中的角色信息写回 UserDefaults，使下次进入账号页时技能进度等与上次展示一致
    private func persistCharacterSnapshot(characterId: Int) async {
        let snapshot = await MainActor.run {
            viewModel.getCharacter(by: characterId)
        }
        guard let snapshot else { return }
        do {
            try await EVELogin.shared.saveCharacterInfo(snapshot)
        } catch {
            Logger.debug("保存角色快照失败 \(characterId): \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshAllCharacters() async {
        // 先让刷新指示器完成动画
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        isRefreshing = true

        let characterAuths = EVELogin.shared.loadCharacters()

        // 先套上已知过期遮罩，且不进入刷新转圈（避免遮罩被 ProgressView 盖住）
        let knownExpiredIds = Set(
            characterAuths.filter(\.character.refreshTokenExpired).map(\.character.CharacterID)
        )
        expiredTokenCharacters = knownExpiredIds
        let candidates = characterAuths.filter {
            !knownExpiredIds.contains($0.character.CharacterID)
        }
        refreshingCharacters = Set(candidates.map(\.character.CharacterID))
        refreshingTotal = candidates.count
        // 让 UI 先渲染过期遮罩
        await Task.yield()

        Logger.info(
            "刷新全部角色: \(candidates.count) 人 (跳过已知过期 \(knownExpiredIds.count) 人)"
        )

        // 角色优先：每个角色独立检查 token → 通过后并行加载 5 类数据，全部就绪即刷新 UI
        // 分批处理角色，每批最多 10 个
        let batchSize = 10
        for batchStart in stride(from: 0, to: candidates.count, by: batchSize) {
            let end = min(batchStart + batchSize, candidates.count)
            let currentBatch = Array(candidates[batchStart ..< end])

            // 使用 TaskGroup 并行处理当前批次的角色数据刷新
            await withTaskGroup(of: Void.self) { group in
                for characterAuth in currentBatch {
                    group.addTask {
                        let characterId = characterAuth.character.CharacterID

                        do {
                            // 使用 TokenManager 获取有效的 token
                            let currentAccessToken = try await AuthTokenManager.shared
                                .getAccessToken(for: characterId)
                            Logger.info(
                                "获得角色Token \(characterAuth.character.CharacterName)(\(characterId)) token: \(String(reflecting: currentAccessToken)), 上次token更新: \(characterAuth.lastTokenUpdateTime)"
                            )

                            // 并行获取全部 5 类数据并更新 UI
                            try await self.fetchAndUpdateCharacter(
                                characterId: characterId, forceRefresh: true
                            )

                            await updateUI {
                                expiredTokenCharacters.remove(characterId)
                            }
                        } catch {
                            if case NetworkError.refreshTokenExpired = error {
                                await updateUI {
                                    expiredTokenCharacters.insert(characterId)
                                }
                            }
                            Logger.error("刷新角色信息失败: \(error)")
                        }

                        // 从刷新集合中移除角色
                        await updateUI {
                            refreshingCharacters.remove(characterId)
                        }
                    }
                }

                // 等待当前批次的所有任务完成
                await group.waitForAll()
            }
        }

        // 更新登录状态
        await updateUI {
            self.isRefreshing = false
        }
    }

    /// 格式化技能点显示
    private func formatSkillPoints(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM", Double(sp) / 1_000_000.0)
        } else if sp >= 1000 {
            return String(format: "%.1fK", Double(sp) / 1000.0)
        }
        return "\(sp)"
    }

    /// 格式化剩余时间显示
    private func formatRemainingTime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// processLogin 成功后的 UI / 数据收尾（权威落盘已在 processLogin 完成）
    private func finishLoginSuccess(character: EVECharacterInfo) async {
        expiredTokenCharacters.remove(character.CharacterID)

        viewModel.characterInfo = character
        viewModel.loadCharacters()

        // refreshCharacterData 已并行获取全部 5 类数据（技能+队列、钱包、头像、位置、公共信息）
        await refreshCharacterData(character)

        Logger.info(
            "成功刷新角色信息(\(character.CharacterID)) - \(character.CharacterName)"
        )
    }

    /// 获取单个角色的全部数据（5 路并行）并更新 UI，然后持久化快照
    /// 调用方负责 token 检查、expiredTokenCharacters / refreshingCharacters 管理
    private func fetchAndUpdateCharacter(characterId: Int, forceRefresh: Bool) async throws {
        let service = CharacterDataService.shared

        // 并行获取所有数据
        async let skillInfoTask = service.getSkillInfo(
            id: characterId, forceRefresh: forceRefresh
        )
        async let walletTask = service.getWalletBalance(
            id: characterId, forceRefresh: forceRefresh
        )
        async let portraitTask = service.getCharacterPortrait(
            id: characterId, forceRefresh: forceRefresh
        )
        async let locationTask = service.getLocation(
            id: characterId, forceRefresh: forceRefresh
        )
        async let publicInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
            characterId: characterId, forceRefresh: forceRefresh
        )

        let ((skillsResponse, queue), balance, portrait, location, publicInfo) = try await (
            skillInfoTask, walletTask, portraitTask, locationTask, publicInfoTask
        )

        await updateUI {
            self.viewModel.updateCharacter(characterId: characterId) { character in
                character.corporationId = publicInfo.corporation_id
                character.allianceId = publicInfo.alliance_id
                character.factionId = publicInfo.faction_id
                character.totalSkillPoints = skillsResponse.total_sp
                character.unallocatedSkillPoints = skillsResponse.unallocated_sp
                applySkillQueue(queue, to: &character)
                character.walletBalance = balance
                character.locationStatus = location.locationStatus
            }

            self.viewModel.characterPortraits[characterId] = portrait

            // 异步更新位置详细信息
            Task {
                let databaseManager = self.viewModel.databaseManager
                let viewModel = self.viewModel
                if let locationInfo = await getSolarSystemInfo(
                    solarSystemId: location.solar_system_id,
                    databaseManager: databaseManager
                ) {
                    await MainActor.run {
                        viewModel.updateCharacter(characterId: characterId) { character in
                            character.location = locationInfo
                        }
                    }
                }
            }
        }

        await persistCharacterSnapshot(characterId: characterId)
    }

    /// 刷新单个角色的数据（登录后调用，token 已知有效）
    private func refreshCharacterData(_ character: EVECharacterInfo) async {
        do {
            try await fetchAndUpdateCharacter(
                characterId: character.CharacterID, forceRefresh: true
            )
            Logger.success("成功刷新角色数据 - \(character.CharacterName)")
        } catch {
            Logger.error("刷新角色数据失败 - \(character.CharacterName): \(error)")
        }

        await updateUI {
            refreshingCharacters.remove(character.CharacterID)
        }
    }

    /// 在AccountsView结构体内添加一个检查scopes更新时间的函数
    private func checkAndUpdateScopesIfNeeded() async {
        Logger.info("检查并更新 scopes...")
        // 只调用一次 getScopes，它会内部调用 getLatestScopes
        let scopes = await EVELogin.shared.getScopes()
        Logger.info("完成 scopes 检查，当前共有 \(scopes.count) 个权限")
    }
}

/// 添加 CharacterRowView 结构体
struct CharacterRowView: View {
    let character: EVECharacterInfo
    let portrait: UIImage?
    let isRefreshing: Bool
    let isEditing: Bool
    let refreshTokenhasExpired: Bool
    let formatISK: (Double) -> String
    let formatSkillPoints: (Int) -> String
    let formatRemainingTime: (TimeInterval) -> String

    /// 显示带标签的可选信息行：有值时显示 "\(label): \(formatted)"，无值时显示 "\(label): \(emptyPlaceholder)"
    @ViewBuilder
    private func optionalInfoRow<T>(
        label: String,
        value: T?,
        formatter: (T) -> String,
        emptyPlaceholder: String
    ) -> some View {
        let displayText = value.map { "\(label): \(formatter($0))" }
            ?? "\(label): \(emptyPlaceholder)"
        Text(displayText)
            .font(.caption)
            .foregroundColor(.gray)
            .lineLimit(1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CharacterAvatarWithBadges(
                character: character,
                portrait: portrait,
                isRefreshing: isRefreshing,
                refreshTokenhasExpired: refreshTokenhasExpired
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(character.CharacterName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    if isRefreshing {
                        // 位置信息占位
                        HStack(spacing: 4) {
                            Text("0.0")
                                .foregroundColor(.gray)
                                .redacted(reason: .placeholder)
                            Text(NSLocalizedString("Misc_Loading", comment: ""))
                                .foregroundColor(.gray)
                                .redacted(reason: .placeholder)
                        }
                        .font(.caption)

                        // 钱包信息占位
                        Text("\(NSLocalizedString("Account_Wallet_value", comment: "")): 0.00 ISK")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .redacted(reason: .placeholder)

                        // 技能点信息占位
                        Text("\(NSLocalizedString("Account_Total_SP", comment: "")): 0.0M SP")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .redacted(reason: .placeholder)
                    } else {
                        // 位置信息
                        if let location = character.location {
                            HStack(spacing: 4) {
                                Text(formatSystemSecurity(location.security))
                                    .foregroundColor(getSecurityColor(location.security))
                                Text("\(location.systemName) / \(location.regionName)").lineLimit(1)
                                if let locationStatus = character.locationStatus?.description {
                                    Text(locationStatus)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                        } else {
                            Text(NSLocalizedString("Unknown_Location", comment: ""))
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }

                        // 钱包信息
                        optionalInfoRow(
                            label: NSLocalizedString("Account_Wallet_value", comment: ""),
                            value: character.walletBalance,
                            formatter: formatISK,
                            emptyPlaceholder: "-- ISK"
                        )

                        // 技能点信息
                        optionalInfoRow(
                            label: NSLocalizedString("Account_Total_SP", comment: ""),
                            value: character.totalSkillPoints,
                            formatter: { sp in
                                if let unallocatedSP = character.unallocatedSkillPoints,
                                   unallocatedSP > 0
                                {
                                    return "\(formatSkillPoints(sp)) SP (\(NSLocalizedString("Main_Skill_Queue_Free_SP", comment: "")) \(formatSkillPoints(unallocatedSP)))"
                                }
                                return "\(formatSkillPoints(sp)) SP"
                            },
                            emptyPlaceholder: "-- SP"
                        )

                        // 技能队列信息
                        if let currentSkill = character.currentSkill {
                            VStack(alignment: .leading, spacing: 4) {
                                // 技能进度条
                                PulsingProgressBar(
                                    progress: currentSkill.progress,
                                    color: currentSkill.remainingTime != nil ? .green : .gray,
                                    height: 4,
                                    cornerRadius: 2,
                                    showPulse: currentSkill.remainingTime != nil
                                )

                                // 技能信息
                                HStack {
                                    HStack(spacing: 4) {
                                        Image(
                                            systemName: currentSkill.remainingTime != nil
                                                ? "play.fill" : "pause.fill"
                                        )
                                        .font(.caption)
                                        .foregroundColor(
                                            currentSkill.remainingTime != nil ? .green : .gray
                                        )
                                        Text(
                                            "\(SkillTreeManager.shared.getSkillName(for: currentSkill.skillId) ?? currentSkill.name) \(currentSkill.level)"
                                        )
                                    }
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                    Spacer()

                                    if let remainingTime = currentSkill.remainingTime {
                                        Text(formatRemainingTime(remainingTime))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    } else {
                                        Text(
                                            "\(NSLocalizedString("Main_Skills_Paused", comment: ""))"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                    }
                                }
                            }
                        } else {
                            // 没有技能在训练时显示的进度条
                            GeometryReader { _ in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 4)
                                }
                            }
                            .frame(height: 4)
                            HStack {
                                Text("-")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(NSLocalizedString("Main_Skills_Empty", comment: ""))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.leading, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .overlay(alignment: .trailing) {
            Image(systemName: "trash.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.red))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .padding(.trailing, 4)
                .allowsHitTesting(false)
                .scaleEffect(isEditing ? 1 : 0)
                .opacity(isEditing ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isEditing)
        }
        .contentShape(Rectangle())
    }
}

/// 技能进度计算工具类
enum SkillProgressCalculator {
    /// 基准技能点数（x1倍增系数）
    static let baseSkillPoints: [Int] = [250, 1415, 8000, 45255, 256_000]

    /// 计算技能的倍增系数
    static func calculateMultiplier(levelEndSp: Int, finishedLevel: Int) -> Int {
        guard finishedLevel > 0 && finishedLevel <= baseSkillPoints.count else { return 1 }
        let baseEndSp = baseSkillPoints[finishedLevel - 1]
        let multiplier = Double(levelEndSp) / Double(baseEndSp)
        return Int(round(multiplier))
    }

    /// 获取前一等级的技能点数
    static func getPreviousLevelSp(finishedLevel: Int, multiplier: Int) -> Int {
        guard finishedLevel > 1 && finishedLevel <= baseSkillPoints.count else { return 0 }
        return baseSkillPoints[finishedLevel - 2] * multiplier
    }

    /// 计算技能训练进度（0.0 - 1.0）
    static func calculateProgress(trainingStartSp: Int, levelEndSp: Int, finishedLevel: Int)
        -> Double
    {
        let multiplier = calculateMultiplier(levelEndSp: levelEndSp, finishedLevel: finishedLevel)
        let previousLevelSp = getPreviousLevelSp(
            finishedLevel: finishedLevel, multiplier: multiplier
        )

        let progress =
            Double(trainingStartSp - previousLevelSp) / Double(levelEndSp - previousLevelSp)
        return min(max(progress, 0.0), 1.0) // 确保进度在0.0到1.0之间
    }
}

/// Steam 登录帮助视图
struct SteamLoginHelpView: View {
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    @Environment(\.dismiss) private var dismiss

    private var gifFileName: String {
        selectedLanguage.hasPrefix("zh") ? "Steam(zh)" : "Steam(en)"
    }

    private var gifURL: URL? {
        Bundle.main.url(forResource: gifFileName, withExtension: "gif")
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 介绍文本和参考链接
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Account_Steam_Login_Description", comment: ""))
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(NSLocalizedString("Account_Steam_Login_Reference_Hint", comment: ""))
                            .font(.body)
                            .foregroundColor(.primary)
                        Link(
                            NSLocalizedString("Account_Steam_Login_Reference_Link", comment: ""),
                            destination: URL(string: "https://support.eveonline.com/hc/articles/203523662")!
                        )
                        .font(.body)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)

                    // GIF 图片
                    if let gifURL = gifURL, let gifData = try? Data(contentsOf: gifURL) {
                        GIFWebView(data: gifData)
                            .frame(maxWidth: .infinity)
                            .frame(height: 640)
                            .cornerRadius(8)
                            .padding(.horizontal)
                    } else {
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("Account_Steam_Login_GIF_Not_Found", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(NSLocalizedString("Account_Steam_Login_Title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_OK", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// GIF 显示组件
struct GIFWebView: UIViewRepresentable {
    let data: Data

    func makeUIView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false

        // 创建 HTML 内容来显示 GIF
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    background-color: transparent;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    object-fit: contain;
                }
            </style>
        </head>
        <body>
            <img src="data:image/gif;base64,\(data.base64EncodedString())" alt="GIF">
        </body>
        </html>
        """

        webView.loadHTMLString(htmlString, baseURL: nil)
        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {
        // 不需要更新
    }
}
