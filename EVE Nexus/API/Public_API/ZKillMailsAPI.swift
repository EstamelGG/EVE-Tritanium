import Foundation

// MARK: - ESI Killmail 响应数据结构

struct ESIKillMail: Codable {
    let killmail_id: Int
    let killmail_time: String // ISO 8601 格式
    let solar_system_id: Int
    let victim: ESIVictim
    let attackers: [ESIAttacker]?
    let items: [ESIItem]?
}

struct ESIVictim: Codable {
    let character_id: Int?
    let corporation_id: Int
    let alliance_id: Int?
    let ship_type_id: Int
    let damage_taken: Int
    let items: [ESIItem]?
}

struct ESIAttacker: Codable {
    let character_id: Int?
    let corporation_id: Int?
    let alliance_id: Int?
    let ship_type_id: Int?
    let weapon_type_id: Int?
    let damage_done: Int
    let final_blow: Bool
}

struct ESIItem: Codable {
    let item_type_id: Int
    let flag: Int
    let quantity_dropped: Int?
    let quantity_destroyed: Int?
    let singleton: Int
    /// 容器内嵌套物品（如货柜中的内容）
    let items: [ESIItem]?
}

// MARK: - 战斗统计相关结构体

struct CharBattleIsk: Codable {
    let iskDestroyed: Double
    let iskLost: Double

    enum CodingKeys: String, CodingKey {
        case iskDestroyed = "s-a-id"
        case iskLost = "s-a-il"
    }
}

class ZKillMailsAPI {
    static let shared = ZKillMailsAPI()
    private init() {}

    // MARK: - ESI Killmail 缓存

    private static let esiKillmailCacheDirectoryName = "ESIKillmails"
    private static let esiKillmailBaseURLString = "https://esi.evetech.net/killmails"
    /// 本地 ESI 详情缓存有效期（秒）；过期后重新请求 ESI
    static let esiKillmailCacheTTL: TimeInterval = 7 * 24 * 60 * 60

    private func getESIKillmailCacheDirectory() throws -> URL {
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent(Self.esiKillmailCacheDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        return cacheDirectory
    }

    private func getESIKillmailCacheFileURL(killmailId: Int) throws -> URL {
        let cacheDirectory = try getESIKillmailCacheDirectory()
        return cacheDirectory.appendingPathComponent("\(killmailId).json")
    }

    /// 从缓存读取 ESI Killmail 详情（存在、未过期且可解码则返回，否则返回 nil）
    private func loadESIKillmailFromCache(killmailId: Int) -> ESIKillMail? {
        guard let cacheFileURL = try? getESIKillmailCacheFileURL(killmailId: killmailId),
              FileManager.default.fileExists(atPath: cacheFileURL.path)
        else {
            return nil
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFileURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) >= Self.esiKillmailCacheTTL
        {
            try? FileManager.default.removeItem(at: cacheFileURL)
            Logger.debug("ESI 详情缓存已过期并删除 - killmail_id: \(killmailId)")
            return nil
        }

        guard let data = try? Data(contentsOf: cacheFileURL),
              let esiDetail = try? JSONDecoder().decode(ESIKillMail.self, from: data)
        else {
            try? FileManager.default.removeItem(at: cacheFileURL)
            return nil
        }
        Logger.debug("已从本地缓存 \(cacheFileURL) 加载 KM 详情.")
        return esiDetail
    }

    /// 将 ESI Killmail 原始数据写入缓存
    private func saveESIKillmailToCache(killmailId: Int, data: Data) {
        guard let cacheFileURL = try? getESIKillmailCacheFileURL(killmailId: killmailId) else {
            return
        }
        try? data.write(to: cacheFileURL)
        Logger.debug("已将 KM 详情写入本地缓存 \(cacheFileURL)")
    }

    // MARK: - 公共方法

    /// 获取单个 ESI Killmail 详情（优先读缓存，未命中则请求 ESI 并写入缓存）
    func fetchESIDetail(killmailId: Int, hash: String) async throws -> ESIKillMail {
        if let cached = loadESIKillmailFromCache(killmailId: killmailId) {
            Logger.debug("从缓存读取 ESI 详情 - killmail_id: \(killmailId), hash: \(hash), url: \("\(Self.esiKillmailBaseURLString)/\(killmailId)/\(hash)/?datasource=tranquility")")
            return cached
        }

        let urlString = "\(Self.esiKillmailBaseURLString)/\(killmailId)/\(hash)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        Logger.debug("从 ESI 获取详情 - killmail_id: \(killmailId), url: \(url)")
        let data = try await NetworkManager.shared.fetchData(from: url)

        let esiDetail = try JSONDecoder().decode(ESIKillMail.self, from: data)
        saveESIKillmailToCache(killmailId: killmailId, data: data)
        Logger.debug("ESI 详情已缓存 - killmail_id: \(killmailId)")
        return esiDetail
    }

    /// 获取角色战斗统计信息（zkillboard 缓存 1 小时）
    func fetchCharacterStats(characterId: Int) async throws -> CharBattleIsk {
        let urlString = "https://zkillboard.com/cache/1hour/stats/?type=characterID&id=\(characterId)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        Logger.info("开始获取角色战斗统计信息 - ID: \(characterId)")
        let data = try await NetworkManager.shared.fetchData(from: url)
        let stats = try JSONDecoder().decode(CharBattleIsk.self, from: data)
        Logger.success("成功获取角色战斗统计信息")
        return stats
    }
}
