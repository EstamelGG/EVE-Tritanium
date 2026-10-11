@preconcurrency import AppAuth
import BackgroundTasks
import Foundation
import Security
import SwiftUI

// 导入技能队列数据模型
// typealias SkillQueueItem = EVE_Nexus.SkillQueueItem

struct EVECharacterInfo: Codable {
    let CharacterID: Int
    let CharacterName: String
    let ExpiresOn: String
    let Scopes: String
    let TokenType: String
    let CharacterOwnerHash: String
    var corporationId: Int?
    var allianceId: Int?
    var factionId: Int?
    var refreshTokenExpired: Bool = false

    // 动态属性
    var totalSkillPoints: Int?
    var unallocatedSkillPoints: Int?
    var walletBalance: Double?
    var skillQueueLength: Int?
    var currentSkill: CurrentSkillInfo?
    var locationStatus: CharacterLocation.LocationStatus?
    var location: SolarSystemInfo?
    var queueFinishTime: TimeInterval? // 添加队列总剩余时间属性

    /// 为JWT令牌解析添加的初始化方法
    init(
        CharacterID: Int, CharacterName: String, ExpiresOn: String, Scopes: String,
        TokenType: String, CharacterOwnerHash: String
    ) {
        self.CharacterID = CharacterID
        self.CharacterName = CharacterName
        self.ExpiresOn = ExpiresOn
        self.Scopes = Scopes
        self.TokenType = TokenType
        self.CharacterOwnerHash = CharacterOwnerHash
        refreshTokenExpired = false
    }

    /// 内部类型定义
    struct CurrentSkillInfo: Codable {
        let skillId: Int
        let name: String
        let level: String
        let progress: Double
        let remainingTime: TimeInterval?
    }

    enum CodingKeys: String, CodingKey {
        case CharacterID
        case CharacterName
        case ExpiresOn
        case Scopes
        case TokenType
        case CharacterOwnerHash
        case totalSkillPoints
        case unallocatedSkillPoints
        case walletBalance
        case location
        case locationStatus
        case currentSkill
        case refreshTokenExpired
        case corporationId
        case allianceId
        case factionId
        case skillQueueLength
        case queueFinishTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        CharacterID = try container.decode(Int.self, forKey: .CharacterID)
        CharacterName = try container.decode(String.self, forKey: .CharacterName)
        ExpiresOn = try container.decode(String.self, forKey: .ExpiresOn)
        Scopes = try container.decode(String.self, forKey: .Scopes)
        TokenType = try container.decode(String.self, forKey: .TokenType)
        CharacterOwnerHash = try container.decode(String.self, forKey: .CharacterOwnerHash)
        totalSkillPoints = try container.decodeIfPresent(Int.self, forKey: .totalSkillPoints)
        unallocatedSkillPoints = try container.decodeIfPresent(
            Int.self, forKey: .unallocatedSkillPoints
        )
        walletBalance = try container.decodeIfPresent(Double.self, forKey: .walletBalance)
        location = try container.decodeIfPresent(SolarSystemInfo.self, forKey: .location)
        locationStatus = try container.decodeIfPresent(
            CharacterLocation.LocationStatus.self, forKey: .locationStatus
        )
        currentSkill = try container.decodeIfPresent(CurrentSkillInfo.self, forKey: .currentSkill)
        refreshTokenExpired =
            try container.decodeIfPresent(Bool.self, forKey: .refreshTokenExpired) ?? false
        corporationId = try container.decodeIfPresent(Int.self, forKey: .corporationId)
        allianceId = try container.decodeIfPresent(Int.self, forKey: .allianceId)
        factionId = try container.decodeIfPresent(Int.self, forKey: .factionId)
        skillQueueLength = try container.decodeIfPresent(Int.self, forKey: .skillQueueLength)
        queueFinishTime = try container.decodeIfPresent(TimeInterval.self, forKey: .queueFinishTime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CharacterID, forKey: .CharacterID)
        try container.encode(CharacterName, forKey: .CharacterName)
        try container.encode(ExpiresOn, forKey: .ExpiresOn)
        try container.encode(Scopes, forKey: .Scopes)
        try container.encode(TokenType, forKey: .TokenType)
        try container.encode(CharacterOwnerHash, forKey: .CharacterOwnerHash)
        try container.encodeIfPresent(totalSkillPoints, forKey: .totalSkillPoints)
        try container.encodeIfPresent(unallocatedSkillPoints, forKey: .unallocatedSkillPoints)
        try container.encodeIfPresent(walletBalance, forKey: .walletBalance)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(locationStatus, forKey: .locationStatus)
        try container.encodeIfPresent(currentSkill, forKey: .currentSkill)
        try container.encode(refreshTokenExpired, forKey: .refreshTokenExpired)
        try container.encodeIfPresent(corporationId, forKey: .corporationId)
        try container.encodeIfPresent(allianceId, forKey: .allianceId)
        try container.encodeIfPresent(factionId, forKey: .factionId)
        try container.encodeIfPresent(skillQueueLength, forKey: .skillQueueLength)
        try container.encodeIfPresent(queueFinishTime, forKey: .queueFinishTime)
    }
}

/// 添加Equatable协议支持
extension EVECharacterInfo: Equatable {
    static func == (lhs: EVECharacterInfo, rhs: EVECharacterInfo) -> Bool {
        return lhs.CharacterID == rhs.CharacterID
    }
}

/// ESI配置模型
struct ESIConfig: Codable {
    let clientId: String
    //    let clientSecret: String
    //    let callbackUrl: String
    var urls: ESIUrls
    var scopes: [String]

    struct ESIUrls: Codable {
        ///        let authorize: String
        ///        let token: String
        /// 添加JWT元数据端点
        let jwksMetadata: String?

        enum CodingKeys: String, CodingKey {
            case jwksMetadata
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            jwksMetadata = try container.decodeIfPresent(String.self, forKey: .jwksMetadata)
        }

        init(jwksMetadata: String? = nil) {
            self.jwksMetadata = jwksMetadata
        }
    }
}

/// 添加角色管理相关的数据结构
struct CharacterAuth: Codable {
    var character: EVECharacterInfo
    let addedDate: Date
    let lastTokenUpdateTime: Date
}

/// 添加用户管理的 ViewModel
@MainActor
class EVELoginViewModel: ObservableObject {
    @Published var characterInfo: EVECharacterInfo?
    // @Published var isLoggedIn: Bool = false
    @Published var showingError: Bool = false
    @Published var errorMessage: String = ""
    @Published var characters: [EVECharacterInfo] = []
    @Published var characterPortraits: [Int: UIImage] = [:]
    let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager = DatabaseManager()) {
        self.databaseManager = databaseManager
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCharacterDetailsUpdate(_:)),
            name: Notification.Name("CharacterDetailsUpdated"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleCharacterDetailsUpdate(_ notification: Notification) {
        Task { @MainActor in
            if let updatedCharacter = notification.userInfo?["character"] as? EVECharacterInfo {
                if let index = characters.firstIndex(where: {
                    $0.CharacterID == updatedCharacter.CharacterID
                }) {
                    characters[index] = updatedCharacter
                }
                if characterInfo?.CharacterID == updatedCharacter.CharacterID {
                    characterInfo = updatedCharacter
                }
            }
        }
    }

    func loadCharacterPortrait(characterId: Int, forceRefresh: Bool = false) async {
        do {
            if !forceRefresh, characterPortraits[characterId] != nil {
                return
            }

            let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            await MainActor.run {
                characterPortraits[characterId] = portrait
            }
        } catch {
            Logger.error("加载角色头像失败: \(error)")
        }
    }

    func loadCharacters(onLoaded: (@MainActor () -> Void)? = nil) {
        Task { @MainActor in
            let allCharacters = EVELogin.shared.loadCharacters()
            let newCharacters = allCharacters.map { $0.character }

            // 原子性更新角色列表
            characters = newCharacters
            onLoaded?()

            Logger.info("已加载 \(characters.count) 个角色")

            // 异步加载头像
            Task {
                for character in newCharacters {
                    // 检查视图是否仍然存在
                    guard
                        await MainActor.run(body: {
                            self.characters.contains { $0.CharacterID == character.CharacterID }
                        })
                    else {
                        continue
                    }

                    await self.loadCharacterPortrait(characterId: character.CharacterID)
                }
            }
        }
    }

    /// 移除角色
    func removeCharacter(_ character: EVECharacterInfo) {
        let characterId = character.CharacterID
        Logger.info("开始移除角色: \(character.CharacterName) (\(characterId))")

        // 1. 先从本地数组中移除，避免UI闪烁
        characters.removeAll { $0.CharacterID == characterId }

        // 2. 移除头像缓存
        characterPortraits.removeValue(forKey: characterId)

        // 3. 如果移除的是当前选中的角色，清除选中状态
        if characterInfo?.CharacterID == characterId {
            characterInfo = nil
        }

        // 4. 异步清理持久化数据，避免阻塞UI
        Task.detached {
            // 清理持久化存储
            EVELogin.shared.removeCharacter(characterId: characterId)

            // 重新验证本地状态与持久化状态的一致性
            await MainActor.run {
                let persistedCharacters = EVELogin.shared.loadCharacters()
                let persistedIds = Set(persistedCharacters.map { $0.character.CharacterID })
                let localIds = Set(self.characters.map { $0.CharacterID })

                // 如果发现不一致，重新加载
                if persistedIds != localIds {
                    Logger.warning("检测到本地与持久化状态不一致，重新加载角色列表")
                    self.loadCharacters()
                }
            }
        }

        Logger.info("角色移除完成: \(character.CharacterName) (\(characterId))")
    }

    /// 更新角色顺序
    func moveCharacter(from source: IndexSet, to destination: Int) {
        // 边界检查
        guard destination >= 0, destination <= characters.count else {
            Logger.warning("移动目标位置 \(destination) 超出有效范围 [0, \(characters.count)]")
            return
        }

        // 检查源索引是否有效
        for index in source {
            guard index < characters.count else {
                Logger.warning("源索引 \(index) 超出数组范围 \(characters.count)")
                return
            }
        }

        characters.move(fromOffsets: source, toOffset: destination)
        let characterIds = characters.map { $0.CharacterID }
        EVELogin.shared.saveCharacterOrder(characterIds)
    }

    // MARK: - 基于角色ID的安全更新方法

    /// 通过角色ID查找角色在数组中的索引
    private func findCharacterIndex(by characterId: Int) -> Int? {
        return characters.firstIndex { $0.CharacterID == characterId }
    }

    /// 安全地更新角色信息
    func updateCharacter(characterId: Int, updateBlock: (inout EVECharacterInfo) -> Void) {
        guard let index = findCharacterIndex(by: characterId) else {
            Logger.warning("未找到角色ID \(characterId) 对应的角色")
            return
        }

        // 确保索引仍然有效（防止在查找和使用之间数组被修改）
        guard index < characters.count else {
            Logger.warning("角色索引 \(index) 超出数组范围 \(characters.count)")
            return
        }

        updateBlock(&characters[index])

        // 如果是当前选中的角色，也更新 characterInfo
        if characterInfo?.CharacterID == characterId {
            characterInfo = characters[index]
        }
    }

    /// 获取角色信息的只读副本
    func getCharacter(by characterId: Int) -> EVECharacterInfo? {
        return characters.first { $0.CharacterID == characterId }
    }
}

class EVELogin {
    static let shared = EVELogin()
    var config: ESIConfig?
    private var session: URLSession!
    private let charactersKey = "EVECharacters"
    private let characterOrderKey = "EVECharacterOrder"
    private let databaseManager: DatabaseManager

    private static let defaultConfig = ESIConfig(
        clientId: EVEConfig.OAuth.clientId,
        //        clientSecret: EVEConfig.OAuth.clientSecret,
        //        callbackUrl: EVEConfig.OAuth.redirectURI.absoluteString,
        urls: ESIConfig.ESIUrls(
            //            authorize: EVEConfig.OAuth.authorizationEndpoint.absoluteString,
            //            token: EVEConfig.OAuth.tokenEndpoint.absoluteString,
            jwksMetadata: EVEConfig.OAuth.jwksMetadataEndpoint.absoluteString
        ),
        scopes: [] // 将在 loadConfig 中填充
    )

    private init() {
        session = URLSession.shared
        databaseManager = DatabaseManager()
        loadConfig()
    }

    /// 主处理函数 - 基本认证
    func processLogin(authState: OIDAuthState) async throws -> EVECharacterInfo {
        Logger.info("开始处理登录流程...")

        // 1. 获取角色信息
        var character = try await getCharacterInfo(
            token: authState.lastTokenResponse?.accessToken ?? "",
            forceRefresh: true
        )
        Logger.info(
            "成功获取角色信息 - 名称: \(character.CharacterName), ID: \(character.CharacterID)"
        )

        // 2. 先写入新的 refresh/access，再清过期标记，避免并发 getAccessToken 仍用旧 refresh。
        await AuthTokenManager.shared.saveAuthState(authState, for: character.CharacterID)

        // 3. 清掉可能残留的 refreshTokenExpired（例如上次 invalid_grant）。
        updateCharacterRefreshTokenExpiredStatus(
            characterId: character.CharacterID, expired: false
        )
        character.refreshTokenExpired = false
        try await saveCharacterInfo(character)

        // 4. 加载详细信息
        return try await loadDetailedInfo(character: character)
    }

    /// 保存角色信息
    func saveCharacterInfo(_ character: EVECharacterInfo) async throws {
        Logger.info(
            "开始保存角色信息 - 角色: \(character.CharacterName) (\(character.CharacterID))"
        )

        var characters = loadCharacters()
        var isNewCharacter = false

        // 检查是否已存在该角色
        if let index = characters.firstIndex(where: {
            $0.character.CharacterID == character.CharacterID
        }) {
            // 保持原有的 addedDate
            let originalAddedDate = characters[index].addedDate
            characters[index] = CharacterAuth(
                character: character,
                addedDate: originalAddedDate,
                lastTokenUpdateTime: Date()
            )
            Logger.info("更新现有角色信息")
        } else {
            characters.append(
                CharacterAuth(
                    character: character,
                    addedDate: Date(),
                    lastTokenUpdateTime: Date()
                )
            )
            isNewCharacter = true
            Logger.info("添加新角色信息")
        }

        // 保存到 UserDefaults
        if let encodedData = try? JSONEncoder().encode(characters) {
            Logger.info(
                "正在缓存个人信息数据, key: \(charactersKey), 数据大小: \(encodedData.count) bytes"
            )
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
        }

        // 如果是新角色，更新角色顺序
        if isNewCharacter {
            // 获取现有的角色顺序
            var characterOrder =
                UserDefaults.standard.array(forKey: characterOrderKey) as? [Int] ?? []
            // 将新角色添加到顺序列表末尾
            characterOrder.append(character.CharacterID)
            // 保存更新后的顺序
            Logger.info(
                "正在缓存角色顺序数据, key: \(characterOrderKey), 数据大小: \(characterOrder.count) bytes"
            )
            UserDefaults.standard.set(characterOrder, forKey: characterOrderKey)
        }
    }

    /// 加载详细信息
    private func loadDetailedInfo(character: EVECharacterInfo) async throws -> EVECharacterInfo {
        // 获取角色详细信息
        let (skills, balance, location, skillQueue) = try await fetchCharacterDetails(
            characterId: character.CharacterID
        )

        // 获取位置详细信息
        let locationInfo = await getSolarSystemInfo(
            solarSystemId: location.solar_system_id,
            databaseManager: databaseManager
        )

        // 更新角色信息
        var updatedCharacter = character
        updatedCharacter.totalSkillPoints = skills.total_sp
        updatedCharacter.unallocatedSkillPoints = skills.unallocated_sp
        updatedCharacter.walletBalance = balance
        updatedCharacter.location = locationInfo
        updatedCharacter.locationStatus = location.locationStatus
        updatedCharacter.skillQueueLength = skillQueue.count

        // 更新技能队列信息
        if let trainingSkill = skillQueue.first(where: { $0.isCurrentlyTraining }),
           let skillName = SkillTreeManager.shared.getSkillName(for: trainingSkill.skill_id)
        {
            updatedCharacter.currentSkill = EVECharacterInfo.CurrentSkillInfo(
                skillId: trainingSkill.skill_id,
                name: skillName,
                level: trainingSkill.skillLevel,
                progress: trainingSkill.progress,
                remainingTime: trainingSkill.remainingTime
            )

            if let lastSkill = skillQueue.last,
               let finishTime = lastSkill.remainingTime
            {
                updatedCharacter.queueFinishTime = finishTime
            }
        }

        // 保存更新后的信息
        try await saveCharacterInfo(updatedCharacter)

        Logger.info("详细信息加载完成")
        return updatedCharacter
    }

    /// 获取角色信息
    private func getCharacterInfo(token: String, forceRefresh: Bool) async throws
        -> EVECharacterInfo
    {
        // 解析JWT令牌
        if let characterInfo = JWTTokenValidator.shared.parseToken(token) {
            Logger.info("从JWT令牌成功解析角色信息 - 角色名: \(characterInfo.CharacterName)")

            // 获取角色的公开信息以更新军团和联盟ID
            let publicInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: characterInfo.CharacterID,
                forceRefresh: forceRefresh
            )

            var updatedCharacterInfo = characterInfo
            updatedCharacterInfo.corporationId = publicInfo.corporation_id
            updatedCharacterInfo.allianceId = publicInfo.alliance_id
            updatedCharacterInfo.factionId = publicInfo.faction_id

            return updatedCharacterInfo
        }

        // 如果JWT解析失败
        Logger.error("无法解析JWT令牌，请确保使用的是v2版本的OAuth端点")
        throw NetworkError.authenticationError("无法解析JWT令牌，请确保使用的是v2版本的OAuth端点")
    }

    /// 加载保存的角色列表
    func loadCharacters() -> [CharacterAuth] {
        guard let data = UserDefaults.standard.data(forKey: charactersKey) else {
            return []
        }

        do {
            var characters = try JSONDecoder().decode([CharacterAuth].self, from: data)

            // 获取保存的顺序
            if let savedOrder = UserDefaults.standard.array(forKey: characterOrderKey) as? [Int] {
                // 创建一个字典，用于快速查找角色
                let characterDict = Dictionary(
                    uniqueKeysWithValues: characters.map { ($0.character.CharacterID, $0) }
                )

                // 按保存的顺序重新排列角色
                characters = savedOrder.compactMap { characterDict[$0] }

                // 添加可能存在的新角色（不在已保存顺序中的角色）
                let savedCharacterIds = Set(savedOrder)
                let unsortedCharacters = characters.filter {
                    !savedCharacterIds.contains($0.character.CharacterID)
                }
                characters.append(contentsOf: unsortedCharacters)
            }

            return characters
        } catch {
            Logger.error("加载角色信息失败: \(error)")
            return []
        }
    }

    /// 移除角色
    func removeCharacter(characterId: Int) {
        Logger.info("开始移除角色 (ID: \(characterId))")

        // 1. 从 UserDefaults 中移除角色信息
        var characters = loadCharacters()
        characters.removeAll { $0.character.CharacterID == characterId }

        if let encodedData = try? JSONEncoder().encode(characters) {
            Logger.info("正在更新角色列表缓存, key: \(charactersKey)")
            UserDefaults.standard.set(encodedData, forKey: charactersKey)
        }

        // 2. 从角色顺序列表中移除
        var characterOrder = UserDefaults.standard.array(forKey: characterOrderKey) as? [Int] ?? []
        characterOrder.removeAll { $0 == characterId }
        Logger.info("正在更新角色顺序缓存, key: \(characterOrderKey)")
        UserDefaults.standard.set(characterOrder, forKey: characterOrderKey)

        // 3. 清除 AuthTokenManager 中的缓存
        Task {
            await AuthTokenManager.shared.clearAllTokens(for: characterId)
        }

        // 4. 清理 CharacterDatabase 中的相关数据
        Task {
            do {
                try await CharacterDatabaseManager.shared.deleteCharacterData(
                    characterId: characterId
                )
                Logger.info("已清理角色 \(characterId) 在数据库中的所有数据")
            } catch {
                Logger.error("清理角色 \(characterId) 的数据库数据失败: \(error)")
            }
        }

        // 5. 取消该角色的技能队列到期提醒
        NotificationManager.shared.cancelSkillQueueNotifications(characterId: characterId)

        UserDefaults.standard.synchronize()
        Logger.info("角色移除完成 (ID: \(characterId))")
    }

    /// 保存角色顺序
    func saveCharacterOrder(_ characterIds: [Int]) {
        // 使用 OrderedSet 去除重复的角色ID，保持原有顺序
        var uniqueCharacterIds: [Int] = []
        var seenCharacterIds = Set<Int>()

        for characterId in characterIds {
            if !seenCharacterIds.contains(characterId) {
                uniqueCharacterIds.append(characterId)
                seenCharacterIds.insert(characterId)
            } else {
                Logger.warning("发现重复的角色ID在顺序列表中，已忽略: \(characterId)")
            }
        }

        Logger.info(
            "正在缓存角色顺序数据, key: \(characterOrderKey), 数据大小: \(uniqueCharacterIds.count) bytes"
        )
        UserDefaults.standard.set(uniqueCharacterIds, forKey: characterOrderKey)
        UserDefaults.standard.synchronize()
    }

    /// 获取指定ID的角色
    func getCharacterByID(_ characterId: Int) -> CharacterAuth? {
        return loadCharacters().first { $0.character.CharacterID == characterId }
    }

    /// 获取角色详细信息
    func fetchCharacterDetails(characterId: Int) async throws -> (
        skills: CharacterSkillsResponse, balance: Double, location: CharacterLocation,
        skillQueue: [SkillQueueItem]
    ) {
        Logger.info("EVELogin: 开始获取角色详细信息...")

        async let skills = CharacterSkillsAPI.shared.fetchCharacterSkills(
            characterId: characterId
        )

        async let balance = CharacterWalletAPI.shared.getWalletBalance(
            characterId: characterId
        )

        async let location = CharacterLocationAPI.shared.fetchCharacterLocation(
            characterId: characterId
        )

        async let skillQueue = CharacterSkillsAPI.shared.fetchSkillQueue(
            characterId: characterId
        )

        do {
            let (skillsResult, balanceResult, locationResult, queueResult) = try await (
                skills, balance, location, skillQueue
            )
            Logger.info("成功获取所有角色详细信息")
            return (skillsResult, balanceResult, locationResult, queueResult)
        } catch {
            Logger.error("获取角色详细信息失败: \(error)")
            throw error
        }
    }

    private func loadConfig() {
        // 初始化基本配置
        var configWithScopes = EVELogin.defaultConfig
        configWithScopes.scopes = []

        // 更新jwksMetadata配置
        configWithScopes.urls = ESIConfig.ESIUrls(
            jwksMetadata: EVEConfig.OAuth.jwksMetadataEndpoint.absoluteString
        )

        config = configWithScopes

        // 异步加载 scopes
        Task {
            let scopes = await ScopeManager.shared.getLatestScopes()
            await MainActor.run {
                self.config?.scopes = scopes
            }
        }
    }

    /// 更新角色的 refreshTokenExpired 状态
    func updateCharacterRefreshTokenExpiredStatus(characterId: Int, expired: Bool) {
        var characters = loadCharacters()
        if let index = characters.firstIndex(where: { $0.character.CharacterID == characterId }) {
            var updatedCharacter = characters[index].character
            if updatedCharacter.refreshTokenExpired != expired {
                Logger.info(
                    "将人物 \(characterId) 的 refresh token 过期状态从 \(updatedCharacter.refreshTokenExpired) 改为 \(expired)"
                )
                updatedCharacter.refreshTokenExpired = expired
                characters[index] = CharacterAuth(
                    character: updatedCharacter, addedDate: characters[index].addedDate,
                    lastTokenUpdateTime: Date()
                )

                // 保存更新后的角色信息
                if let encodedData = try? JSONEncoder().encode(characters) {
                    UserDefaults.standard.set(encodedData, forKey: charactersKey)
                }

                // 发送通知以更新UI（必须在主线程执行）
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("CharacterDetailsUpdated"),
                        object: nil,
                        userInfo: ["character": updatedCharacter]
                    )
                }
            } else {
                Logger.info(
                    "人物 \(characterId) 的 refresh token 过期状态为 \(updatedCharacter.refreshTokenExpired), 无需更改"
                )
            }
        }
    }

    /// 添加 getScopes 方法到类内部
    func getScopes() async -> [String] {
        let scopes = await ScopeManager.shared.getLatestScopes()
        // 更新配置中的 scopes
        await MainActor.run {
            self.config?.scopes = scopes
        }
        return scopes
    }
}

/// 添加 ScopeManager 类
class ScopeManager {
    static let shared = ScopeManager()
    private let latestScopesFileName = "latest_scopes.json"
    private let hardcodedScopesFileName = "scopes.json"

    private init() {}

    /// 定义 scopes 获取来源枚举
    enum ScopeSource {
        case network
        case localCache
        case hardcoded
    }

    /// 定义返回结果结构
    struct ScopeResult {
        let scopes: [String]
        let source: ScopeSource
    }

    /// 获取文档目录路径
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 获取最新 scopes 文件路径
    private var latestScopesPath: URL {
        documentsDirectory.appendingPathComponent(latestScopesFileName)
    }

    /// 从本地文件加载 scopes
    private func loadScopesFromFile(_ url: URL) -> [String]? {
        do {
            let data = try Data(contentsOf: url)
            let scopesDict = try JSONDecoder().decode([String: [String]].self, from: data)
            Logger.info("从文件加载 scopes 成功: \(url)")
            return Array(Set(scopesDict.values.flatMap { $0 }))
        } catch {
            Logger.error("从文件加载 scopes 失败: \(error)")
            return nil
        }
    }

    /// 保存 scopes 到本地文件
    private func saveScopesToFile(_ scopes: [String]) {
        do {
            // 对 scopes 数组进行排序
            let sortedScopes = scopes.sorted()
            let scopesDict = ["scopes": sortedScopes]
            let data = try JSONEncoder().encode(scopesDict)
            try data.write(to: latestScopesPath)
            Logger.info("成功保存 scopes 到本地文件，共 \(sortedScopes.count) 个权限")
        } catch {
            Logger.error("保存 scopes 到本地文件失败: \(error)")
        }
    }

    /// 读取打包内的 scopes 配置
    private func readBundledScopesConfig() -> (registered: Set<String>, notRequired: Set<String>)? {
        guard
            let scopesURL = Bundle.main.url(
                forResource: hardcodedScopesFileName, withExtension: nil
            ),
            let data = try? Data(contentsOf: scopesURL),
            let scopesDict = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return nil
        }

        let registered = Set(scopesDict["registeredScopes"] ?? [])
        let notRequired = Set(scopesDict["notRequiredScopes"] ?? [])
        return (registered: registered, notRequired: notRequired)
    }

    /// 从 api 获取最新的 scopes（与 registeredScopes 取交集后，剔除 notRequiredScopes）
    func fetchLatestScopes() async throws -> [String] {
        guard let url = URL(string: "https://esi.evetech.net/meta/openapi.json") else {
            throw NetworkError.invalidURL
        }

        // 使用NetworkManager实现超时重试机制
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "GET",
            headers: ["Accept": "application/json"],
            noRetryKeywords: nil,
            timeouts: [10, 20, 30]
        )

        let openapi = try JSONDecoder().decode(OpenAPIResponse.self, from: data)

        // 从 components.securitySchemes.OAuth2.flows.authorizationCode.scopes 中提取所有的 scope keys
        let allScopes = Set(
            openapi.components.securitySchemes.oauth2.flows.authorizationCode.scopes.keys.map {
                String($0)
            }
        )

        // 从本地打包文件读取配置
        let config =
            readBundledScopesConfig() ?? (registered: Set<String>(), notRequired: Set<String>())

        // 计算：最新(全量) ∩ registeredScopes，再剔除 notRequiredScopes
        let intersected = allScopes.intersection(config.registered)
        let finalScopes = intersected.subtracting(config.notRequired)

        // 保存过滤后的 scopes 到本地文件
        saveScopesToFile(Array(finalScopes))

        Logger.info(
            "成功从网络获取最新scopes，原始: \(allScopes.count)，交集后: \(intersected.count)，剔除不需要后: \(finalScopes.count)"
        )

        return Array(finalScopes)
    }

    /// 获取 scopes 并返回来源信息
    func getLatestScopesWithSource(forceRefresh: Bool = false) async -> ScopeResult {
        // 检查是否需要刷新
        var shouldRefresh = forceRefresh

        if !shouldRefresh && FileManager.default.fileExists(atPath: latestScopesPath.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: latestScopesPath.path
                )
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let timeInterval = Date().timeIntervalSince(modificationDate)
                    let days = Int(timeInterval) / (24 * 3600)
                    let remainingDays = 7 - days
                    shouldRefresh = timeInterval >= 7 * 24 * 3600

                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    let lastUpdateStr = dateFormatter.string(from: modificationDate)

                    Logger.info(
                        """
                        Scopes 文件状态:
                        - 最后更新时间: \(lastUpdateStr)
                        - 已过去天数: \(days) 天
                        - 剩余有效期: \(remainingDays) 天
                        - 是否需要刷新: \(shouldRefresh ? "是" : "否")
                        """
                    )
                }
            } catch {
                Logger.error("检查 latest_scopes.json 文件属性失败: \(error)")
                shouldRefresh = true
            }
        } else if !shouldRefresh {
            Logger.info("latest_scopes.json 文件不存在，需要创建")
            shouldRefresh = true
        }

        // 如果需要刷新，尝试从网络获取
        if shouldRefresh {
            do {
                Logger.info("尝试从网络获取最新 scopes")
                let scopes = try await fetchLatestScopes()
                return ScopeResult(scopes: scopes, source: .network)
            } catch {
                Logger.error("从网络获取 scopes 失败: \(error)，尝试使用本地文件")
            }
        }

        // 尝试从本地文件加载
        if let scopes = loadScopesFromFile(latestScopesPath) {
            Logger.info("从本地文件加载 scopes 成功")
            // 再次应用规则：与 registered 取交集，并剔除 notRequired
            let config =
                readBundledScopesConfig() ?? (registered: Set<String>(), notRequired: Set<String>())
            let currentSet = Set(scopes)
            let intersected =
                config.registered.isEmpty ? currentSet : currentSet.intersection(config.registered)
            let finalSet = intersected.subtracting(config.notRequired)
            if scopes.count != finalSet.count {
                Logger.info(
                    "对本地 scopes 应用交集与剔除过滤，原始: \(scopes.count)，交集后: \(intersected.count)，剔除后: \(finalSet.count)"
                )
            }
            return ScopeResult(scopes: Array(finalSet), source: .localCache)
        }

        // 如果本地文件加载失败，使用硬编码的 scopes
        Logger.info("从本地文件加载失败，使用硬编码的 scopes")
        let scopes = loadHardcodedScopes() ?? []
        return ScopeResult(scopes: scopes, source: .hardcoded)
    }

    /// 获取 scopes（保持原有方法的兼容性）
    func getLatestScopes(forceRefresh: Bool = false) async -> [String] {
        let result = await getLatestScopesWithSource(forceRefresh: forceRefresh)
        return result.scopes
    }

    /// 从硬编码的 scopes.json 加载：registeredScopes 与 notRequiredScopes 计算后返回
    private func loadHardcodedScopes() -> [String]? {
        guard let config = readBundledScopesConfig() else { return nil }

        // 兜底：registeredScopes − notRequiredScopes
        let finalScopes = config.registered.subtracting(config.notRequired)
        Logger.info(
            "从硬编码文件加载 scopes 成功（registered − notRequired），共 \(finalScopes.count) 个权限"
        )
        return Array(finalScopes)
    }
}

/// 添加 OpenAPIResponse 结构体
private struct OpenAPIResponse: Codable {
    let components: Components

    struct Components: Codable {
        let securitySchemes: SecuritySchemes

        struct SecuritySchemes: Codable {
            let oauth2: OAuth2

            private enum CodingKeys: String, CodingKey {
                case oauth2 = "OAuth2"
            }

            struct OAuth2: Codable {
                let flows: Flows

                struct Flows: Codable {
                    let authorizationCode: AuthorizationCode

                    struct AuthorizationCode: Codable {
                        let scopes: [String: String]
                    }
                }
            }
        }
    }
}
