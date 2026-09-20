import Foundation
import UIKit

// MARK: - 缓存元数据模型

struct ImageCacheMetadata: Codable {
    let etag: String?
    let path: String
    let lastModified: Date
    let cachedAt: Date // 缓存时间

    init(etag: String?, path: String) {
        self.etag = etag
        self.path = path
        lastModified = Date()
        cachedAt = Date()
    }

    /// 检查缓存是否过期（针对无 ETag 的情况）
    func isExpired(timeoutHours: Double = 8) -> Bool {
        let elapsed = Date().timeIntervalSince(cachedAt) / 3600
        return elapsed > timeoutHours
    }
}

// MARK: - 图片缓存管理器

@globalActor actor ImageCacheManagerActor {
    static let shared = ImageCacheManagerActor()
}

@ImageCacheManagerActor
class ImageCacheManager {
    static let shared = ImageCacheManager()

    // MARK: - 常量配置

    private let cacheDirectoryName = "image_cache"
    private let metadataKey = "ImageCacheMetadataMap"
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB

    // MARK: - 私有属性

    private var metadataMap: [String: ImageCacheMetadata] = [:]
    private let fileManager = FileManager.default
    private var downloadTasks: [String: Task<UIImage, Error>] = [:]

    // MARK: - 初始化

    private init() {
        loadMetadata()
        createCacheDirectoryIfNeeded()
    }

    // MARK: - 缓存目录管理

    private func getCacheDirectory() -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(cacheDirectoryName)
    }

    private func createCacheDirectoryIfNeeded() {
        let cacheDir = getCacheDirectory()
        if !fileManager.fileExists(atPath: cacheDir.path) {
            do {
                try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                Logger.info("创建缓存目录: \(cacheDir.path)")
            } catch {
                Logger.error("创建缓存目录失败: \(error)")
            }
        }
    }

    // MARK: - 元数据管理

    private func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: metadataKey),
           let decoded = try? JSONDecoder().decode([String: ImageCacheMetadata].self, from: data)
        {
            metadataMap = decoded
            Logger.info("加载元数据: \(metadataMap.count) 条记录")
        }
    }

    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(metadataMap)
            UserDefaults.standard.set(data, forKey: metadataKey)
            Logger.debug("保存元数据: \(metadataMap.count) 条记录")
        } catch {
            Logger.error("保存元数据失败: \(error)")
        }
    }

    // MARK: - 公共接口

    /// 获取图片（带缓存和 ETag 验证）
    /// - Parameters:
    ///   - url: 图片 URL
    ///   - forceRefresh: 是否强制刷新
    ///   - backgroundUpdate: 是否在后台更新（先返回缓存，后台验证更新）
    /// - Returns: UIImage
    func fetchImage(from url: URL, forceRefresh: Bool = false, backgroundUpdate: Bool = true) async throws -> UIImage {
        let urlString = url.absoluteString

        // 检查是否已有正在进行的下载任务
        if let existingTask = downloadTasks[urlString] {
            Logger.debug("复用现有下载任务: \(urlString)")
            return try await existingTask.value
        }

        // 如果启用后台更新且不是强制刷新
        if backgroundUpdate && !forceRefresh {
            // 先尝试从缓存加载
            if let cachedImage = try await loadImageFromCacheWithoutValidation(url: url) {
                // Logger.info("返回缓存图片，后台验证更新: \(urlString)")

                // 在后台验证并更新
                Task { @ImageCacheManagerActor in
                    do {
                        try await validateAndUpdateCache(url: url)
                    } catch {
                        Logger.debug("后台更新失败: \(error)")
                    }
                }

                return cachedImage
            }
        }

        // 创建新的下载任务
        let task = Task<UIImage, Error> {
            defer {
                // 任务完成后移除
                Task { @ImageCacheManagerActor in
                    downloadTasks.removeValue(forKey: urlString)
                }
            }

            // 如果不是强制刷新，先尝试从缓存加载（带验证）
            if !forceRefresh, let cachedImage = try await loadImageFromCache(url: url) {
                // Logger.info("从缓存加载图片: \(urlString)")
                return cachedImage
            }

            // 从网络下载
            return try await downloadAndCacheImage(url: url)
        }

        downloadTasks[urlString] = task
        return try await task.value
    }

    /// 从缓存加载图片（不进行验证，直接返回）
    private func loadImageFromCacheWithoutValidation(url: URL) async throws -> UIImage? {
        let urlString = url.absoluteString

        guard let metadata = metadataMap[urlString] else {
            Logger.debug("缓存未命中: \(urlString)")
            return nil
        }

        // 对于无 ETag 的图片，检查是否过期（8小时）
        if metadata.etag == nil || metadata.etag?.isEmpty == true {
            if metadata.isExpired(timeoutHours: 8) {
                Logger.debug("无 ETag 缓存已过期（8小时）: \(urlString)")
                return nil
            }
        }

        let cacheDir = getCacheDirectory()
        let imagePath = cacheDir.appendingPathComponent(metadata.path)

        guard fileManager.fileExists(atPath: imagePath.path) else {
            Logger.warning("缓存文件不存在: \(imagePath.path)")
            metadataMap.removeValue(forKey: urlString)
            saveMetadata()
            return nil
        }

        // 加载图片
        guard let data = try? Data(contentsOf: imagePath),
              let image = UIImage(data: data)
        else {
            Logger.error("加载图片数据失败: \(imagePath.path)")
            try? fileManager.removeItem(at: imagePath)
            metadataMap.removeValue(forKey: urlString)
            saveMetadata()
            return nil
        }

        return image
    }

    /// 从缓存加载图片（带验证）
    private func loadImageFromCache(url: URL) async throws -> UIImage? {
        let urlString = url.absoluteString

        guard let metadata = metadataMap[urlString] else {
            Logger.debug("缓存未命中: \(urlString)")
            return nil
        }

        let cacheDir = getCacheDirectory()
        let imagePath = cacheDir.appendingPathComponent(metadata.path)

        guard fileManager.fileExists(atPath: imagePath.path) else {
            Logger.warning("缓存文件不存在: \(imagePath.path)")
            // 清理无效的元数据
            metadataMap.removeValue(forKey: urlString)
            saveMetadata()
            return nil
        }

        // 验证 ETag
        if let etag = metadata.etag, !etag.isEmpty {
            let isValid = try await validateETag(url: url, cachedETag: etag)
            if !isValid {
                Logger.error("ETag 验证失败，需要重新下载: \(urlString)")
                return nil
            }
        } else {
            // 无 ETag 的情况，检查时间是否过期（8小时）
            if metadata.isExpired(timeoutHours: 8) {
                // Logger.info("无 ETag 缓存已过期（8小时），需要重新下载: \(urlString)")
                return nil
            }
        }

        // 加载图片
        guard let data = try? Data(contentsOf: imagePath),
              let image = UIImage(data: data)
        else {
            Logger.error("加载图片数据失败: \(imagePath.path)")
            // 清理损坏的缓存
            try? fileManager.removeItem(at: imagePath)
            metadataMap.removeValue(forKey: urlString)
            saveMetadata()
            return nil
        }

        return image
    }

    /// 后台验证并更新缓存
    private func validateAndUpdateCache(url: URL) async throws {
        let urlString = url.absoluteString

        guard let metadata = metadataMap[urlString] else {
            return
        }

        // 如果有 ETag，验证是否需要更新
        if let etag = metadata.etag, !etag.isEmpty {
            let isValid = try await validateETag(url: url, cachedETag: etag)
            if !isValid {
                // Logger.info("后台检测到更新，重新下载: \(urlString)")
                _ = try await downloadAndCacheImage(url: url)
            }
        } else {
            // 无 ETag 的情况，检查是否过期（8小时）
            if metadata.isExpired(timeoutHours: 8) {
                // Logger.info("后台检测到缓存过期，重新下载: \(urlString)")
                _ = try await downloadAndCacheImage(url: url)
            }
        }
    }

    /// 验证 ETag
    private func validateETag(url: URL, cachedETag: String) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               let serverETag = httpResponse.value(forHTTPHeaderField: "ETag")
            {
                return serverETag == cachedETag
                // Logger.debug("ETag 验证: 缓存=\(cachedETag), 服务器=\(serverETag), 有效=\(isValid)")
            }

            // 如果服务器不返回 ETag，认为缓存有效
            // Logger.debug("服务器未返回 ETag，使用缓存")
            return true
        } catch {
            // 网络错误时使用缓存
            Logger.warning("ETag 验证失败，使用缓存: \(error)")
            return true
        }
    }

    /// 下载并缓存图片
    private func downloadAndCacheImage(url: URL) async throws -> UIImage {
        let urlString = url.absoluteString

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        Logger.info("开始下载: \(urlString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageCacheError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            Logger.error("下载失败，状态码: \(httpResponse.statusCode)")
            throw ImageCacheError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let image = UIImage(data: data) else {
            Logger.error("图片数据无效")
            throw ImageCacheError.invalidImageData
        }

        // 获取 ETag
        let etag = httpResponse.value(forHTTPHeaderField: "ETag")

        // 保存原始图片数据到磁盘（不进行格式转换）
        try await saveImageToCache(imageData: data, url: url, etag: etag)

        // Logger.info("下载完成: \(urlString), 大小: \(data.count) bytes, ETag: \(etag ?? "无")")

        return image
    }

    /// 保存图片到缓存（保存原始数据，不进行格式转换）
    private func saveImageToCache(imageData: Data, url: URL, etag: String?) async throws {
        let urlString = url.absoluteString
        let cacheDir = getCacheDirectory()

        // 生成唯一文件名（不指定扩展名，保持原始格式）
        let fileName = UUID().uuidString
        let filePath = cacheDir.appendingPathComponent(fileName)

        // 如果已有旧缓存，先删除
        if let oldMetadata = metadataMap[urlString] {
            let oldPath = cacheDir.appendingPathComponent(oldMetadata.path)
            try? fileManager.removeItem(at: oldPath)
            Logger.debug("删除旧缓存: \(oldPath.path)")
        }

        // 直接写入原始数据
        try imageData.write(to: filePath)

        // 更新元数据
        let metadata = ImageCacheMetadata(etag: etag, path: fileName)
        metadataMap[urlString] = metadata
        saveMetadata()

        // Logger.info("保存图片: \(fileName), 大小: \(imageData.count) bytes")

        // 检查缓存大小
        await checkCacheSizeAndCleanup()
    }

    // MARK: - 缓存清理

    /// 检查缓存大小并清理
    private func checkCacheSizeAndCleanup() async {
        let cacheDir = getCacheDirectory()
        var totalSize: Int64 = 0
        var files: [(url: URL, size: Int64, modifiedDate: Date)] = []

        guard let enumerator = fileManager.enumerator(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        // 统计所有文件
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                if let size = resourceValues.fileSize,
                   let modifiedDate = resourceValues.contentModificationDate
                {
                    totalSize += Int64(size)
                    files.append((fileURL, Int64(size), modifiedDate))
                }
            } catch {
                Logger.error("获取文件信息失败: \(error)")
            }
        }

        Logger.debug("当前缓存大小: \(FormatUtil.formatFileSize(totalSize))")

        // 如果超过限制，清理最旧的文件
        if totalSize > maxCacheSize {
            Logger.warning("缓存超过限制，开始清理")

            // 按修改时间排序（最旧的在前）
            files.sort { $0.modifiedDate < $1.modifiedDate }

            var sizeToFree = totalSize - maxCacheSize + (maxCacheSize / 10) // 多清理10%

            for file in files {
                if sizeToFree <= 0 {
                    break
                }

                // 删除文件
                try? fileManager.removeItem(at: file.url)

                // 从元数据中移除
                let fileName = file.url.lastPathComponent
                if let entry = metadataMap.first(where: { $0.value.path == fileName }) {
                    metadataMap.removeValue(forKey: entry.key)
                    Logger.debug("清理缓存: \(fileName)")
                }

                sizeToFree -= file.size
            }

            saveMetadata()
            Logger.success("缓存清理完成")
        }
    }

    /// 清空所有缓存
    func clearAllCache() {
        let cacheDir = getCacheDirectory()

        do {
            if fileManager.fileExists(atPath: cacheDir.path) {
                try fileManager.removeItem(at: cacheDir)
                createCacheDirectoryIfNeeded()
            }

            metadataMap.removeAll()
            saveMetadata()

            Logger.info("清空所有缓存")
        } catch {
            Logger.error("清空缓存失败: \(error)")
        }
    }
}

// MARK: - 错误类型

enum ImageCacheError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无效的响应"
        case let .httpError(statusCode):
            return "HTTP 错误: \(statusCode)"
        case .invalidImageData:
            return "无效的图片数据"
        }
    }
}
