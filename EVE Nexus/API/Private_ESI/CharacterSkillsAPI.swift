import Foundation

/// 技能数据模型
public struct CharacterSkill: Codable {
    public let active_skill_level: Int
    public let skill_id: Int
    public let skillpoints_in_skill: Int
    public let trained_skill_level: Int
}

public struct CharacterSkillsResponse: Codable {
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

/// 技能队列项目
public struct SkillQueueItem: Codable, Identifiable, Equatable {
    public let queue_position: Int
    public let skill_id: Int
    public let finished_level: Int
    public let training_start_sp: Int?
    public let level_end_sp: Int?
    public let level_start_sp: Int?
    public let start_date: Date?
    public let finish_date: Date?

    public var id: Int {
        queue_position
    }

    public var isCurrentlyTraining: Bool {
        guard let startDate = start_date,
              let finishDate = finish_date
        else {
            return false
        }
        let now = Date()
        return now >= startDate && now <= finishDate
    }

    public var remainingTime: TimeInterval? {
        guard let finishDate = finish_date else {
            return nil
        }
        return finishDate.timeIntervalSinceNow
    }

    /// 获取技能等级的罗马数字表示
    public var skillLevel: String {
        let romanNumerals = ["I", "II", "III", "IV", "V"]
        return romanNumerals[finished_level - 1]
    }

    /// 计算训练进度
    public var progress: Double {
        progress(at: Date())
    }

    public func progress(at now: Date) -> Double {
        guard let startDate = start_date,
              let finishDate = finish_date,
              let trainingStartSp = training_start_sp,
              let levelEndSp = level_end_sp,
              let levelStartSp = level_start_sp
        else {
            return 0
        }

        // 如果还没开始训练，进度为0
        if now < startDate {
            return 0
        }

        // 如果已经完成训练，进度为1
        if now > finishDate {
            return 1
        }

        // 正在训练中：使用基于时间的进度计算
        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
        guard totalTrainingTime > 0, levelEndSp > levelStartSp else { return 0 }
        let trainedTime = now.timeIntervalSince(startDate)
        let timeProgress = trainedTime / totalTrainingTime

        // 计算剩余需要训练的技能点
        let remainingSP = levelEndSp - trainingStartSp

        // 计算当前已训练的技能点
        let trainedSP = Double(remainingSP) * timeProgress
        let currentSP = Double(trainingStartSp) + trainedSP

        // 计算当前等级的进度
        let levelCurrentSP = currentSP - Double(levelStartSp) // 在该等级已获得的技能点
        let levelTotalSP = Double(levelEndSp - levelStartSp) // 该等级需要的总技能点

        return min(max(levelCurrentSP / levelTotalSP, 0), 1)
    }
}

struct CharacterAttributes: Codable {
    let charisma: Int
    let intelligence: Int
    let memory: Int
    let perception: Int
    let willpower: Int
    let bonus_remaps: Int?
    let accrued_remap_cooldown_date: String?
    let last_remap_date: String?
}

/// 技能与技能队列的单一磁盘快照
private struct CharacterSkillsDiskBundle: Codable {
    var skills: CharacterSkillsResponse?
    var queue: [SkillQueueItem]?
}

public class CharacterSkillsAPI {
    public static let shared = CharacterSkillsAPI()
    private init() {}

    private static let pairedCacheValiditySeconds: TimeInterval = 2 * 60 * 60

    private func characterSkillsDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let characterSkillsPath = documentsPath.appendingPathComponent("CharacterSkills")
        try? FileManager.default.createDirectory(
            at: characterSkillsPath, withIntermediateDirectories: true
        )
        return characterSkillsPath
    }

    private func getSkillsBundleCacheFilePath(characterId: Int) -> URL {
        characterSkillsDirectory().appendingPathComponent("\(characterId)_skills_bundle.json")
    }

    private func legacySkillsCacheFilePath(characterId: Int) -> URL {
        characterSkillsDirectory().appendingPathComponent("\(characterId)_all_skills.json")
    }

    private func legacySkillQueueCacheFilePath(characterId: Int) -> URL {
        characterSkillsDirectory().appendingPathComponent("\(characterId)_skill_queue.json")
    }

    private func isCacheFileValid(at path: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: path.path) else { return false }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let expiry = modificationDate.addingTimeInterval(Self.pairedCacheValiditySeconds)
                return Date() <= expiry
            }
        } catch {
            Logger.error("获取文件属性失败: \(error)")
        }
        return false
    }

    private func makeJSONEncoderForBundle() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private func makeJSONDecoderForBundle() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private func loadDiskBundle(characterId: Int, allowExpired: Bool = false) -> CharacterSkillsDiskBundle? {
        let bundlePath = getSkillsBundleCacheFilePath(characterId: characterId)
        if FileManager.default.fileExists(atPath: bundlePath.path) {
            if allowExpired || isCacheFileValid(at: bundlePath) {
                do {
                    let jsonData = try Data(contentsOf: bundlePath)
                    let bundle = try makeJSONDecoderForBundle().decode(CharacterSkillsDiskBundle.self, from: jsonData)
                    Logger.debug("从合并缓存加载技能快照 - 角色ID: \(characterId), 路径: \(bundlePath.path)")
                    return bundle
                } catch {
                    Logger.error("读取合并技能缓存失败: \(error)")
                    try? FileManager.default.removeItem(at: bundlePath)
                }
            } else {
                try? FileManager.default.removeItem(at: bundlePath)
            }
        }
        return nil
    }

    private func saveDiskBundle(characterId: Int, bundle: CharacterSkillsDiskBundle) -> Bool {
        let path = getSkillsBundleCacheFilePath(characterId: characterId)
        do {
            let data = try makeJSONEncoderForBundle().encode(bundle)
            try data.write(to: path)
            try? FileManager.default.removeItem(at: legacySkillsCacheFilePath(characterId: characterId))
            try? FileManager.default.removeItem(at: legacySkillQueueCacheFilePath(characterId: characterId))
            Logger.debug("已写入合并技能缓存 - 角色ID: \(characterId), 路径: \(path.path)")
            return true
        } catch {
            Logger.error("保存合并技能缓存失败: \(error)")
            return false
        }
    }

    private func saveSkillsOnlyToBundle(characterId: Int, skills: CharacterSkillsResponse) -> Bool {
        // 仅更新 skills 时会清空 queue；结果与「先读盘再写」一致，无需先 loadDiskBundle，避免无意义的二次读盘与日志
        saveDiskBundle(
            characterId: characterId,
            bundle: CharacterSkillsDiskBundle(skills: skills, queue: nil)
        )
    }

    private func saveQueueOnlyToBundle(characterId: Int, queue: [SkillQueueItem]) -> Bool {
        saveDiskBundle(
            characterId: characterId,
            bundle: CharacterSkillsDiskBundle(skills: nil, queue: queue)
        )
    }

    private func savePairedSkillsBundle(characterId: Int, skills: CharacterSkillsResponse, queue: [SkillQueueItem]) -> Bool {
        saveDiskBundle(characterId: characterId, bundle: CharacterSkillsDiskBundle(skills: skills, queue: queue))
    }

    public func loadSkillsFromCacheIfAvailable(characterId: Int) -> CharacterSkillsResponse? {
        loadSkillsFromCache(characterId: characterId)
    }

    public func loadSkillsAndQueueFromCacheIfAvailable(characterId: Int, allowExpired: Bool = false) -> (skills: CharacterSkillsResponse, queue: [SkillQueueItem])? {
        guard let bundle = loadDiskBundle(characterId: characterId, allowExpired: allowExpired),
              let skills = bundle.skills,
              let queue = bundle.queue
        else {
            return nil
        }
        return (skills, queue)
    }

    private func loadSkillsFromCache(characterId: Int) -> CharacterSkillsResponse? {
        guard let bundle = loadDiskBundle(characterId: characterId),
              let skills = bundle.skills
        else {
            return nil
        }
        return skills
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
        if !forceRefresh {
            if let cachedSkills = loadSkillsFromCache(characterId: characterId) {
                return cachedSkills
            }
        }

        let skills = try await fetchCharacterSkillsFromNetwork(characterId: characterId)
        if saveSkillsOnlyToBundle(characterId: characterId, skills: skills) {
            Logger.success("成功缓存技能数据到合并文件 - 角色ID: \(characterId)")
        }
        return skills
    }

    /// 并行拉取技能与队列后**只写入一次**合并缓存。
    public func fetchCharacterSkillsAndQueue(
        characterId: Int,
        forceRefresh: Bool = false
    ) async throws -> (skills: CharacterSkillsResponse, queue: [SkillQueueItem]) {
        if !forceRefresh {
            if let cached = loadSkillsAndQueueFromCacheIfAvailable(characterId: characterId) {
                return cached
            }
        }

        async let skillsTask = fetchCharacterSkillsFromNetwork(characterId: characterId)
        async let queueTask = fetchSkillQueueFromServer(characterId: characterId)
        let (skills, queue) = try await (skillsTask, queueTask)

        if savePairedSkillsBundle(characterId: characterId, skills: skills, queue: queue) {
            Logger.success("成功缓存技能+队列到合并文件 - 角色ID: \(characterId), 队列长度: \(queue.count)")
        }
        await scheduleSkillQueueReminder(characterId: characterId, queue: queue)
        return (skills, queue)
    }

    private func loadSkillQueue(characterId: Int) -> [SkillQueueItem]? {
        guard let bundle = loadDiskBundle(characterId: characterId),
              let queue = bundle.queue
        else {
            return nil
        }
        return queue
    }

    /// 从服务器获取技能队列
    private func fetchSkillQueueFromServer(characterId: Int) async throws -> [SkillQueueItem] {
        let url = URL(
            string:
            "https://esi.evetech.net/characters/\(characterId)/skillqueue/?datasource=tranquility"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SkillQueueItem].self, from: data)
    }

    public func fetchSkillQueue(
        characterId: Int, forceRefresh: Bool = false, scheduleReminder: Bool = true
    ) async throws -> [SkillQueueItem] {
        if !forceRefresh {
            if let cachedQueue = loadSkillQueue(characterId: characterId) {
                return cachedQueue
            }
        }

        Logger.debug("从服务器获取技能队列 - 角色ID: \(characterId)")
        let queue = try await fetchSkillQueueFromServer(characterId: characterId)

        if saveQueueOnlyToBundle(characterId: characterId, queue: queue) {
            Logger.success("成功缓存技能队列到合并文件 - 角色ID: \(characterId)")
        }
        if scheduleReminder {
            await scheduleSkillQueueReminder(characterId: characterId, queue: queue)
        }
        return queue
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
