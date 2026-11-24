import Foundation
import SwiftUI
import UIKit
import Zip

class IconManager {
    static let shared = IconManager()

    /// 分类 / 分组缺省图标
    static let defaultIcon = "category"
    /// 物品缺省图标
    static let defaultItemIcon = "not_found"

    private let fileManager = FileManager.default
    private var imageCache = NSCache<NSString, UIImage>()
    private var iconsDirectory: URL?
    private var typeIconsDirectory: URL?
    private let defaults = UserDefaults.standard
    private let extractionStateKey = "IconExtractionComplete"

    private init() {
        setupIconsDirectory()
        setupTypeIconsDirectory()
    }

    private func setupIconsDirectory() {
        let iconsDir = LocalSDELayout.iconsDirectory
        if !fileManager.fileExists(atPath: iconsDir.path) {
            try? fileManager.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        }
        iconsDirectory = iconsDir
        Logger.info("Icons directory setup at: \(iconsDir.path)")
    }

    /// 解压完成后更新图标根目录
    func adoptIconsDirectory(_ url: URL) {
        iconsDirectory = url
    }

    private func setupTypeIconsDirectory() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let typeIconsDir = documentsURL.appendingPathComponent("type_icons")

        // 如果类型图标目录不存在，创建它
        if !fileManager.fileExists(atPath: typeIconsDir.path) {
            try? fileManager.createDirectory(at: typeIconsDir, withIntermediateDirectories: true)
        }

        typeIconsDirectory = typeIconsDir
        Logger.info("Type icons directory setup at: \(typeIconsDir.path)")
    }

    var isExtractionComplete: Bool {
        get {
            Logger.debug("正在从 UserDefaults 读取键: \(extractionStateKey)")
            return defaults.bool(forKey: extractionStateKey)
        }
        set {
            Logger.debug("正在写入 UserDefaults，键: \(extractionStateKey), 值: \(newValue)")
            defaults.set(newValue, forKey: extractionStateKey)
        }
    }

    /// 从图标名称中提取ID
    private func extractTypeID(from iconName: String) -> Int? {
        // 检查是否以"icon_"开头
        guard iconName.hasPrefix("icon_") else {
            return nil
        }

        // 使用正则表达式提取ID
        let pattern = "icon_(\\d+)_"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsString = iconName as NSString
        let matches = regex.matches(
            in: iconName, options: [], range: NSRange(location: 0, length: nsString.length)
        )

        guard let match = matches.first, match.numberOfRanges > 1 else {
            return nil
        }

        let idRange = match.range(at: 1)
        let idString = nsString.substring(with: idRange)

        return Int(idString)
    }

    /// 从磁盘加载类型图标
    private func loadTypeIconFromDisk(iconName: String) -> UIImage? {
        guard let typeIconsDirectory = typeIconsDirectory else {
            return nil
        }

        let iconURL = typeIconsDirectory.appendingPathComponent(iconName)
        if let imageData = try? Data(contentsOf: iconURL),
           let image = UIImage(data: imageData)
        {
            return image
        }

        return nil
    }

    /// 同步从在线API获取图标
    func loadTypeIconFromAPISync(typeID: Int, size: Int = 64) -> UIImage? {
        let iconName = "icon_\(typeID)_\(size).png"

        // 检查缓存目录中是否已存在
        if let image = loadTypeIconFromDisk(iconName: iconName) {
            return image
        }

        // 构建API URL
        let urlString = "https://images.evetech.net/types/\(typeID)/icon?size=\(size)"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL: \(urlString)")
            return nil
        }

        // 使用同步方式下载图像
        var resultImage: UIImage?
        let destination = typeIconsDirectory?.appendingPathComponent(iconName)
        guard let destination = destination else {
            Logger.error("Type icons directory is not set")
            return nil
        }

        // 为每次下载创建新的信号量
        let semaphore = DispatchSemaphore(value: 0)

        // 创建同步下载任务
        let downloadTask = URLSession.shared.dataTask(with: url) { data, response, error in
            defer {
                semaphore.signal()
            }

            if let error = error {
                Logger.error("Failed to download type icon: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                Logger.error("Invalid response for type icon download")
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                Logger.error("Failed to create image from downloaded data")
                return
            }

            // 保存到磁盘
            do {
                try data.write(to: destination)
                Logger.info("Saved type icon to disk: \(iconName)")
                resultImage = image
            } catch {
                Logger.error("Failed to save type icon to disk: \(error.localizedDescription)")
            }
        }

        // 启动下载任务并等待完成
        downloadTask.resume()

        // 设置超时时间为5秒
        let timeout = DispatchTime.now() + .seconds(5)
        if case .timedOut = semaphore.wait(timeout: timeout) {
            Logger.warning("Download timed out for type icon: \(iconName)")
            return UIImage(named: "not_found") ?? UIImage()
        }

        return resultImage ?? UIImage(named: "not_found") ?? UIImage()
    }

    func loadLocalUIImage(for iconName: String) -> UIImage? {
        // 从解压后的目录中读取图片
        guard let iconsDirectory = iconsDirectory else {
            Logger.error("Icons directory is not set")
            return nil
        }

        // 尝试不同的扩展名组合
        let possibleNames = [
            iconName,
            iconName.lowercased(),
            iconName.replacingOccurrences(of: ".png", with: ".PNG"),
        ]

        for name in possibleNames {
            let iconURL = iconsDirectory.appendingPathComponent(name)
            if let imageData = try? Data(contentsOf: iconURL),
               let image = UIImage(data: imageData)
            {
                return image
            }
        }

        // 检查是否是类型图标（以"icon_"开头）
        return extractTypeID(from: iconName) == nil ? nil : loadTypeIconFromDisk(iconName: iconName)
    }

    func loadUIImage(for iconName: String) -> UIImage {
        let cacheKey = NSString(string: iconName)
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        if let image = loadLocalUIImage(for: iconName) {
            imageCache.setObject(image, forKey: cacheKey)
            return image
        }
        // 如果是类型图标但未找到，尝试同步加载
        if let typeID = extractTypeID(from: iconName) {
            if let downloadedImage = loadTypeIconFromAPISync(typeID: typeID) {
                imageCache.setObject(downloadedImage, forKey: cacheKey)
                return downloadedImage
            }
        }

        // 兜底：加载 Asset Catalog 的 not_found 图标并缓存，避免重复查找与日志
        Logger.warning("Failed to load image: \(iconName)")
        let fallback = UIImage(named: "not_found") ?? UIImage()
        imageCache.setObject(fallback, forKey: cacheKey)
        return fallback
    }

    func loadImage(for iconName: String) -> Image {
        // 先尝试从 Assets 加载
        if let uiImage = UIImage(named: iconName.replacingOccurrences(of: ".png", with: "")) {
            return Image(uiImage: uiImage)
        }

        // 如果 Assets 中找不到，从本地文件加载
        return Image(uiImage: loadUIImage(for: iconName))
    }

    func preloadCommonIcons(icons: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            for iconName in icons {
                _ = self.loadUIImage(for: iconName)
            }
        }
    }

    /// 清空内存图标缓存（SDE/图标重置后调用，确保旧图标不会继续显示）
    func clearCache() {
        imageCache.removeAllObjects()
        Logger.info("IconManager 内存图标缓存已清空")
    }

    func unzipIcons(
        from sourceURL: URL, to destinationURL: URL, progress: @escaping (Double) -> Void
    ) async throws {
        Logger.debug("Starting icon extraction from \(sourceURL.path) to \(destinationURL.path)")

        // 重置解压状态
        isExtractionComplete = false

        try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try Zip.unzipFile(sourceURL, destination: destinationURL, overwrite: true, password: nil) {
            progressValue in
            progress(progressValue)
        }

        // 更新内部的 iconsDirectory
        iconsDirectory = destinationURL

        // 验证解压是否成功
        if let contents = try? fileManager.contentsOfDirectory(atPath: destinationURL.path),
           !contents.isEmpty
        {
            // 设置解压完成状态
            isExtractionComplete = true
            Logger.info("Successfully extracted \(contents.count) icons to \(destinationURL.path)")
        } else {
            throw IconManagerError.readError("Extraction failed: directory is empty")
        }
    }

    enum IconManagerError: Error {
        case readError(String)
    }
}
