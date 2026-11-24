import Foundation

// MARK: - Data Models

struct CharacterPlanetaryInfo: Codable, Sendable {
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

struct PlanetaryDetail: Codable, Equatable, Sendable {
    let links: [PlanetaryLink] // maxItems: 500
    let pins: [PlanetaryPin] // maxItems: 100
    let routes: [PlanetaryRoute] // maxItems: 1000

    enum CodingKeys: String, CodingKey {
        case links, pins, routes
    }
}

struct PlanetaryPin: Codable, Equatable, Sendable {
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

struct PlanetaryContent: Codable, Equatable, Sendable {
    let amount: Int64
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case amount
        case typeId = "type_id"
    }
}

struct PlanetaryExtractor: Codable, Equatable, Sendable {
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

struct PlanetaryHead: Codable, Equatable, Sendable {
    let headId: Int // maximum: 9, minimum: 0
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case headId = "head_id"
        case latitude
        case longitude
    }
}

struct PlanetaryFactory: Codable, Equatable, Sendable {
    let schematicId: Int

    enum CodingKeys: String, CodingKey {
        case schematicId = "schematic_id"
    }
}

struct PlanetaryRoute: Codable, Equatable, Sendable {
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
    var fetchedAt: Date?

    enum CodingKeys: String, CodingKey {
        case detail
        case earliestExtractorExpiry = "earliest_extractor_expiry"
        case finalProductIds = "final_product_ids"
        case extractorStatus = "extractor_status"
        case fetchedAt = "fetched_at"
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

@globalActor
actor PlanetaryCacheWriter {
    static let shared = PlanetaryCacheWriter()
}

class CharacterPlanetaryAPI {
    // MARK: - Cache Configuration

    /// 星球列表缓存过期时间（秒），默认1天
    private static let planetaryListCacheExpiration: TimeInterval = 24 * 60 * 60

    /// 星球详情缓存过期时间（秒），默认1小时
    private static let planetaryDetailCacheExpiration: TimeInterval = 1 * 60 * 60

    private struct DetailKey: Hashable, Sendable {
        let characterID: Int
        let planetID: Int
    }

    private static let colonyRequests = AppDataRequests<Int, [CharacterPlanetaryInfo]>()
    private static let detailRequests = AppDataRequests<DetailKey, PlanetaryDetail>()

    static func fetchCharacterPlanetary(
        characterId: Int, forceRefresh: Bool = false, maxCacheAge: TimeInterval? = nil
    ) async throws -> [CharacterPlanetaryInfo] {
        if !forceRefresh, let cached = checkCache(
            characterId: characterId, maxAge: maxCacheAge ?? planetaryListCacheExpiration
        ) {
            return cached
        }
        return try await colonyRequests.run(characterId) {
            let url = URL(string: "https://esi.evetech.net/characters/\(characterId)/planets/?datasource=tranquility")!
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url, characterId: characterId, forceRefresh: forceRefresh
            )
            let colonies = try JSONDecoder().decode([CharacterPlanetaryInfo].self, from: data)
            try? saveToCache(data: data, characterId: characterId)
            await AppDataUpdate.colonies(characterID: characterId, colonies: colonies, at: Date()).publish()
            return colonies
        }
    }

    static func fetchPlanetaryDetail(
        characterId: Int, planetId: Int, forceRefresh: Bool = false, maxCacheAge: TimeInterval? = nil
    ) async throws -> PlanetaryDetail {
        try await fetchPlanetaryDetailWithCache(
            characterId: characterId, planetId: planetId, forceRefresh: forceRefresh, maxCacheAge: maxCacheAge
        ).detail
    }

    static func fetchPlanetaryDetailWithCache(
        characterId: Int,
        planetId: Int,
        forceRefresh: Bool = false,
        maxCacheAge: TimeInterval? = nil
    ) async throws -> (detail: PlanetaryDetail, cachedResults: CachedPlanetaryResults?) {
        if !forceRefresh, let cached = checkMergedPlanetCache(
            characterId: characterId, planetId: planetId, maxCacheAge: maxCacheAge
        ) {
            return cached
        }

        let key = DetailKey(characterID: characterId, planetID: planetId)
        let detail = try await detailRequests.run(key) {
            let url = URL(string: "https://esi.evetech.net/characters/\(characterId)/planets/\(planetId)/?datasource=tranquility")!
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url, characterId: characterId, forceRefresh: forceRefresh
            )
            let detail = try JSONDecoder().decode(PlanetaryDetail.self, from: data)
            try? await saveToPlanetCache(detail: detail, characterId: characterId, planetId: planetId)
            await AppDataUpdate.colony(characterID: characterId, planetID: planetId, detail: detail, at: Date()).publish()
            return detail
        }
        return (detail, nil)
    }

    static func cachedColonies(characterID: Int) -> [CharacterPlanetaryInfo]? {
        checkCache(characterId: characterID, maxAge: nil)
    }

    static func cachedColony(characterID: Int, planetID: Int, allowExpired: Bool = true) -> PlanetaryDetail? {
        checkMergedPlanetCache(characterId: characterID, planetId: planetID, allowExpired: allowExpired)?.detail
    }

    /// 保存计算结果到缓存（更新合并后的缓存）
    @PlanetaryCacheWriter
    static func savePlanetaryDetailCalculations(
        characterId: Int,
        planetId: Int,
        detail: PlanetaryDetail,
        earliestExtractorExpiry: Date?,
        finalProductIds: [Int],
        extractorStatus: CachedExtractorStatus
    ) {
        guard checkPlanetCache(characterId: characterId, planetId: planetId) == detail else { return }

        // 创建扩展缓存结构（包含计算结果）
        let cachedDetail = CachedPlanetaryDetail(
            detail: detail,
            earliestExtractorExpiry: earliestExtractorExpiry,
            finalProductIds: finalProductIds,
            extractorStatus: extractorStatus,
            fetchedAt: cachedColonyAt(characterID: characterId, planetID: planetId)
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

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Planetary", isDirectory: true)
    }

    private static func coloniesCacheURL(characterID: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(characterID)_planetary.json")
    }

    private static func colonyCacheURL(characterID: Int, planetID: Int) -> URL {
        cacheDirectory.appendingPathComponent("character_\(characterID)_planet_\(planetID).json")
    }

    static func cachedColoniesAt(characterID: Int) -> Date? {
        coloniesCacheURL(characterID: characterID).cacheModificationDate
    }

    static func cachedColonyAt(characterID: Int, planetID: Int) -> Date? {
        let url = colonyCacheURL(characterID: characterID, planetID: planetID)
        struct Timestamp: Decodable { let fetched_at: Date? }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fetchedAt = (try? decoder.decode(Timestamp.self, from: Data(contentsOf: url)))?.fetched_at
        return fetchedAt ?? url.cacheModificationDate
    }

    private static func checkCache(characterId: Int, maxAge: TimeInterval?) -> [CharacterPlanetaryInfo]? {
        let fileManager = FileManager.default
        let cacheFile = coloniesCacheURL(characterID: characterId)

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
        if let maxAge, Date().timeIntervalSince(modificationDate) >= maxAge {
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

        // 创建缓存目录（如果不存在）
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let cacheFile = coloniesCacheURL(characterID: characterId)
        try data.write(to: cacheFile, options: .atomic)
    }

    // MARK: - Planet Cache Management

    /// 检查合并后的缓存（统一使用 CachedPlanetaryDetail 格式）
    private static func checkMergedPlanetCache(characterId: Int, planetId: Int, allowExpired: Bool = false, maxCacheAge: TimeInterval? = nil) -> (detail: PlanetaryDetail, cachedResults: CachedPlanetaryResults?)? {
        let fileManager = FileManager.default

        let cacheFile = colonyCacheURL(characterID: characterId, planetID: planetId)

        guard fileManager.fileExists(atPath: cacheFile.path) else {
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

        guard allowExpired || (cachedDetail.fetchedAt ?? cacheFile.cacheModificationDate)
            .map({ Date().timeIntervalSince($0) < (maxCacheAge ?? planetaryDetailCacheExpiration) }) == true else { return nil }

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
    @PlanetaryCacheWriter
    private static func saveToPlanetCache(
        detail: PlanetaryDetail? = nil,
        cachedDetail: CachedPlanetaryDetail? = nil,
        characterId: Int,
        planetId: Int
    ) throws {
        let fileManager = FileManager.default

        // 创建缓存目录（如果不存在）
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let cacheFile = colonyCacheURL(characterID: characterId, planetID: planetId)

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
                extractorStatus: nil,
                fetchedAt: Date()
            )
        } else {
            throw NSError(domain: "CharacterPlanetaryAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "必须提供 detail 或 cachedDetail"])
        }

        let data = try encoder.encode(cachedDetailToSave)
        try data.write(to: cacheFile, options: .atomic)
    }

    /// 清理指定角色的所有星球详情缓存
    /// - Parameter characterId: 角色ID
    @PlanetaryCacheWriter
    static func clearPlanetDetailCache(characterId: Int) {
        let fileManager = FileManager.default

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
