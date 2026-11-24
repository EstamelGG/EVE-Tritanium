import Foundation
import SwiftUI

// MARK: - 数据模型

struct MarketOrder: Codable, Sendable {
    let duration: Int
    let isBuyOrder: Bool
    let issued: String
    let locationId: Int64
    let minVolume: Int
    let orderId: Int
    let price: Double
    let range: String
    let systemId: Int
    let typeId: Int
    let volumeRemain: Int
    let volumeTotal: Int

    enum CodingKeys: String, CodingKey {
        case duration
        case isBuyOrder = "is_buy_order"
        case issued
        case locationId = "location_id"
        case minVolume = "min_volume"
        case orderId = "order_id"
        case price
        case range
        case systemId = "system_id"
        case typeId = "type_id"
        case volumeRemain = "volume_remain"
        case volumeTotal = "volume_total"
    }
}

// MARK: - 错误类型

enum MarketAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case let .networkError(error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case let .decodingError(error):
            return "数据解码错误: \(error.localizedDescription)"
        case let .httpError(code):
            return "HTTP错误: \(code)"
        case .rateLimitExceeded:
            return "超出请求限制"
        }
    }
}

// MARK: - 市场API

@globalActor actor MarketOrdersAPIActor {
    static let shared = MarketOrdersAPIActor()
}

@MarketOrdersAPIActor
class MarketOrdersAPI {
    static let shared = MarketOrdersAPI()
    private let cacheDuration: TimeInterval = 3 * 60 * 60 // 3 小时缓存

    private struct RequestKey: Hashable, Sendable {
        let typeID: Int
        let regionID: Int
    }

    private let requests = AppDataRequests<RequestKey, [MarketOrder]>()

    private init() {}

    private struct CachedData: Codable {
        let data: [MarketOrder]
        let timestamp: Date
    }

    // MARK: - 缓存方法

    private func getCacheDirectory() -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "MarketCache", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    private func getCacheFilePath(typeID: Int, regionID: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("market_orders_\(typeID)_\(regionID).json")
    }

    func cachedAt(typeID: Int, regionID: Int) -> Date? {
        let region = typeID == MarketManager.plexTypeID ? MarketManager.globalPlexRegionID : regionID
        return getCacheFilePath(typeID: typeID, regionID: region)?.cacheModificationDate
    }

    private func loadFromCache(typeID: Int, regionID: Int, maxAge: TimeInterval) -> [MarketOrder]? {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              cached.timestamp.addingTimeInterval(maxAge) > Date()
        else {
            return nil
        }

        Logger.info("使用 \(typeID) 缓存的市场订单数据: \(cacheFile)")
        return cached.data
    }

    private func saveToCache(_ orders: [MarketOrder], typeID: Int, regionID: Int, at date: Date) {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID) else { return }

        let cachedData = CachedData(data: orders, timestamp: date)
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile, options: .atomic)
            Logger.info("市场订单数据已缓存到文件")
        } catch {
            Logger.error("保存市场订单缓存失败: \(error)")
        }
    }

    // MARK: - 公共方法

    func fetchMarketOrders(
        typeID: Int, regionID: Int, forceRefresh: Bool = false, maxCacheAge: TimeInterval? = nil
    ) async throws
        -> [MarketOrder]
    {
        var actualRegionID = regionID

        // PLEX 特殊处理：订单走全球市场
        if typeID == MarketManager.plexTypeID {
            actualRegionID = MarketManager.globalPlexRegionID
        }

        // 统一强制刷新限流：5 分钟内的重复强制刷新降级为使用缓存
        var forceRefresh = forceRefresh
        if forceRefresh, await !ForceRefreshThrottle.shared.request(
            key: "orders-\(typeID)-\(actualRegionID)"
        ) {
            Logger.info("强制刷新过于频繁，降级使用缓存: \(typeID)")
            forceRefresh = false
        }

        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache(typeID: typeID, regionID: actualRegionID, maxAge: maxCacheAge ?? cacheDuration) {
                return cached
            }
        }

        let key = RequestKey(typeID: typeID, regionID: actualRegionID)
        return try await requests.run(key) {
            try await self.downloadOrders(for: key)
        }
    }

    private func downloadOrders(for key: RequestKey) async throws -> [MarketOrder] {
        let typeID = key.typeID
        let actualRegionID = key.regionID
        // 构建URL
        let baseURL = "https://esi.evetech.net/markets/\(actualRegionID)/orders/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "type_id", value: "\(typeID)"),
            URLQueryItem(name: "datasource", value: "tranquility"),
        ]

        guard let url = components?.url else {
            throw MarketAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let orders = try JSONDecoder().decode([MarketOrder].self, from: data)

        // 保存到缓存
        let now = Date()
        saveToCache(orders, typeID: typeID, regionID: actualRegionID, at: now)
        await AppDataUpdate.marketOrders(typeID: typeID, regionID: actualRegionID, orders: orders, at: now).publish()

        return orders
    }
}
