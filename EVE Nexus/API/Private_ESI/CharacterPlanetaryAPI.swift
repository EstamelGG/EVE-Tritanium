import Foundation

// MARK: - Data Models

struct CharacterPlanetaryInfo: Codable {
    let lastUpdate: String
    let numPins: Int
    let ownerId: Int
    let planetId: Int
    let planetType: String
    let solarSystemId: Int
    let upgradeLevel: Int

    enum CodingKeys: String, CodingKey {
        case lastUpdate = "last_update"
        case numPins = "num_pins"
        case ownerId = "owner_id"
        case planetId = "planet_id"
        case planetType = "planet_type"
        case solarSystemId = "solar_system_id"
        case upgradeLevel = "upgrade_level"
    }
}

struct PlanetaryDetail: Codable {
    let links: [PlanetaryLink] // maxItems: 500
    let pins: [PlanetaryPin] // maxItems: 100
    let routes: [PlanetaryRoute] // maxItems: 1000

    enum CodingKeys: String, CodingKey {
        case links, pins, routes
    }
}

struct PlanetaryPin: Codable {
    let contentTypeId: Int?
    let contents: [PlanetaryContent]? // maxItems: 90
    let expiryTime: String?
    let extractorDetails: PlanetaryExtractor?
    let factoryDetails: PlanetaryFactory?
    let installTime: String?
    let lastCycleStart: String?
    let latitude: Double
    let longitude: Double
    let pinId: Int64
    let schematicId: Int?
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case contentTypeId = "content_type_id"
        case contents
        case expiryTime = "expiry_time"
        case extractorDetails = "extractor_details"
        case factoryDetails = "factory_details"
        case installTime = "install_time"
        case lastCycleStart = "last_cycle_start"
        case latitude
        case longitude
        case pinId = "pin_id"
        case schematicId = "schematic_id"
        case typeId = "type_id"
    }
}

struct PlanetaryContent: Codable {
    let amount: Int64
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case amount
        case typeId = "type_id"
    }
}

struct PlanetaryExtractor: Codable {
    let heads: [PlanetaryHead] // maxItems: 10
    let productTypeId: Int?
    let cycleTime: Int? // in seconds
    let headRadius: Double?
    let qtyPerCycle: Int?

    enum CodingKeys: String, CodingKey {
        case heads
        case productTypeId = "product_type_id"
        case cycleTime = "cycle_time"
        case headRadius = "head_radius"
        case qtyPerCycle = "qty_per_cycle"
    }
}

struct PlanetaryHead: Codable {
    let headId: Int // maximum: 9, minimum: 0
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case headId = "head_id"
        case latitude
        case longitude
    }
}

struct PlanetaryFactory: Codable {
    let schematicId: Int

    enum CodingKeys: String, CodingKey {
        case schematicId = "schematic_id"
    }
}

struct PlanetaryRoute: Codable {
    let contentTypeId: Int
    let destinationPinId: Int64
    let quantity: Double
    let routeId: Int64
    let sourcePinId: Int64
    let waypoints: [Int64]? // maxItems: 5

    enum CodingKeys: String, CodingKey {
        case contentTypeId = "content_type_id"
        case destinationPinId = "destination_pin_id"
        case quantity
        case routeId = "route_id"
        case sourcePinId = "source_pin_id"
        case waypoints
    }
}

// MARK: - Extended Cache Structure

/// 扩展的行星详情缓存结构，包含计算结果
struct CachedPlanetaryDetail: Codable {
    let detail: PlanetaryDetail // 原始的行星详情数据

    // 计算结果（可选，如果存在则说明已计算过）
    let earliestExtractorExpiry: Date? // 最早采集器过期时间
    let finalProductIds: [Int]? // 最终产品ID列表
    let extractorStatus: CachedExtractorStatus? // 采集器状态

    enum CodingKeys: String, CodingKey {
        case detail
        case earliestExtractorExpiry = "earliest_extractor_expiry"
        case finalProductIds = "final_product_ids"
        case extractorStatus = "extractor_status"
    }
}

/// 缓存的采集器状态
struct CachedExtractorStatus: Codable {
    let totalCount: Int
    let expiredCount: Int
    let expiringSoonCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case expiredCount = "expired_count"
        case expiringSoonCount = "expiring_soon_count"
    }
}

/// 缓存的计算结果（用于返回）
struct CachedPlanetaryResults {
    let earliestExtractorExpiry: Date?
    let finalProductIds: [Int]
    let extractorStatus: CachedExtractorStatus
}

class CharacterPlanetaryAPI {
    // MARK: - Cache Configuration

    /// 星球列表缓存过期时间（秒），默认1天
    private static let planetaryListCacheExpiration: TimeInterval = 24 * 60 * 60

    /// 星球详情缓存过期时间（秒），默认1小时
    private static let planetaryDetailCacheExpiration: TimeInterval = 1 * 60 * 60

    static func fetchCharacterPlanetary(characterId: Int, forceRefresh: Bool = false) async throws
        -> [CharacterPlanetaryInfo]
    {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/planets/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }
        // 检查缓存（除非强制刷新）
        if !forceRefresh, let cachedData = checkCache(characterId: characterId) {
            Logger.info("Fetch Planets from cache.")
            return cachedData
        }

        // 使用fetchWithToken发起请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        Logger.debug("Fetched from Network.")
        // 解析数据
        let planetaryInfo = try JSONDecoder().decode([CharacterPlanetaryInfo].self, from: data)

        // 缓存数据
        try? saveToCache(data: data, characterId: characterId)

        return planetaryInfo
    }

    static func fetchPlanetaryDetail(characterId: Int, planetId: Int, forceRefresh: Bool = false)
        async throws -> PlanetaryDetail
    {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/planets/\(planetId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }

        // 检查缓存（除非强制刷新）
        if !forceRefresh,
           let cachedData = checkPlanetCache(characterId: characterId, planetId: planetId)
        {
            Logger.info("Fetch Planetary Detail from cache.")
            return cachedData
        }

        // 使用fetchWithToken发起请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        Logger.debug("Fetched from Network.")
        // 解析数据
        let planetaryDetail = try JSONDecoder().decode(PlanetaryDetail.self, from: data)

        // 缓存数据（保存为扩展格式，但不包含计算结果）
        try? saveToPlanetCache(detail: planetaryDetail, characterId: characterId, planetId: planetId)
        Logger.debug("Save to cache.")
        return planetaryDetail
    }

    /// 获取行星详情（带计算结果缓存）
    /// - Returns: (detail, cachedResults)，如果缓存中有计算结果则返回，否则返回 nil
    static func fetchPlanetaryDetailWithCache(
        characterId: Int,
        planetId: Int,
        forceRefresh: Bool = false
    ) async throws -> (detail: PlanetaryDetail, cachedResults: CachedPlanetaryResults?) {
        let urlString =
            "https://esi.evetech.net/characters/\(characterId)/planets/\(planetId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }

        // 检查合并后的缓存（包含计算结果）
        if !forceRefresh {
            if let (detail, cachedResults) = checkMergedPlanetCache(characterId: characterId, planetId: planetId) {
                Logger.info("Fetch Planetary Detail from merged cache.")
                return (detail, cachedResults)
            }
        }

        // 使用fetchWithToken发起请求
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        Logger.debug("Fetched from Network.")
        // 解析数据
        let planetaryDetail = try JSONDecoder().decode(PlanetaryDetail.self, from: data)

        // 缓存数据（保存为扩展格式，但不包含计算结果）
        try? saveToPlanetCache(detail: planetaryDetail, characterId: characterId, planetId: planetId)
        Logger.debug("Save to cache.")
        return (planetaryDetail, nil)
    }

    /// 保存计算结果到缓存（更新合并后的缓存）
    static func savePlanetaryDetailCalculations(
        characterId: Int,
        planetId: Int,
        earliestExtractorExpiry: Date?,
        finalProductIds: [Int],
        extractorStatus: CachedExtractorStatus
    ) {
        // 先读取现有的缓存数据
        guard let detail = checkPlanetCache(characterId: characterId, planetId: planetId) else {
            Logger.warning("无法保存计算结果：找不到原始缓存数据")
            return
        }

        // 创建扩展缓存结构（包含计算结果）
        let cachedDetail = CachedPlanetaryDetail(
            detail: detail,
            earliestExtractorExpiry: earliestExtractorExpiry,
            finalProductIds: finalProductIds,
            extractorStatus: extractorStatus
        )

        // 保存到合并后的缓存
        do {
            try saveToPlanetCache(cachedDetail: cachedDetail, characterId: characterId, planetId: planetId)
            Logger.debug("已保存计算结果到缓存: character_\(characterId)_planet_\(planetId)")
        } catch {
            Logger.error("保存计算结果到缓存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Management

    private static func checkCache(characterId: Int) -> [CharacterPlanetaryInfo]? {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")

        let cacheFile = cacheDirectory.appendingPathComponent("\(characterId)_planetary.json")

        guard fileManager.fileExists(atPath: cacheFile.path) else {
            return nil
        }

        // 检查文件修改时间
        guard let attributes = try? fileManager.attributesOfItem(atPath: cacheFile.path),
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        // 检查缓存是否过期
        if Date().timeIntervalSince(modificationDate) > planetaryListCacheExpiration {
            try? fileManager.removeItem(at: cacheFile)
            return nil
        }

        // 读取缓存数据
        guard let data = try? Data(contentsOf: cacheFile),
              let planetaryInfo = try? JSONDecoder().decode([CharacterPlanetaryInfo].self, from: data)
        else {
            return nil
        }
        Logger.info("Read data from cache: \(cacheFile.path())")
        return planetaryInfo
    }

    private static func saveToCache(data: Data, characterId: Int) throws {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")

        // 创建缓存目录（如果不存在）
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let cacheFile = cacheDirectory.appendingPathComponent("\(characterId)_planetary.json")
        try data.write(to: cacheFile)
    }

    // MARK: - Planet Cache Management

    /// 检查合并后的缓存（统一使用 CachedPlanetaryDetail 格式）
    private static func checkMergedPlanetCache(characterId: Int, planetId: Int) -> (detail: PlanetaryDetail, cachedResults: CachedPlanetaryResults?)? {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")

        let cacheFile = cacheDirectory.appendingPathComponent(
            "character_\(characterId)_planet_\(planetId).json"
        )

        guard fileManager.fileExists(atPath: cacheFile.path) else {
            return nil
        }

        // 检查文件修改时间
        guard let attributes = try? fileManager.attributesOfItem(atPath: cacheFile.path),
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        // 检查缓存是否过期
        if Date().timeIntervalSince(modificationDate) > planetaryDetailCacheExpiration {
            try? fileManager.removeItem(at: cacheFile)
            return nil
        }

        // 读取缓存数据
        guard let data = try? Data(contentsOf: cacheFile) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 读取 CachedPlanetaryDetail 格式
        guard let cachedDetail = try? decoder.decode(CachedPlanetaryDetail.self, from: data) else {
            return nil
        }

        // 检查是否有计算结果
        if let finalProductIds = cachedDetail.finalProductIds,
           let extractorStatus = cachedDetail.extractorStatus
        {
            let cachedResults = CachedPlanetaryResults(
                earliestExtractorExpiry: cachedDetail.earliestExtractorExpiry,
                finalProductIds: finalProductIds,
                extractorStatus: extractorStatus
            )
            return (cachedDetail.detail, cachedResults)
        } else {
            // 没有计算结果
            return (cachedDetail.detail, nil)
        }
    }

    /// 检查缓存（仅返回详情）
    private static func checkPlanetCache(characterId: Int, planetId: Int) -> PlanetaryDetail? {
        if let (detail, _) = checkMergedPlanetCache(characterId: characterId, planetId: planetId) {
            return detail
        }
        return nil
    }

    /// 保存到缓存（统一使用 CachedPlanetaryDetail 格式）
    private static func saveToPlanetCache(
        detail: PlanetaryDetail? = nil,
        cachedDetail: CachedPlanetaryDetail? = nil,
        characterId: Int,
        planetId: Int
    ) throws {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")

        // 创建缓存目录（如果不存在）
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let cacheFile = cacheDirectory.appendingPathComponent(
            "character_\(characterId)_planet_\(planetId).json"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // 统一使用 CachedPlanetaryDetail 格式
        let cachedDetailToSave: CachedPlanetaryDetail
        if let cachedDetail = cachedDetail {
            cachedDetailToSave = cachedDetail
        } else if let detail = detail {
            // 保存为 CachedPlanetaryDetail 格式但不包含计算结果
            cachedDetailToSave = CachedPlanetaryDetail(
                detail: detail,
                earliestExtractorExpiry: nil,
                finalProductIds: nil,
                extractorStatus: nil
            )
        } else {
            throw NSError(domain: "CharacterPlanetaryAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "必须提供 detail 或 cachedDetail"])
        }

        let data = try encoder.encode(cachedDetailToSave)
        try data.write(to: cacheFile)
    }

    /// 清理指定角色的所有星球详情缓存
    /// - Parameter characterId: 角色ID
    static func clearPlanetDetailCache(characterId: Int) {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary")

        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            let prefix = "character_\(characterId)_planet_"
            for file in files {
                if file.lastPathComponent.hasPrefix(prefix) {
                    try fileManager.removeItem(at: file)
                    Logger.info("已清理星球详情缓存: \(file.lastPathComponent)")
                }
            }
        } catch {
            Logger.error("清理星球详情缓存失败: \(error.localizedDescription)")
        }
    }
}
