import Foundation
import SwiftUI

// MARK: - 数据模型

struct MarketHistory: Codable, Sendable {
    let average: Double
    let date: String
    let highest: Double
    let lowest: Double
    let order_count: Int
    let volume: Int
}

extension WidgetMarketPoint {
    static func recent(history: [MarketHistory], through date: Date) -> [Self] {
        let format = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        return recent(history.compactMap { entry in
            guard let day = try? format.parse(entry.date) else { return nil }
            return Self(date: day, average: entry.average)
        }, through: date)
    }
}

// MARK: - 错误类型

enum MarketHistoryAPIError: LocalizedError {
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

// MARK: - 市场历史API

@globalActor actor MarketHistoryAPIActor {
    static let shared = MarketHistoryAPIActor()
}

@MarketHistoryAPIActor
class MarketHistoryAPI {
    static let shared = MarketHistoryAPI()
    private let cacheDuration: TimeInterval = 60 * 60 // 1小时缓存

    private struct RequestKey: Hashable, Sendable {
        let typeID: Int
        let regionID: Int
    }

    private let requests = AppDataRequests<RequestKey, [MarketHistory]>()
    private lazy var bundledPlexHistory = loadPlexHistory()

    private init() {}

    private struct CachedData: Codable {
        let data: [MarketHistory]
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
        return cacheDirectory.appendingPathComponent("market_history_\(typeID)_\(regionID).json")
    }

    func cachedAt(typeID: Int, regionID: Int) -> Date? {
        let region = typeID == MarketManager.plexTypeID ? MarketManager.globalPlexRegionID : regionID
        return getCacheFilePath(typeID: typeID, regionID: region)?.cacheModificationDate
    }

    private func loadFromCache(typeID: Int, regionID: Int, maxAge: TimeInterval) -> [MarketHistory]? {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data),
              cached.timestamp.addingTimeInterval(maxAge) > Date()
        else {
            return nil
        }

        Logger.info("使用缓存的市场历史数据")
        return cached.data
    }

    private func saveToCache(_ history: [MarketHistory], typeID: Int, regionID: Int, at date: Date) {
        guard let cacheFile = getCacheFilePath(typeID: typeID, regionID: regionID) else { return }

        let cachedData = CachedData(data: history, timestamp: date)
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile, options: .atomic)
            Logger.info("市场历史数据已缓存到文件")
        } catch {
            Logger.error("保存市场历史缓存失败: \(error)")
        }
    }

    // MARK: - 公共方法

    func fetchMarketHistory(
        typeID: Int, regionID: Int, forceRefresh: Bool = false, interpolate: Bool = true,
        fillToCurrentDate: Bool = true, maxCacheAge: TimeInterval? = nil
    ) async throws -> [MarketHistory] {
        var actualRegionID = regionID

        // PLEX 特殊处理
        if typeID == MarketManager.plexTypeID {
            actualRegionID = MarketManager.globalPlexRegionID

            // 读取本地plex_history.json文件
            if let plexHistory = bundledPlexHistory {
                // 获取API数据
                let apiHistory = try await fetchApiHistory(
                    typeID: typeID, regionID: actualRegionID, forceRefresh: forceRefresh,
                    interpolate: false, maxCacheAge: maxCacheAge
                )

                // 简单合并：本地数据 + API数据
                let combined = plexHistory + apiHistory

                return interpolate
                    ? interpolateMarketHistory(combined, fillToCurrentDate: fillToCurrentDate)
                    : combined
            }
        }

        // 普通流程
        return try await fetchApiHistory(
            typeID: typeID, regionID: actualRegionID, forceRefresh: forceRefresh,
            interpolate: interpolate, fillToCurrentDate: fillToCurrentDate, maxCacheAge: maxCacheAge
        )
    }

    private func loadPlexHistory() -> [MarketHistory]? {
        guard let path = Bundle.main.path(forResource: "plex_history", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let history = try? JSONDecoder().decode([MarketHistory].self, from: data)
        else {
            return nil
        }
        return history
    }

    private func fetchApiHistory(
        typeID: Int, regionID: Int, forceRefresh: Bool, interpolate: Bool = true,
        fillToCurrentDate: Bool = true, maxCacheAge: TimeInterval? = nil
    ) async throws -> [MarketHistory] {
        if regionID < 0 {
            return []
        }

        // 统一强制刷新限流：5 分钟内的重复强制刷新降级为使用缓存
        var forceRefresh = forceRefresh
        if forceRefresh, await !ForceRefreshThrottle.shared.request(
            key: "history-\(typeID)-\(regionID)"
        ) {
            Logger.info("强制刷新过于频繁，降级使用缓存: \(typeID)")
            forceRefresh = false
        }

        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache(typeID: typeID, regionID: regionID, maxAge: maxCacheAge ?? cacheDuration) {
                return interpolate
                    ? interpolateMarketHistory(cached, fillToCurrentDate: fillToCurrentDate)
                    : cached
            }
        }

        let key = RequestKey(typeID: typeID, regionID: regionID)
        let history = try await requests.run(key) {
            try await self.downloadHistory(for: key)
        }
        return interpolate ? interpolateMarketHistory(history, fillToCurrentDate: fillToCurrentDate) : history
    }

    private func downloadHistory(for key: RequestKey) async throws -> [MarketHistory] {
        let (typeID, regionID) = (key.typeID, key.regionID)
        // 构建URL
        let baseURL = "https://esi.evetech.net/markets/\(regionID)/history/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "type_id", value: "\(typeID)"),
            URLQueryItem(name: "datasource", value: "tranquility"),
        ]

        guard let url = components?.url else {
            throw MarketHistoryAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let history = try JSONDecoder().decode([MarketHistory].self, from: data)

        let now = Date()
        saveToCache(history, typeID: typeID, regionID: regionID, at: now)
        let displayHistory = typeID == MarketManager.plexTypeID ? (bundledPlexHistory ?? []) + history : history
        await AppDataUpdate.marketHistory(typeID: typeID, regionID: regionID, history: displayHistory, at: now).publish()
        return history
    }

    // MARK: - 数据插值处理

    func interpolateMarketHistory(_ history: [MarketHistory], fillToCurrentDate: Bool = true)
        -> [MarketHistory]
    {
        // 确保历史数据按日期排序（从早到晚）
        let sortedHistory = history.sorted {
            guard let date1 = dateFromString($0.date), let date2 = dateFromString($1.date) else {
                return false
            }
            return date1 < date2
        }

        guard !sortedHistory.isEmpty else { return [] }

        // 获取最早和最晚的日期
        guard let firstDateString = sortedHistory.first?.date,
              let lastDateString = sortedHistory.last?.date,
              let firstDate = dateFromString(firstDateString),
              var lastDate = dateFromString(lastDateString)
        else {
            return sortedHistory
        }

        // 如果需要填充到当前日期，则使用当前日期作为最后日期
        if fillToCurrentDate {
            let currentDate = Date()
            if lastDate < currentDate {
                lastDate = currentDate
            }
        }

        // 创建日期到数据的映射
        var dateToHistoryMap = [String: MarketHistory]()
        for item in sortedHistory {
            dateToHistoryMap[item.date] = item
        }

        // 创建完整的日期序列
        var currentDate = firstDate
        var allDates = [String]()
        let calendar = Calendar.current

        while currentDate <= lastDate {
            let dateString = stringFromDate(currentDate)
            allDates.append(dateString)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        // 创建插值后的历史数据
        var interpolatedHistory = [MarketHistory]()
        var lastValidHistory: MarketHistory?

        for dateString in allDates {
            if let historyItem = dateToHistoryMap[dateString] {
                // 如果当前日期有数据，则使用该数据
                interpolatedHistory.append(historyItem)
                lastValidHistory = historyItem
            } else if let lastValid = lastValidHistory {
                // 如果当前日期没有数据，则使用上一个有效数据点的值，但order_count设为0
                let interpolatedItem = MarketHistory(
                    average: lastValid.average,
                    date: dateString,
                    highest: lastValid.highest,
                    lowest: lastValid.lowest,
                    order_count: 0,
                    volume: 0
                )
                interpolatedHistory.append(interpolatedItem)
            }
        }
        Logger.info("插值完成，增加 \(interpolatedHistory.count - history.count) 条数据")
        return interpolatedHistory
    }

    // MARK: - 日期工具方法

    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func stringFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
