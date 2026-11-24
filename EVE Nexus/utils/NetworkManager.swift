import Foundation
import Pulse
import SwiftUI

/// 修改缓存包装类为泛型
class CachedData<T> {
    let data: T
    let timestamp: Date

    init(data: T, timestamp: Date) {
        self.data = data
        self.timestamp = timestamp
    }
}

/// 频率限制信息结构
struct RateLimitInfo {
    let group: String?
    let limit: String?
    let remaining: Int?
    let used: Int?
    let retryAfter: Int?

    init(from response: HTTPURLResponse) {
        group = response.value(forHTTPHeaderField: "X-Ratelimit-Group")
        limit = response.value(forHTTPHeaderField: "X-Ratelimit-Limit")
        remaining = Int(response.value(forHTTPHeaderField: "X-Ratelimit-Remaining") ?? "")
        used = Int(response.value(forHTTPHeaderField: "X-Ratelimit-Used") ?? "")
        retryAfter = Int(response.value(forHTTPHeaderField: "Retry-After") ?? "")
    }

    var logString: String {
        var components: [String] = []

        components.append("组: \(group ?? "N/A")")
        components.append("限制: \(limit ?? "N/A")")
        components.append("剩余: \(remaining?.description ?? "N/A")")
        components.append("已用: \(used?.description ?? "N/A")")
        components.append("重试间隔: \(retryAfter?.description ?? "N/A")")

        return components.joined(separator: ", ")
    }
}

// UserDefaults 键：API 频率限制触发时间戳
private let rateLimitTriggeredAtKey = "RateLimit_TriggeredAt"
private let rateLimitCooldownSeconds: TimeInterval = 60

/// 全局 API 频率限制弹窗管理器
@MainActor
final class RateLimitAlertManager: ObservableObject {
    static let shared = RateLimitAlertManager()

    @Published var shouldShowRateLimitAlert = false

    /// 冷却结束时间，供 TimelineView 倒计时使用；无冷却或已结束时返回 nil
    static var cooldownEndDate: Date? {
        let triggeredAt = UserDefaults.standard.double(forKey: rateLimitTriggeredAtKey)
        guard triggeredAt > 0 else { return nil }
        let endDate = Date(timeIntervalSince1970: triggeredAt + rateLimitCooldownSeconds)
        return endDate > Date() ? endDate : nil
    }

    private init() {}

    func showRateLimitAlert() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: rateLimitTriggeredAtKey)
        shouldShowRateLimitAlert = true
    }
}

/// 检查是否处于频率限制冷却期，若是则抛出错误
private func checkRateLimitCooldown() throws {
    let triggeredAt = UserDefaults.standard.double(forKey: rateLimitTriggeredAtKey)
    guard triggeredAt > 0 else { return }
    let elapsed = Date().timeIntervalSince1970 - triggeredAt
    if elapsed < rateLimitCooldownSeconds {
        throw NetworkError.rateLimitCooldown
    }
}

/// 修改类定义，继承自NSObject
@globalActor actor NetworkManagerActor {
    static let shared = NetworkManagerActor()
}

@NetworkManagerActor
class NetworkManager: NSObject, @unchecked Sendable {
    static let shared = NetworkManager()
    private let retrier: RequestRetrier
    private let rateLimiter: RateLimiter
    private let session: any URLSessionProtocol

    // 通用缓存（用于JSON数据）
    private let dataCache = NSCache<NSString, CachedData<Any>>()
    private var dataCacheKeys = Set<String>() // 跟踪数据缓存的键

    // 图片缓存
    private let imageCache = NSCache<NSString, CachedData<UIImage>>()
    private var imageCacheKeys = Set<String>() // 跟踪图片缓存的键

    private let requestConcurrency = RequestConcurrencyLimiter(limit: 8)

    override private init() {
        retrier = RequestRetrier()
        rateLimiter = RateLimiter()

        // 总是使用 URLSessionProxy 来记录网络请求日志
        // 这样网络日志总是被记录，只是用户界面上的查看按钮受 enableLogging 控制
        // 配置 NetworkLogger，使用与 Logger 相同的 LoggerStore
        var configuration = NetworkLogger.Configuration()
        // 配置敏感信息过滤（自动将敏感头信息替换为 <private>）
        configuration.sensitiveHeaders = ["Authorization", "Access-Token", "X-Auth-Token"]
        configuration.sensitiveQueryItems = ["token", "key", "password"]

        // 创建 NetworkLogger，使用与 Logger 相同的 LoggerStore
        // 这样所有日志（文本日志和网络日志）都会存储在同一个地方
        let loggerStore = Logger.shared.loggerStore
        let networkLogger = NetworkLogger(store: loggerStore, configuration: configuration)

        // 使用 URLSessionProxy 包装 URLSession
        // URLSessionProxy 会自动记录所有网络请求到 Pulse
        // 直接使用 URLSessionProxy 而不是它的 session 属性，这样才能正确拦截 async/await 方法
        session = URLSessionProxy(configuration: .default, logger: networkLogger)

        super.init()

        // 设置缓存限制
        dataCache.countLimit = 100
        imageCache.countLimit = 200

        // 设置缓存删除时的回调
        dataCache.delegate = self
        imageCache.delegate = self
    }

    /// 内部方法：执行请求并返回 Data 与 HTTPURLResponse，供 fetchData 等复用
    private func fetchDataWithResponse(
        from url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String]? = nil,
        forceRefresh: Bool = false,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        try checkRateLimitCooldown()
        try await requestConcurrency.acquire()
        defer { requestConcurrency.release() }

        try Task.checkCancellation()
        try await rateLimiter.waitForPermission()

        var request = URLRequest(url: url)
        request.httpMethod = method

        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("tranquility", forHTTPHeaderField: "datasource")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(
            "Tritanium_v\(AppConfiguration.Version.fullVersion)_mail:tritanium_support@icloud.com",
            forHTTPHeaderField: "User-Agent"
        )

        if method == "POST", body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = body
            if method == "POST", let jsonString = String(data: body, encoding: .utf8) {
                Logger.debug("POST Request Body: \(jsonString)")
            }
        }

        return try await performRequest(
            request: request,
            url: url,
            noRetryKeywords: noRetryKeywords,
            timeouts: timeouts
        )
    }

    /// 通用的数据获取函数
    func fetchData(
        from url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String]? = nil,
        forceRefresh: Bool = false,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        let (data, _) = try await fetchDataWithResponse(
            from: url,
            method: method,
            body: body,
            headers: headers,
            forceRefresh: forceRefresh,
            noRetryKeywords: noRetryKeywords,
            timeouts: timeouts
        )
        return data
    }

    /// 内部方法：执行请求并返回 Data 与 HTTPURLResponse
    private func performRequest(
        request: URLRequest,
        url: URL,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        return try await retrier.execute(noRetryKeywords: noRetryKeywords, timeouts: timeouts) {
            try await Task.detached(priority: .userInitiated) {
                let sendTime = Date()
                let (data, response) = try await self.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("无效的HTTP响应 - URL: \(url.absoluteString)")
                    throw NetworkError.invalidResponse
                }

                // 有限流头即记录（含 429），用于设置页网络限流监视器
                ESIRateLimitInterceptor.intercept(url: url, response: httpResponse, sendTime: sendTime)

                // 检查成功状态码（200 OK, 201 Created, 204 No Content）
                guard [200, 201, 204].contains(httpResponse.statusCode) else {
                    // 429 时也解析并触发频率限制弹窗
                    if httpResponse.statusCode == 429 {
                        let rateLimitInfo = RateLimitInfo(from: httpResponse)
                        if (rateLimitInfo.remaining ?? 1) <= 0 {
                            Task { @MainActor in
                                RateLimitAlertManager.shared.showRateLimitAlert()
                            }
                        }
                    }
                    if let responseBody = String(data: data, encoding: .utf8) {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体: \(responseBody)")
                        throw NetworkError.httpError(
                            statusCode: httpResponse.statusCode, message: responseBody
                        )
                    } else {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体无法解析")
                        throw NetworkError.httpError(statusCode: httpResponse.statusCode)
                    }
                }
                // 解析频率限制信息
                let rateLimitInfo = RateLimitInfo(from: httpResponse)
                if rateLimitInfo.remaining ?? 100 <= 20 {
                    Logger.warning("[HTTP-Response] URL: \(url.absoluteString), Code: \(httpResponse.statusCode), Body Length: \(data.count) bytes, Rate Limit: \(rateLimitInfo.logString)")
                }
                if (rateLimitInfo.remaining ?? 1) <= 0 {
                    Task { @MainActor in
                        RateLimitAlertManager.shared.showRateLimitAlert()
                    }
                }
                return (data, httpResponse)
            }.value
        }
    }

    /// 清除所有缓存
    func clearAllCaches() async {
        await withCheckedContinuation { continuation in
            Task { @NetworkManagerActor in
                // 清除内存缓存
                dataCache.removeAllObjects()
                dataCacheKeys.removeAll()

                imageCache.removeAllObjects()
                imageCacheKeys.removeAll()

                continuation.resume()
            }
        }

        // 清除文件缓存
        await clearFileCaches()
    }

    private func clearFileCaches() async {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let staticDataSetPath = paths[0].appendingPathComponent("StaticDataSet")

        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(
                at: staticDataSetPath, includingPropertiesForKeys: nil
            )

            for url in contents {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileSize = attributes[.size] as? Int64
                {
                    Logger.info(
                        "Deleting file: \(url.lastPathComponent) (Size: \(FormatUtil.formatFileSize(fileSize)))"
                    )
                    try? FileManager.default.removeItem(at: url)
                }
            }

            Logger.info("Finished clearing StaticDataSet directory")
        } catch {
            try? FileManager.default.createDirectory(
                at: staticDataSetPath, withIntermediateDirectories: true
            )
            Logger.error("Error accessing StaticDataSet directory: \(error)")
        }
    }

    /// 专门用于需访问令牌的请求
    func fetchDataWithToken(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        forceRefresh: Bool = false,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }
        Logger.debug("Fetch data with token \(token.prefix(8))......")
        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(
            from: url,
            headers: allHeaders,
            forceRefresh: forceRefresh,
            noRetryKeywords: noRetryKeywords,
            timeouts: timeouts
        )
    }

    /// POST请求带Token的方法
    func postDataWithToken(
        to url: URL,
        body: Data,
        characterId: Int,
        headers: [String: String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 使用基础的 fetchData 方法获取数据
        return try await fetchData(
            from: url,
            method: "POST",
            body: body,
            headers: allHeaders,
            timeouts: timeouts
        )
    }

    /// DELETE请求带Token的方法
    func deleteDataWithToken(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil
    ) async throws -> Data {
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 使用基础的 fetchData 方法发送DELETE请求
        return try await fetchData(
            from: url,
            method: "DELETE",
            headers: allHeaders,
            noRetryKeywords: noRetryKeywords
        )
    }

    /// 专门用于需访问令牌的请求，并返回响应头中的页数信息
    func fetchDataWithTokenAndPages(
        from url: URL,
        characterId: Int,
        headers: [String: String]? = nil,
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil
    ) async throws -> (Data, Int) {
        try checkRateLimitCooldown()
        // 获取角色的token
        let token = try await AuthTokenManager.shared.getAccessToken(for: characterId)

        // 创建基本请求头
        var allHeaders: [String: String] = [
            "Authorization": "Bearer \(token)",
            "datasource": "tranquility",
            "Accept": "application/json",
        ]

        // 添加自定义请求头
        headers?.forEach { key, value in
            allHeaders[key] = value
        }

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // 添加请求头
        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return try await retrier.execute(noRetryKeywords: noRetryKeywords, timeouts: timeouts) {
            Logger.info("HTTP GET Request to: \(url)")

            return try await Task.detached(priority: .userInitiated) {
                let sendTime = Date()
                let (data, response) = try await self.session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.error("无效的HTTP响应 - URL: \(url.absoluteString)")
                    throw NetworkError.invalidResponse
                }

                ESIRateLimitInterceptor.intercept(url: url, response: httpResponse, sendTime: sendTime)

                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 429 {
                        let rateLimitInfo = RateLimitInfo(from: httpResponse)
                        if (rateLimitInfo.remaining ?? 1) <= 0 {
                            Task { @MainActor in
                                RateLimitAlertManager.shared.showRateLimitAlert()
                            }
                        }
                    }
                    if let responseBody = String(data: data, encoding: .utf8) {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体: \(responseBody)")
                        throw NetworkError.httpError(
                            statusCode: httpResponse.statusCode, message: responseBody
                        )
                    } else {
                        Logger.error("HTTP请求失败 - URL: \(url.absoluteString)")
                        Logger.error("状态码: \(httpResponse.statusCode)")
                        Logger.error("响应体无法解析")
                        throw NetworkError.httpError(statusCode: httpResponse.statusCode)
                    }
                }

                // 从响应头中获取总页数
                let totalPages = Int(httpResponse.value(forHTTPHeaderField: "X-Pages") ?? "1") ?? 1
                Logger.info("获取到总页数: \(totalPages)")

                return (data, totalPages)
            }.value
        }
    }

    /// 处理分页数据的通用方法
    /// - Parameters:
    ///   - baseUrl: 基础URL，不包含页码参数
    ///   - characterId: 角色ID，用于获取访问令牌
    ///   - maxConcurrentPages: 最大并发请求数
    ///   - decoder: 用于解码数据的闭包
    ///   - progressCallback: 进度回调闭包，提供当前页数和总页数
    /// - Returns: 解码后的数据数组
    func fetchPaginatedData<T>(
        from baseUrl: URL,
        characterId: Int,
        maxConcurrentPages: Int = 3,
        decoder: @escaping (Data) throws -> [T],
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> [T] {
        var allItems: [T] = []

        // 构建第一页的URL
        let firstPageUrlString =
            baseUrl.absoluteString + (baseUrl.absoluteString.contains("?") ? "&" : "?") + "page=1"
        guard let firstPageUrl = URL(string: firstPageUrlString) else {
            throw NetworkError.invalidURL
        }

        Logger.info("开始获取第1页数据")

        // 获取第一页数据和总页数
        let (firstPageData, totalPages) = try await fetchDataWithTokenAndPages(
            from: firstPageUrl,
            characterId: characterId,
            timeouts: [2, 10, 15, 15, 15]
        )

        progressCallback?(1, totalPages)

        let firstPageItems = try decoder(firstPageData)
        Logger.success("成功获取第1页数据，本页包含\(firstPageItems.count)个项目")
        allItems.append(contentsOf: firstPageItems)

        // 如果有多页，使用并发获取剩余页面
        if totalPages > 1 {
            Logger.info("检测到总共有\(totalPages)页数据，开始并发获取剩余页面")

            do {
                try await withThrowingTaskGroup(of: (page: Int, items: [T]).self) { group in
                    var currentPage = 2
                    var inProgressPages = 0
                    var completedPages = Set<Int>()
                    completedPages.insert(1) // 第一页已完成

                    // 添加初始任务
                    while currentPage <= totalPages, inProgressPages < maxConcurrentPages {
                        let page = currentPage
                        group.addTask(priority: .userInitiated) {
                            let pageUrlString =
                                baseUrl.absoluteString
                                    + (baseUrl.absoluteString.contains("?") ? "&" : "?")
                                    + "page=\(page)"
                            guard let pageUrl = URL(string: pageUrlString) else {
                                throw NetworkError.invalidURL
                            }

                            Logger.info("开始获取第\(page)页数据")

                            let data = try await self.fetchDataWithToken(
                                from: pageUrl,
                                characterId: characterId,
                                timeouts: [2, 10, 15, 15, 15]
                            )

                            let pageItems = try decoder(data)
                            Logger.success("成功获取第\(page)页数据，本页包含\(pageItems.count)个项目")

                            // 添加短暂延迟以避免请求过于频繁
                            try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000)) // 500ms延迟

                            return (page: page, items: pageItems)
                        }
                        currentPage += 1
                        inProgressPages += 1
                    }

                    // 处理完成的任务并添加新任务
                    for try await result in group {
                        allItems.append(contentsOf: result.items)
                        completedPages.insert(result.page)
                        inProgressPages -= 1

                        // 更新进度回调
                        progressCallback?(completedPages.count, totalPages)

                        // 如果还有更多页面要获取，添加新任务
                        if currentPage <= totalPages {
                            let page = currentPage
                            group.addTask(priority: .userInitiated) {
                                let pageUrlString =
                                    baseUrl.absoluteString
                                        + (baseUrl.absoluteString.contains("?") ? "&" : "?")
                                        + "page=\(page)"
                                guard let pageUrl = URL(string: pageUrlString) else {
                                    throw NetworkError.invalidURL
                                }

                                Logger.info("开始获取第\(page)页数据")

                                let data = try await self.fetchDataWithToken(
                                    from: pageUrl,
                                    characterId: characterId,
                                    timeouts: [2, 10, 15, 15, 15]
                                )

                                let pageItems = try decoder(data)
                                Logger.success("成功获取第\(page)页数据，本页包含\(pageItems.count)个项目")

                                // 添加短暂延迟以避免请求过于频繁
                                try await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000)) // 500ms延迟

                                return (page: page, items: pageItems)
                            }
                            currentPage += 1
                            inProgressPages += 1
                        }
                    }

                    // 检查是否所有页面都已获取
                    if completedPages.count != totalPages {
                        let missingPages = Set(1 ... totalPages).subtracting(completedPages)
                        Logger.warning("部分页面未能获取: \(missingPages)")
                    }
                }
            } catch {
                // 如果是取消错误，直接抛出
                if error is CancellationError {
                    throw error
                }

                // 对于其他错误，如果已经获取了一些数据，记录错误但继续返回已获取的数据
                if !allItems.isEmpty {
                    Logger.error("获取部分页面时出错: \(error)，但已获取\(allItems.count)个项目")
                } else {
                    // 如果没有获取到任何数据，则抛出错误
                    throw error
                }
            }
        }

        Logger.info("数据获取完成，共\(allItems.count)个项目")
        return allItems
    }
}

/// 网络错误枚举
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String? = nil)
    case invalidImageData
    case noValidPrice
    case invalidData
    case refreshTokenExpired
    case unauthed
    case invalidToken(String)
    case maxRetriesExceeded
    case authenticationError(String)
    case decodingError(Error)
    case rateLimitCooldown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Network_Error_Invalid_URL", comment: "")
        case .invalidResponse:
            return NSLocalizedString("Network_Error_Invalid_Response", comment: "")
        case let .httpError(statusCode, message):
            if let message = message {
                return
                    "\(String(format: NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode)): \(message)"
            }
            return String(
                format: NSLocalizedString("Network_Error_HTTP_Error", comment: ""), statusCode
            )
        case .invalidImageData:
            return NSLocalizedString("Network_Error_Invalid_Image", comment: "")
        case .noValidPrice:
            return NSLocalizedString("Network_Error_No_Price", comment: "")
        case .invalidData:
            return NSLocalizedString("Network_Error_Invalid_Data", comment: "")
        case .refreshTokenExpired:
            return NSLocalizedString("Network_Error_Token_Expired", comment: "")
        case .unauthed:
            return NSLocalizedString("Network_Error_Unauthed", comment: "")
        case let .invalidToken(reason):
            return "Invaild Token:\(reason)"
        case .maxRetriesExceeded:
            return "Max Retries Exceeded"
        case let .authenticationError(reason):
            return "Authentication Error: \(reason)"
        case let .decodingError(error):
            return "Decoding Error: \(error)"
        case .rateLimitCooldown:
            return NSLocalizedString("Network_Error_RateLimit_Cooldown", comment: "")
        }
    }
}

extension NetworkManager: NSCacheDelegate {
    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // 当缓存项被移除时，从对应的键集合中移除键
        Task { @NetworkManagerActor in
            if cache === self.dataCache {
                if let key = obj as? NSString {
                    self.dataCacheKeys.remove(key as String)
                }
            } else if cache === self.imageCache {
                if let key = obj as? NSString {
                    self.imageCacheKeys.remove(key as String)
                }
            }
        }
    }
}

/// 添加 RequestRetrier 类
class RequestRetrier {
    private let defaultTimeouts: [TimeInterval]
    private let retryDelay: TimeInterval
    private var noRetryKeywords: [String]

    init(
        defaultTimeouts: [TimeInterval] = [1.5, 3, 5, 20, 20, 20], retryDelay: TimeInterval = 0,
        noRetryKeywords: [String] = []
    ) {
        self.defaultTimeouts = defaultTimeouts
        self.retryDelay = retryDelay
        self.noRetryKeywords = noRetryKeywords
    }

    func execute<T>(
        noRetryKeywords: [String]? = nil,
        timeouts: [TimeInterval]? = nil,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        // 使用自定义超时序列或默认序列
        let effectiveTimeouts = timeouts ?? defaultTimeouts

        // 合并默认的和临时的不重试关键词
        let keywords = Set(self.noRetryKeywords + (noRetryKeywords ?? []))
        var attempts = 0
        var lastError: Error?

        while attempts < effectiveTimeouts.count {
            do {
                // 设置当前尝试的超时时间
                let timeout = effectiveTimeouts[attempts]
                Logger.info("尝试第 \(attempts + 1) 次请求，超时时间: \(timeout)秒")

                return try await withTimeout(timeout) {
                    try await operation()
                }
            } catch {
                lastError = error

                // 检查是否应该重试
                if !shouldRetry(error, keywords: keywords) {
                    throw error
                }

                attempts += 1
                if attempts < effectiveTimeouts.count {
                    let delay = UInt64(retryDelay * pow(2.0, Double(attempts))) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? NetworkError.maxRetriesExceeded
    }

    private func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T)
        async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 添加实际操作任务
            group.addTask(priority: .userInitiated) {
                try await operation()
            }

            // 添加超时任务
            group.addTask(priority: .userInitiated) {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NetworkError.httpError(statusCode: 408, message: "请求超时")
            }

            defer {
                group.cancelAll()
            }

            // 等待第一个完成的任务
            do {
                return try await group.next()
                    ?? {
                        throw NetworkError.httpError(statusCode: 408, message: "请求超时")
                    }()
            } catch {
                // 取消所有任务并抛出错误
                group.cancelAll()
                throw error
            }
        }
    }

    private func shouldRetry(_ error: Error, keywords: Set<String>) -> Bool {
        // 首先检查是否是网络错误
        if case let NetworkError.httpError(statusCode, message) = error {
            // 如果响应中包含不重试的关键词，则不重试
            if let errorMessage = message,
               keywords.contains(where: { errorMessage.contains($0) })
            {
                Logger.info("检测到不重试关键词，停止重试")
                return false
            }

            // 对于特定状态码才重试
            return [408, 500, 502, 503, 504].contains(statusCode)
        }
        return false
    }
}

@NetworkManagerActor
final class RequestConcurrencyLimiter {
    private var available: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) {
        precondition(limit > 0)
        available = limit
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { @NetworkManagerActor in
                self.cancelWaiter(id)
            }
        }

        // A cancellation can arrive after release has already handed off the slot.
        if Task.isCancelled {
            release()
            throw CancellationError()
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

/// 添加 RateLimiter 类
actor RateLimiter {
    private var tokens: Int
    private let maxTokens: Int
    private var lastRefill: Date
    private let refillRate: Double // tokens per second

    init(maxTokens: Int = 150, refillRate: Double = 50) {
        self.maxTokens = maxTokens
        tokens = maxTokens
        lastRefill = Date()
        self.refillRate = refillRate
    }

    private func refillTokens() {
        let now = Date()
        let timePassed = now.timeIntervalSince(lastRefill)
        let tokensToAdd = Int(timePassed * refillRate)

        tokens = min(maxTokens, tokens + tokensToAdd)
        lastRefill = now
    }

    func waitForPermission() async throws {
        while tokens <= 0 {
            refillTokens()
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        tokens -= 1
    }
}
