import Foundation

/// 技能数据模型
public struct CharacterSkill: Codable, Sendable {
    public let active_skill_level: Int
    public let skill_id: Int
    public let skillpoints_in_skill: Int
    public let trained_skill_level: Int
}

public struct CharacterSkillsResponse: Codable, Sendable {
    public let skills: [CharacterSkill]
    public let total_sp: Int
    public let unallocated_sp: Int

    /// 技能ID到技能信息的映射，用于快速查找（O(1)时间复杂度）
    /// 此属性会被缓存到文件中，如果缓存文件中不存在则从 skills 数组自动创建
    public var skillsMap: [Int: CharacterSkill]

    private enum CodingKeys: String, CodingKey {
        case skills
        case total_sp
        case unallocated_sp
        case skillsMap
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = try container.decode([CharacterSkill].self, forKey: .skills)
        total_sp = try container.decode(Int.self, forKey: .total_sp)
        unallocated_sp = try container.decode(Int.self, forKey: .unallocated_sp)

        // 尝试从缓存文件中读取 skillsMap，如果不存在则从 skills 数组创建（向后兼容）
        if let cachedMap = try? container.decode([Int: CharacterSkill].self, forKey: .skillsMap) {
            skillsMap = cachedMap
        } else {
            // 从 skills 数组创建技能ID到技能信息的映射
            skillsMap = Dictionary(uniqueKeysWithValues: skills.map { ($0.skill_id, $0) })
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(skills, forKey: .skills)
        try container.encode(total_sp, forKey: .total_sp)
        try container.encode(unallocated_sp, forKey: .unallocated_sp)
        // 将 skillsMap 也编码到缓存文件中
        try container.encode(skillsMap, forKey: .skillsMap)
    }
}

struct CharacterAttributes: Codable, Sendable {
    let charisma: Int
    let intelligence: Int
    let memory: Int
    let perception: Int
    let willpower: Int
    let bonus_remaps: Int?
    let accrued_remap_cooldown_date: String?
    let last_remap_date: String?
}

private struct CharacterSkillsDiskBundle: Codable {
    var skills: CharacterSkillsResponse?
    var skillsAt: Date?
}

struct CharacterSkillQueueUpdate {
    static let notification = Notification.Name("CharacterSkillQueueDidUpdate")

    let characterID: Int
    let sample: CharacterSkillQueueSample
}

public actor CharacterSkillsAPI {
    public static let shared = CharacterSkillsAPI()
    private init() {}

    private static let cacheValiditySeconds: TimeInterval = 2 * 60 * 60

    private nonisolated func characterSkillsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CharacterSkills", isDirectory: true)
    }

    private nonisolated func privateBundleURL(for characterId: Int) -> URL {
        characterSkillsDirectory().appendingPathComponent("\(characterId)_skills.json")
    }

    /// Keep this check on scalar timestamps: Date's Comparable dispatch is on the
    /// zero-address crash path seen in the iOS 27.2 TestFlight reports.
    nonisolated func isCacheFileValid(at path: URL, now: Date = Date()) -> Bool {
        guard let modifiedAt = modificationDate(at: path) else { return false }
        return Self.isFresh(modifiedAt, at: now)
    }

    private nonisolated func modificationDate(at path: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path.path)
        return attributes?[.modificationDate] as? Date
    }

    private static func isFresh(_ stamp: Date, at now: Date = Date()) -> Bool {
        now.timeIntervalSinceReferenceDate <= stamp.timeIntervalSinceReferenceDate + cacheValiditySeconds
    }

    private nonisolated func loadDiskBundle(characterId: Int) -> CharacterSkillsDiskBundle? {
        return readDiskBundle(at: privateBundleURL(for: characterId))
    }

    private nonisolated func readDiskBundle(at path: URL) -> CharacterSkillsDiskBundle? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(CharacterSkillsDiskBundle.self, from: data)
    }

    private func saveDiskBundle(characterId: Int, bundle: CharacterSkillsDiskBundle) -> Bool {
        let path = privateBundleURL(for: characterId)
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            try encoder.encode(bundle).write(to: path, options: [
                .atomic, .completeFileProtectionUntilFirstUserAuthentication,
            ])
            return true
        } catch {
            Logger.error("保存合并技能缓存失败: \(error)")
            return false
        }
    }

    public nonisolated func loadSkillsFromCacheIfAvailable(characterId: Int) -> CharacterSkillsResponse? {
        guard let bundle = loadDiskBundle(characterId: characterId),
              let stamp = bundle.skillsAt, Self.isFresh(stamp)
        else { return nil }
        return bundle.skills
    }

    public nonisolated func loadSkillsAndQueueFromCacheIfAvailable(
        characterId: Int, allowExpired: Bool = false
    ) -> (skills: CharacterSkillsResponse, queue: [SkillQueueItem])? {
        guard let bundle = loadDiskBundle(characterId: characterId), let skills = bundle.skills,
              let skillsAt = bundle.skillsAt, let sample = WidgetStore.shared.skillQueue(for: characterId),
              allowExpired || (Self.isFresh(skillsAt) && Self.isFresh(sample.fetchedAt))
        else { return nil }
        return (skills, sample.queue)
    }

    func cachedSkillQueue(characterId: Int) -> CharacterSkillQueueSample? {
        WidgetStore.shared.skillQueue(for: characterId)?.relocalized(lookup: ItemInfoMap.typeName(for:))
    }

    private func fetchCharacterSkillsFromNetwork(characterId: Int) async throws -> CharacterSkillsResponse {
        let urlString = "https://esi.evetech.net/characters/\(characterId)/skills/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        do {
            return try JSONDecoder().decode(CharacterSkillsResponse.self, from: data)
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    public func fetchCharacterSkills(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterSkillsResponse
    {
        if !forceRefresh, let cachedSkills = loadSkillsFromCacheIfAvailable(characterId: characterId) {
            return cachedSkills
        }

        let skills = try await fetchCharacterSkillsFromNetwork(characterId: characterId)
        var bundle = loadDiskBundle(characterId: characterId) ?? CharacterSkillsDiskBundle()
        bundle.skills = skills
        bundle.skillsAt = Date()
        _ = saveDiskBundle(characterId: characterId, bundle: bundle)
        return skills
    }

    public func fetchCharacterSkillsAndQueue(
        characterId: Int,
        forceRefresh: Bool = false
    ) async throws -> (skills: CharacterSkillsResponse, queue: [SkillQueueItem]) {
        if !forceRefresh, let cached = loadSkillsAndQueueFromCacheIfAvailable(characterId: characterId) {
            return cached
        }

        async let skills = fetchCharacterSkills(characterId: characterId, forceRefresh: forceRefresh)
        async let queue = fetchSkillQueue(characterId: characterId, forceRefresh: forceRefresh)
        return try await (skills, queue)
    }

    public func fetchSkillQueue(
        characterId: Int, forceRefresh: Bool = false, scheduleReminder: Bool = true
    ) async throws -> [SkillQueueItem] {
        try await fetchSkillQueueSample(
            characterId: characterId, maxAge: Self.cacheValiditySeconds,
            forceRefresh: forceRefresh, scheduleReminder: scheduleReminder
        ).queue
    }

    func fetchSkillQueueSample(
        characterId: Int, maxAge: TimeInterval, forceRefresh: Bool = false,
        refreshAfterCompletion: Bool = false, scheduleReminder: Bool = false
    ) async throws -> CharacterSkillQueueSample {
        try Task.checkCancellation()
        let sample: CharacterSkillQueueSample
        do {
            sample = try await WidgetRepository.shared.skillQueue(for: characterId, maxAge: maxAge,
                                                                  force: forceRefresh, afterCompletion: refreshAfterCompletion).relocalized(lookup: ItemInfoMap.typeName(for:))
        } catch WidgetAuthorizationError.needsLogin {
            EVELogin.shared.updateCharacterRefreshTokenExpiredStatus(characterId: characterId, expired: true)
            throw NetworkError.refreshTokenExpired
        }
        try Task.checkCancellation()
        await Self.publishQueue(sample, characterId: characterId)
        if scheduleReminder {
            await scheduleSkillQueueReminder(characterId: characterId, queue: sample.queue)
        }
        return sample
    }

    @MainActor
    private static func publishQueue(
        _ sample: CharacterSkillQueueSample, characterId: Int
    ) {
        NotificationCenter.default.post(
            name: CharacterSkillQueueUpdate.notification,
            object: CharacterSkillQueueUpdate(characterID: characterId, sample: sample)
        )
        AppDataUpdate.skills(characterID: characterId, sample: sample).publish()
    }

    /// 根据最新队列安排技能到期提醒通知（角色名从 EVELogin 已登录列表中查找）
    private func scheduleSkillQueueReminder(characterId: Int, queue: [SkillQueueItem]) async {
        let characterName = EVELogin.shared.loadCharacters()
            .first(where: { $0.character.CharacterID == characterId })?
            .character.CharacterName
            ?? "\(characterId)"
        await NotificationManager.shared.scheduleSkillQueueNotifications(
            characterId: characterId,
            characterName: characterName,
            queue: queue
        )
    }

    private func getAttributesCacheFilePath(characterId: Int) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")

        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(
            at: characterSkillsPath, withIntermediateDirectories: true
        )

        return characterSkillsPath.appendingPathComponent("\(characterId)_attributes.json")
    }

    /// 保存角色属性到本地文件
    private func saveAttributesToCache(characterId: Int, attributes: CharacterAttributes) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(attributes)

            let filePath = getAttributesCacheFilePath(characterId: characterId)
            try jsonData.write(to: filePath)

            Logger.success("成功缓存角色属性到文件 - 角色ID: \(characterId), 路径: \(filePath.path)")
            return true
        } catch {
            Logger.error("保存角色属性到文件失败: \(error)")
            return false
        }
    }

    /// 从本地文件读取角色属性
    private func loadAttributesFromCache(characterId: Int) -> CharacterAttributes? {
        let filePath = getAttributesCacheFilePath(characterId: characterId)

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        // 检查文件修改时间，缓存1小时
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let cacheExpirationDate = modificationDate.addingTimeInterval(60 * 60) // 1小时
                if Date() > cacheExpirationDate {
                    Logger.debug("角色属性缓存已过期 - 角色ID: \(characterId)")
                    return nil
                }
            }
        } catch {
            Logger.error("获取文件属性失败: \(error)")
            return nil
        }

        do {
            let jsonData = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            let attributes = try decoder.decode(CharacterAttributes.self, from: jsonData)

            Logger.debug("从文件缓存加载角色属性 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return attributes
        } catch {
            Logger.error("从文件读取角色属性失败: \(error)")
            return nil
        }
    }

    /// 获取角色属性点
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新，默认为false
    /// - Returns: 角色属性数据
    func fetchAttributes(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterAttributes
    {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedAttributes = loadAttributesFromCache(characterId: characterId) {
                Logger.debug("从缓存加载角色属性 - 角色ID: \(characterId)")
                return cachedAttributes
            }
        }

        Logger.debug("从服务器获取角色属性 - 角色ID: \(characterId)")
        let url = URL(
            string:
            "https://esi.evetech.net/characters/\(characterId)/attributes/?datasource=tranquility"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(CharacterAttributes.self, from: data)

            // 保存到本地文件
            if saveAttributesToCache(characterId: characterId, attributes: response) {
                Logger.success("成功缓存角色属性到文件")
            }

            return response
        } catch {
            Logger.error("解析角色属性数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
}
