import Foundation
import SwiftUI

/// 角色公开信息数据模型
struct CharacterPublicInfo: Codable {
    let alliance_id: Int?
    let birthday: String
    let bloodline_id: Int
    let corporation_id: Int
    let faction_id: Int?
    let gender: String
    let name: String
    let race_id: Int
    let security_status: Double?
    let title: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case alliance_id
        case birthday
        case bloodline_id
        case corporation_id
        case description
        case faction_id
        case gender
        case name
        case race_id
        case security_status
        case title
    }
}

/// 角色雇佣历史记录数据模型
struct CharacterEmploymentHistory: Codable {
    let corporation_id: Int
    let record_id: Int
    let start_date: String
}

final class CharacterAPI: @unchecked Sendable {
    static let shared = CharacterAPI()
    private init() {
        // 使用 ImageCacheManager，无需初始化配置
    }

    /// 保存角色信息到数据库
    private func saveCharacterInfoToCache(_ info: CharacterPublicInfo, characterId: Int) -> Bool {
        let query = """
            INSERT OR REPLACE INTO character_info (
                character_id, alliance_id, birthday, bloodline_id, corporation_id,
                faction_id, gender, name, race_id, security_status, title, description,
                last_updated
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        """

        let parameters: [Any] = [
            characterId,
            info.alliance_id as Any? ?? NSNull(),
            info.birthday,
            info.bloodline_id,
            info.corporation_id,
            info.faction_id as Any? ?? NSNull(),
            info.gender,
            info.name,
            info.race_id,
            info.security_status as Any? ?? NSNull(),
            info.title as Any? ?? NSNull(),
            info.description as Any? ?? NSNull(),
        ]

        // 字段名称数组，与参数数组顺序对应
        let fieldNames = [
            "character_id",
            "alliance_id",
            "birthday",
            "bloodline_id",
            "corporation_id",
            "faction_id",
            "gender",
            "name",
            "race_id",
            "security_status",
            "title",
            "description",
        ]

        if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: parameters
        ) {
            Logger.error("保存角色信息失败: \(error)")
            // 打印每个参数的字段名、值和类型
            for (index, value) in parameters.enumerated() {
                Logger.error("字段 '\(fieldNames[index])': 值 = \(value), 类型 = \(type(of: value))")
            }
            return false
        }

        Logger.success("成功保存角色信息到数据库 - 角色ID: \(characterId)")
        return true
    }

    /// 从数据库读取角色信息
    private func loadCharacterInfoFromCache(characterId: Int, ignoreExpiry: Bool = false) -> CharacterPublicInfo? {
        let query: String
        if ignoreExpiry {
            query = """
                SELECT * FROM character_info
                WHERE character_id = ?
            """
        } else {
            query = """
                SELECT * FROM character_info
                WHERE character_id = ?
                AND datetime(last_updated) > datetime('now', '-1 hour')
            """
        }

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ),
            let row = rows.first
        {
            // 安全地处理数值类型转换
            guard let bloodlineId = (row["bloodline_id"] as? Int64).map({ Int($0) }),
                  let corporationId = (row["corporation_id"] as? Int64).map({ Int($0) }),
                  let raceId = (row["race_id"] as? Int64).map({ Int($0) }),
                  let gender = row["gender"] as? String,
                  let name = row["name"] as? String,
                  let birthday = row["birthday"] as? String
            else {
                Logger.error("从数据库加载角色信息失败 - 必需字段类型转换失败")
                return nil
            }

            // 处理可选字段
            let allianceId = (row["alliance_id"] as? Int64).map { Int($0) }
            let factionId = (row["faction_id"] as? Int64).map { Int($0) }
            let securityStatus = row["security_status"] as? Double
            let title = row["title"] as? String
            let description = row["description"] as? String

            return CharacterPublicInfo(
                alliance_id: allianceId,
                birthday: birthday,
                bloodline_id: bloodlineId,
                corporation_id: corporationId,
                faction_id: factionId,
                gender: gender,
                name: name,
                race_id: raceId,
                security_status: securityStatus,
                title: title,
                description: description
            )
        }
        return nil
    }

    /// 读取缓存的角色信息（忽略过期时间）。
    /// 用于"先用缓存再刷新"模式：在 `fetchCharacterPublicInfo` 返回前，先用缓存启动关联信息加载。
    func loadCachedCharacterInfo(characterId: Int) -> CharacterPublicInfo? {
        return loadCharacterInfoFromCache(characterId: characterId, ignoreExpiry: true)
    }

    /// 获取角色公开信息
    func fetchCharacterPublicInfo(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterPublicInfo
    {
        // 如果不是强制刷新，先尝试从数据库加载
        if !forceRefresh {
            if let cachedInfo = loadCharacterInfoFromCache(characterId: characterId) {
                Logger.info("使用缓存的角色信息 - 角色ID: \(characterId)")
                return cachedInfo
            }
        }

        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/?datasource=tranquility" // 该接口缓存期较长 7 天，仅记录不重要信息
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        var info = try JSONDecoder().decode(CharacterPublicInfo.self, from: data)

        // 获取最新的联盟和公司信息
        do {
            let affiliations = try await CharacterAffiliationAPI.shared.fetchAffiliations( // 该接口缓存期较短，用于获取最新的人物军团和联盟信息
                characterIds: [characterId]
            )
            if let affiliation = affiliations.first {
                // 更新联盟和公司信息
                info = CharacterPublicInfo(
                    alliance_id: affiliation.alliance_id, // 使用缓存期较短的数据
                    birthday: info.birthday,
                    bloodline_id: info.bloodline_id,
                    corporation_id: affiliation.corporation_id, // 使用缓存期较短的数据
                    faction_id: affiliation.faction_id,
                    gender: info.gender,
                    name: info.name,
                    race_id: info.race_id,
                    security_status: info.security_status,
                    title: info.title,
                    description: info.description
                )
            }
        } catch {
            Logger.error("获取角色关联信息失败: \(error)")
            // 即使获取关联信息失败，我们仍然使用原始信息
        }

        // 保存到数据库
        if saveCharacterInfoToCache(info, characterId: characterId) {
            Logger.success("成功缓存角色信息 - 角色ID: \(characterId)")
        }

        return info
    }

    /// 获取角色头像URL
    private func getPortraitURL(characterId: Int, size: Int) -> URL {
        return URL(
            string: "https://images.evetech.net/characters/\(characterId)/portrait?size=\(size)"
        )!
    }

    /// 获取角色头像
    func fetchCharacterPortrait(
        characterId: Int, size: Int = 128, forceRefresh: Bool = false, catchImage _: Bool = true
    ) async throws -> UIImage {
        let portraitURL = getPortraitURL(characterId: characterId, size: size)

        do {
            // 使用 ImageCacheManager
            // backgroundUpdate: true 表示先返回缓存，后台验证ETag并更新
            return try await ImageCacheManager.shared.fetchImage(
                from: portraitURL,
                forceRefresh: forceRefresh,
                backgroundUpdate: true
            )

            // Logger.info("成功获取角色头像 - 角色ID: \(characterId), 大小: \(size)")

        } catch {
            Logger.error("获取角色头像失败 - 角色ID: \(characterId), 错误: \(error)")
            throw error
        }
    }

    /// 获取角色雇佣历史
    func fetchEmploymentHistory(characterId: Int, forceRefresh: Bool = false) async throws -> [CharacterEmploymentHistory] {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EmploymentHistory", isDirectory: true)
        let file = directory.appendingPathComponent("\(characterId).json")
        if !forceRefresh,
           let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < 24 * 3600,
           let data = try? Data(contentsOf: file),
           let history = try? JSONDecoder().decode([CharacterEmploymentHistory].self, from: data)
        {
            return history
        }

        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/corporationhistory/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url, forceRefresh: forceRefresh)
        let history = try JSONDecoder().decode([CharacterEmploymentHistory].self, from: data)

        // 按开始日期降序排序（最新的在前）
        let sorted = history.sorted { $0.start_date > $1.start_date }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(sorted).write(to: file, options: .atomic)
        } catch {
            Logger.error("无法缓存雇佣历史: \(error)")
        }
        return sorted
    }
}
