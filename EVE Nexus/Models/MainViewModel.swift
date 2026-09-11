import Foundation
import SwiftUI

/// 定义 CharacterSkills 结构体
struct CharacterSkills {
    let total_sp: Int
    let unallocated_sp: Int
}

/// 定义 QueuedSkill 结构体
struct QueuedSkill {
    let skill_id: Int
    let skillLevel: Int
    let remainingTime: TimeInterval?
    let progress: Double
    let isCurrentlyTraining: Bool
}

/// 定义 CharacterStats 结构体
struct CharacterStats {
    var skillPoints: String = "--"
    var queueStatus: String = "--"
    var walletBalance: String = "--"
    var location: String = "--"
}

@MainActor
class MainViewModel: ObservableObject {
    // MARK: - Constants

    private enum Constants {
        static let baseCloneCooldown: TimeInterval = 24 * 3600 // 基础24小时冷却
        static let secondsInHour = 3600
        static let maxRetryCount = 3
        static let retryDelay: TimeInterval = 1.0
        static let emptyValue = "--"
    }

    // MARK: - Loading State

    enum LoadingState: String {
        case idle
        case loadingPortrait
        case loadingSkills
        case loadingWallet
        case loadingQueue
        case loadingServerStatus
        case loadingCloneStatus
    }

    // MARK: - Error Handling

    enum RefreshError: Error {
        case serverStatusFailed
    }

    // MARK: - Published Properties

    @Published var characterStats = CharacterStats()
    @Published var serverStatus: ServerStatus?
    @Published var selectedCharacter: EVECharacterInfo?
    @Published var characterPortrait: UIImage?
    @Published var cloneJumpStatus: String = NSLocalizedString(
        "Main_Jump_Clones_Available", comment: ""
    )
    @Published var cloneCooldownEndDate: Date? = nil // 克隆冷却结束时间
    @Published var skillQueueEndDate: Date? = nil // 技能队列完成时间
    @Published var skillQueueCount: Int = 0 // 技能队列中的技能数量
    @Published var isRefreshing = false
    @Published var loadingState: LoadingState = .idle
    @Published var lastError: RefreshError?

    // 添加军团和联盟相关的发布属性
    @Published var corporationInfo: CorporationInfo?
    @Published var corporationLogo: UIImage?
    @Published var allianceInfo: AllianceInfo?
    @Published var allianceLogo: UIImage?

    // 添加势力相关的发布属性
    @Published var factionInfo: FactionInfo?
    @Published var factionLogo: UIImage?

    // MARK: - Private Properties

    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    // 缓存克隆冷却时间，避免重复计算
    private var cachedCloneCooldownPeriod: TimeInterval?
    private var lastCloneCooldownCalculation: Date?
    private let cloneCooldownCacheTimeout: TimeInterval = 300 // 5分钟缓存
    /// 刷新任务去重：防止多个刷新任务同时运行
    private var refreshTask: Task<Void, Never>?

    private var cloneCooldownPeriod: TimeInterval {
        // 检查缓存是否有效
        if let cached = cachedCloneCooldownPeriod,
           let lastCalculation = lastCloneCooldownCalculation,
           Date().timeIntervalSince(lastCalculation) < cloneCooldownCacheTimeout
        {
            return cached
        }

        // 如果没有缓存或缓存过期，返回默认值
        // 实际的异步计算将在需要时进行
        return Constants.baseCloneCooldown
    }

    /// 异步计算克隆冷却时间
    private func calculateCloneCooldownPeriod() async {
        guard let character = selectedCharacter else { return }

        do {
            // 调用API获取技能数据
            let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: character.CharacterID,
                forceRefresh: false
            )

            // 查找 Advanced Infomorph Psychology 技能等级
            var cooldownPeriod = Constants.baseCloneCooldown
            if let infomorphSkill = skillsResponse.skillsMap[33399] {
                // 每级减少1小时，从24小时开始
                let reductionHours = infomorphSkill.trained_skill_level
                let remainingHours = max(24 - reductionHours, 1) // 最少保留1小时冷却时间
                cooldownPeriod = Double(remainingHours * Constants.secondsInHour)
            }

            // 更新缓存
            await MainActor.run {
                self.cachedCloneCooldownPeriod = cooldownPeriod
                self.lastCloneCooldownCalculation = Date()
            }
        } catch {
            Logger.error("获取技能数据失败: \(error)")
            // 保持默认值
        }
    }

    // MARK: - Cache Management

    private struct Cache {
        var skills: CharacterSkills?
        var walletBalance: Double?
        var skillQueue: [QueuedSkill]?

        mutating func clear() {
            skills = nil
            walletBalance = nil
            skillQueue = nil
        }
    }

    private var cache = Cache()

    // MARK: - Initialization

    init() {
        loadSavedCharacter()
    }

    // MARK: - Private Methods

    @MainActor
    private func updateCloneStatus(from cloneInfo: CharacterCloneInfo) {
        // 异步计算克隆冷却时间
        Task {
            await calculateCloneCooldownPeriod()

            if let lastJumpDate = cloneInfo.last_clone_jump_date {
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime]

                if let jumpDate = dateFormatter.date(from: lastJumpDate) {
                    let now = Date()
                    let timeSinceLastJump = now.timeIntervalSince(jumpDate)

                    if timeSinceLastJump >= cloneCooldownPeriod {
                        cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                        cloneCooldownEndDate = nil
                    } else {
                        // 计算并缓存冷却完成时间，但不使用定时器更新
                        cloneCooldownEndDate = jumpDate.addingTimeInterval(cloneCooldownPeriod)
                        // 设置基本状态，具体倒计时由CloneCountdownView组件处理
                        cloneJumpStatus = NSLocalizedString(
                            "Main_Jump_Clones_Available", comment: ""
                        )
                    }
                }
            } else {
                cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                cloneCooldownEndDate = nil
            }
        }
    }

    private func updateSkillPoints(_ totalSP: Int?) {
        if let sp = totalSP {
            characterStats.skillPoints = String(
                format: NSLocalizedString("Main_Skills_Ponits", comment: ""),
                FormatUtil.format(Double(sp))
            )
        } else {
            characterStats.skillPoints = String(
                format: NSLocalizedString("Main_Skills_Ponits", comment: ""), Constants.emptyValue
            )
        }
    }

    private func updateWalletBalance(_ balance: Double?) {
        if let bal = balance {
            characterStats.walletBalance = String(
                format: NSLocalizedString("Main_Wealth_ISK", comment: ""), FormatUtil.formatISK(bal)
            )
        } else {
            characterStats.walletBalance = String(
                format: NSLocalizedString("Main_Wealth_ISK", comment: ""), Constants.emptyValue
            )
        }
    }

    /// 计算当前正在训练技能的实际已学点数
    /// 只计算当前正在训练的技能（如果队列未暂停）
    /// - Parameter queue: 技能队列
    /// - Returns: 正在训练技能已获得的技能点数
    private func calculateCurrentlyTrainingSkillPoints(queue: [SkillQueueItem]) -> Int {
        // 检查队列是否暂停（如果第一个技能没有start_date和finish_date，就是暂停的）
        let isPaused = queue.first?.start_date == nil || queue.first?.finish_date == nil
        if isPaused {
            return 0
        }

        let now = Date()

        // 找到正在训练的技能
        guard let trainingSkill = queue.first(where: { $0.isCurrentlyTraining }),
              let startDate = trainingSkill.start_date,
              let finishDate = trainingSkill.finish_date,
              let trainingStartSp = trainingSkill.training_start_sp,
              let levelEndSp = trainingSkill.level_end_sp
        else {
            return 0
        }

        // 计算训练时间进度
        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
        let trainedTime = now.timeIntervalSince(startDate)

        guard totalTrainingTime > 0 else { return 0 }

        // 计算时间进度（0.0 到 1.0）
        let timeProgress = min(1.0, max(0.0, trainedTime / totalTrainingTime))

        // 计算该等级需要训练的总技能点数
        let totalSPForLevel = levelEndSp - trainingStartSp

        // 计算已经获得的技能点数
        return Int(Double(totalSPForLevel) * timeProgress)
    }

    private func processSkillInfo(skillsResponse: CharacterSkillsResponse, queue: [SkillQueueItem]) {
        cache.skills = CharacterSkills(
            total_sp: skillsResponse.total_sp,
            unallocated_sp: skillsResponse.unallocated_sp
        )

        // 计算当前正在训练技能的实际已学点数（如果队列未暂停）
        let currentlyTrainingSP = calculateCurrentlyTrainingSkillPoints(queue: queue)

        // 将未分配的技能点数（free sp）和正在训练技能已获得的技能点数加到total_sp上
        let totalSPWithTraining = skillsResponse.total_sp + skillsResponse.unallocated_sp + currentlyTrainingSP
        updateSkillPoints(totalSPWithTraining)

        // 更新技能队列数量
        skillQueueCount = queue.count

        // 更新技能队列结束时间
        if let lastSkill = queue.last, let remainingTime = lastSkill.remainingTime,
           remainingTime > 0
        {
            skillQueueEndDate = Date().addingTimeInterval(remainingTime)
        } else if !queue.isEmpty {
            // 检查是否有正在训练的技能
            let trainingSkill = queue.first(where: { $0.isCurrentlyTraining })
            if trainingSkill != nil {
                // 有正在训练的技能但没有明确结束时间，设置一个短暂的结束时间
                skillQueueEndDate = Date().addingTimeInterval(60) // 1分钟
            } else {
                // 有技能但没有正在训练的
                skillQueueEndDate = nil
            }
        } else {
            // 队列为空
            skillQueueEndDate = nil
        }

        cache.skillQueue = queue.map { skill in
            QueuedSkill(
                skill_id: skill.skill_id,
                skillLevel: skill.finished_level,
                remainingTime: skill.remainingTime,
                progress: skill.progress,
                isCurrentlyTraining: skill.isCurrentlyTraining
            )
        }
    }

    private func retryOperation<T>(
        named operationName: String,
        maxRetries: Int = Constants.maxRetryCount,
        operation: () async throws -> T
    ) async throws -> T {
        var retryCount = 0
        var lastError: Error?

        while retryCount < maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                retryCount += 1
                if retryCount < maxRetries {
                    Logger.warning(
                        "操作失败: \(operationName) (尝试 \(retryCount)/\(maxRetries)) - 错误: \(error)"
                    )
                    try await Task.sleep(nanoseconds: UInt64(Constants.retryDelay * 1_000_000_000))
                }
            }
        }

        Logger.error("操作最终失败: \(operationName)")
        throw lastError ?? RefreshError.serverStatusFailed
    }

    // MARK: - Public Methods

    func refreshAllBasicData(forceRefresh: Bool = false) async {
        // 如果已有刷新任务在运行
        if let existingTask = refreshTask {
            if forceRefresh {
                // 强制刷新时，取消现有任务并创建新任务
                Logger.info("强制刷新：取消现有刷新任务并创建新任务")
                existingTask.cancel()
                refreshTask = nil
            } else {
                // 非强制刷新时，等待现有任务完成
                Logger.info("刷新任务已在进行中，等待完成...")
                await existingTask.value
                return
            }
        }

        // 创建新的刷新任务
        refreshTask = Task {
            defer { refreshTask = nil }

            Logger.info("正在刷新人物的全部基本数据")
            isRefreshing = true
            lastError = nil
            let service = CharacterDataService.shared

            // 创建一个独立的任务来处理服务器状态，但不等待它完成
            Task.detached(priority: .background) {
                do {
                    Logger.info("正在刷新服务器状态")
                    let status = try await service.getServerStatus(forceRefresh: forceRefresh)
                    await MainActor.run {
                        self.serverStatus = status
                    }
                } catch {
                    await MainActor.run {
                        self.lastError = .serverStatusFailed
                        Logger.error("获取服务器状态失败: \(error)")
                    }
                }
            }

            // 如果有选中的角色，开始加载所有数据
            if let character = selectedCharacter {
                // 预加载角色技能数据
                SharedSkillsManager.shared.preloadSkills()

                // 优先加载头像 - 在后台线程执行
                if characterPortrait == nil {
                    Task.detached(priority: .userInitiated) {
                        await MainActor.run {
                            self.loadingState = .loadingPortrait
                        }
                        Logger.info("正在刷新人物头像")
                        if let portrait = try? await service.getCharacterPortrait(
                            id: character.CharacterID,
                            forceRefresh: forceRefresh
                        ) {
                            await MainActor.run {
                                self.characterPortrait = portrait
                                self.loadingState = .idle
                            }
                        } else {
                            await MainActor.run {
                                self.loadingState = .idle
                            }
                        }
                    }
                }

                // 加载角色公共信息及关联的军团/联盟/势力信息
                // 策略：先用缓存（哪怕过期）的 publicInfo 启动关联信息加载并刷新 UI，
                //       再拉取最新 publicInfo；若关联 ID 变化，用新 ID 重新加载并刷新。
                Task.detached(priority: .userInitiated) {
                    let cachedInfo = CharacterAPI.shared.loadCachedCharacterInfo(
                        characterId: character.CharacterID
                    )

                    // 1. 用缓存 ID 先加载关联信息并刷新 UI（失败不影响后续最新数据加载）
                    if let cached = cachedInfo {
                        do {
                            try await self.loadAffiliations(from: cached)
                        } catch {
                            Logger.error("用缓存加载关联信息失败: \(error)")
                        }
                    }

                    // 2. 拉取最新 publicInfo
                    do {
                        Logger.info("正在刷新人物公共信息")
                        let freshInfo = try await self.retryOperation(named: "获取角色公共信息") {
                            try await CharacterAPI.shared.fetchCharacterPublicInfo(
                                characterId: character.CharacterID, forceRefresh: forceRefresh
                            )
                        }

                        // 3. 若无缓存或关联 ID 变化，用新数据重新加载
                        let needsReload = cachedInfo == nil
                            || cachedInfo?.corporation_id != freshInfo.corporation_id
                            || cachedInfo?.alliance_id != freshInfo.alliance_id
                            || cachedInfo?.faction_id != freshInfo.faction_id

                        if needsReload {
                            try await self.loadAffiliations(from: freshInfo)
                        }
                    } catch {
                        Logger.error("获取角色公共信息失败: \(error)")
                    }
                }

                // 加载技能信息 - 在后台线程执行
                Task.detached(priority: .userInitiated) {
                    do {
                        Logger.info("正在刷新人物技能数据")
                        let (skillsResponse, queue) = try await self.retryOperation(named: "获取技能信息") {
                            try await service.getSkillInfo(
                                id: character.CharacterID, forceRefresh: forceRefresh
                            )
                        }
                        await MainActor.run {
                            self.processSkillInfo(skillsResponse: skillsResponse, queue: queue)
                        }
                    } catch {
                        Logger.error("获取技能信息失败: \(error)")
                    }
                }

                // 加载钱包余额 - 在后台线程执行
                Task.detached(priority: .userInitiated) {
                    do {
                        Logger.info("正在刷新钱包余额")
                        let balance = try await self.retryOperation(named: "获取钱包余额") {
                            try await service.getWalletBalance(
                                id: character.CharacterID, forceRefresh: forceRefresh
                            )
                        }
                        await MainActor.run {
                            self.cache.walletBalance = balance
                            self.updateWalletBalance(balance)
                        }
                    } catch {
                        Logger.error("获取钱包余额失败: \(error)")
                    }
                }

                // 加载位置信息 - 在后台线程执行
                Task.detached(priority: .userInitiated) {
                    do {
                        Logger.info("正在刷新人物位置信息")
                        let location = try await self.retryOperation(named: "获取位置信息") {
                            try await service.getLocation(
                                id: character.CharacterID, forceRefresh: forceRefresh
                            )
                        }
                        await MainActor.run {
                            self.characterStats.location = location.locationStatus.description
                        }
                    } catch {
                        Logger.error("获取位置信息失败: \(error)")
                    }
                }

                // 加载克隆状态 - 在后台线程执行
                Task.detached(priority: .userInitiated) {
                    do {
                        Logger.info("正在刷新人物克隆信息")
                        let cloneInfo = try await self.retryOperation(named: "获取克隆状态") {
                            try await service.getCloneStatus(
                                id: character.CharacterID, forceRefresh: forceRefresh
                            )
                        }
                        await MainActor.run {
                            self.updateCloneStatus(from: cloneInfo)
                        }
                    } catch {
                        Logger.error("获取克隆状态失败: \(error)")
                    }
                }
            }

            isRefreshing = false
            Logger.info("刷新基本信息完成")
            loadingState = .idle
        }

        await refreshTask?.value
    }

    /// 根据 publicInfo 并行加载军团/联盟/势力信息并刷新 UI。
    /// 军团 info+logo 与联盟 info+logo 全部并行（async let 声明即启动），势力为本地 SDE 查询（瞬时）。
    private func loadAffiliations(from publicInfo: CharacterPublicInfo) async throws {
        // 军团 info + logo（async let 声明即启动，与下方联盟任务并行）
        async let corpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
            corporationId: publicInfo.corporation_id
        )
        async let corpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
            corporationId: publicInfo.corporation_id
        )

        // 联盟 info + logo（与军团并行）
        let (alliInfo, alliLogo): (AllianceInfo?, UIImage?)
        if let allianceId = publicInfo.alliance_id {
            async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(
                allianceId: allianceId
            )
            async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(
                allianceID: allianceId
            )
            let (info, logo) = try await (allianceInfoTask, allianceLogoTask)
            alliInfo = info
            alliLogo = logo
        } else {
            alliInfo = nil
            alliLogo = nil
        }

        let (corpInfo, corpLogo) = try await (corpInfoTask, corpLogoTask)

        // 势力信息（本地 SDE，瞬时）
        let (factionInfo, factionLogo): (FactionInfo?, UIImage?)
        if let factionId = publicInfo.faction_id,
           let stored = SDEMemoryStore.faction(for: factionId)
        {
            factionInfo = stored
            factionLogo = IconManager.shared.loadUIImage(for: stored.iconName)
        } else {
            if let factionId = publicInfo.faction_id {
                Logger.error("查询势力信息失败: faction_id=\(factionId)")
            }
            factionInfo = nil
            factionLogo = nil
        }

        // 批量更新所有UI，减少重绘次数
        await MainActor.run {
            self.corporationInfo = corpInfo
            self.corporationLogo = corpLogo
            self.allianceInfo = alliInfo
            self.allianceLogo = alliLogo
            self.factionInfo = factionInfo
            self.factionLogo = factionLogo
        }
    }

    /// 加载保存的角色信息
    private func loadSavedCharacter() {
        Logger.info("正在加载保存的角色信息...")
        Logger.info("当前保存的所选角色ID: \(currentCharacterId)")

        if currentCharacterId != 0 {
            if let auth = EVELogin.shared.getCharacterByID(currentCharacterId) {
                selectedCharacter = auth.character
                Logger.success("成功加载保存的角色信息: \(auth.character.CharacterName)")
            } else {
                Logger.warning("找不到保存的角色（ID: \(currentCharacterId)），重置选择")
                resetCharacterInfo()
            }
        }
    }

    /// 重置角色信息
    func resetCharacterInfo() {
        characterStats = CharacterStats()
        selectedCharacter = nil
        characterPortrait = nil
        isRefreshing = false
        loadingState = .idle
        currentCharacterId = 0
        lastError = nil

        // 清除缓存的数据
        cache.clear()
        cachedCloneCooldownPeriod = nil
        lastCloneCooldownCalculation = nil
        cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Available", comment: "")
    }

    /// 从本地快速更新数据（缓存+数据库）
    func quickRefreshFromLocal() async {
        guard let character = selectedCharacter else { return }
        let service = CharacterDataService.shared

        // 并发执行所有请求，不强制刷新
        async let skillInfoTask = retryOperation(named: "快速获取技能信息") {
            try await service.getSkillInfo(id: character.CharacterID)
        }
        async let walletTask = retryOperation(named: "快速获取钱包余额") {
            try await service.getWalletBalance(id: character.CharacterID)
        }
        async let locationTask = retryOperation(named: "快速获取位置信息") {
            try await service.getLocation(id: character.CharacterID)
        }
        async let cloneTask = retryOperation(named: "快速获取克隆状态") {
            try await service.getCloneStatus(id: character.CharacterID)
        }

        do {
            // 处理技能信息
            let (skillsResponse, queue) = try await skillInfoTask
            processSkillInfo(skillsResponse: skillsResponse, queue: queue)

            // 处理钱包余额
            let balance = try await walletTask
            cache.walletBalance = balance
            updateWalletBalance(balance)

            // 处理位置信息
            let location = try await locationTask
            characterStats.location = location.locationStatus.description

            // 处理克隆状态
            let cloneInfo = try await cloneTask
            updateCloneStatus(from: cloneInfo)
        } catch {
            Logger.error("快速刷新数据失败: \(error)")
            // 快速刷新失败不设置错误状态，因为这是一个静默的后台操作
        }
    }
}
