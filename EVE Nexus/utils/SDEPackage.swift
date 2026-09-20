import CloudKit
import CommonCrypto
import Foundation
import Zip

// MARK: - Models

/// CloudKit / Bundle / GitHub metadata；缺字段用默认值
struct CloudKitMetadata: Codable {
    let iconVersion: Int
    let iconSha256: String
    let buildNumber: Int
    let patchNumber: Int
    let releaseDate: String
    let sdeSha256: String
    /// 安装来源标记（远端 metadata 不含此字段，安装时本地写入）
    var source: String?

    /// SDE 安装来源常量
    static let sourceCloudKit = "cloudkit"
    static let sourceGitHub = "github"
    static let sourceBundle = "bundle"

    enum CodingKeys: String, CodingKey {
        case iconVersion = "icon_version"
        case iconSha256 = "icon_sha256"
        case buildNumber = "build_number"
        case patchNumber = "patch_number"
        case releaseDate = "release_date"
        case sdeSha256 = "sde_sha256"
        case source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iconVersion = try c.decodeIfPresent(Int.self, forKey: .iconVersion) ?? 0
        iconSha256 = try c.decodeIfPresent(String.self, forKey: .iconSha256) ?? ""
        buildNumber = try c.decodeIfPresent(Int.self, forKey: .buildNumber) ?? 0
        patchNumber = try c.decodeIfPresent(Int.self, forKey: .patchNumber) ?? 0
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
        sdeSha256 = try c.decodeIfPresent(String.self, forKey: .sdeSha256) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }

    var isValid: Bool {
        buildNumber > 0 || !sdeSha256.isEmpty
    }

    var versionLabel: String {
        patchNumber > 0 ? "\(buildNumber).\(patchNumber)" : "\(buildNumber)"
    }

    /// 启动校验时使用的完整调试摘要
    var debugSummary: String {
        let release = releaseDate.isEmpty ? "<empty>" : releaseDate
        return "build=\(buildNumber), patch=\(patchNumber), iconVersion=\(iconVersion), releaseDate=\(release), "
            + "sdeSHA256=\(sdeSha256Short), iconSHA256=\(iconSha256Short)"
    }

    var sdeSha256Short: String {
        shortHash(sdeSha256)
    }

    var iconSha256Short: String {
        shortHash(iconSha256)
    }

    private func shortHash(_ value: String) -> String {
        value.isEmpty ? "<empty>" : "\(value.prefix(16))…"
    }
}

/// 多行资源检查日志，最终作为一条日志输出
struct SDECheckLog {
    private var lines: [String]

    init(title: String) {
        lines = [title]
    }

    mutating func append(_ line: String) {
        lines.append(line)
    }

    func emit(isWarning: Bool = false) {
        let message = lines.joined(separator: "\n")
        if isWarning {
            Logger.warning(message)
        } else {
            Logger.info(message)
        }
    }
}

struct SDEUpdateInfo {
    let metadata: CloudKitMetadata
    var recordID: CKRecord.ID?
    #if DEBUG
        /// GitHub Release 模式下的安装包直链（仅 Debug 构建）
        var githubIconsURL: URL? = nil
        var githubSDEURL: URL? = nil
    #endif

    var versionLabel: String {
        metadata.versionLabel
    }
}

enum SDECloudKitError: LocalizedError {
    case missingAssetField(String)
    case invalidAsset
    case metadataUnavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case let .missingAssetField(name): return "CloudKit 记录缺少字段: \(name)"
        case .invalidAsset: return "CloudKit Asset 无效"
        case .metadataUnavailable: return "无法获取 metadata"
        case .timeout: return "CloudKit 请求超时"
        }
    }
}

// MARK: - Bundle SDE Resources（utils/sde：sde.zip / icons.zip / metadata.json）

enum BundleSDEResources {
    /// Xcode 同步根目录下的相对路径
    private static let subdirectoryCandidates = ["utils/sde", "sde"]

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        for sub in subdirectoryCandidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return url
            }
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    static var sdeZipURL: URL? {
        url(forResource: "sde", withExtension: "zip")
    }

    static var iconsZipURL: URL? {
        url(forResource: "icons", withExtension: "zip")
    }

    static var metadataURL: URL? {
        url(forResource: "metadata", withExtension: "json")
    }
}

/// Documents 内统一安装目录：`sde/`（库、图标、metadata 同目录）
enum LocalSDELayout {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sde", isDirectory: true)
    }

    static var iconsDirectory: URL {
        root.appendingPathComponent("icons", isDirectory: true)
    }

    static var metadataURL: URL {
        root.appendingPathComponent("metadata.json")
    }

    /// 清除旧版独立 icons 目录（Documents/icons、Documents/Icons）。
    /// 仅在 `sde/icons` 已有有效内容时执行，避免新包未就绪时误删唯一数据源。
    static func purgeLegacyInstallArtifacts() {
        let fm = FileManager.default
        let newIcons = iconsDirectory
        let newContents = (try? fm.contentsOfDirectory(atPath: newIcons.path)) ?? []
        guard !newContents.isEmpty else {
            Logger.info("Documents/sde/icons 尚未就绪，跳过清除旧版 icons 目录")
            return
        }

        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let names = (try? fm.contentsOfDirectory(atPath: documents.path)) ?? []

        var removed = 0
        for name in names where name == "icons" || name == "Icons" {
            let url = documents.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            do {
                try fm.removeItem(at: url)
                removed += 1
                Logger.info("已清除旧版目录: \(url.path)")
            } catch {
                Logger.error("清除旧版目录失败 \(url.lastPathComponent): \(error)")
            }
        }

        if removed == 0 {
            Logger.debug("无旧版 Documents/icons 目录需要清理")
        }
    }
}

// MARK: - Local Metadata

final class MetadataManager {
    static let shared = MetadataManager()
    private init() {}

    func readMetadataFromBundle() -> CloudKitMetadata? {
        guard let url = BundleSDEResources.metadataURL else { return nil }
        return read(from: url)
    }

    func readLocalMetadata() -> CloudKitMetadata? {
        let url = LocalSDELayout.metadataURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return read(from: url)
    }

    func saveLocalMetadata(_ metadata: CloudKitMetadata) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: LocalSDELayout.root, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: LocalSDELayout.metadataURL)
        Logger.info("metadata.json 已保存: \(metadata.versionLabel), icon=\(metadata.iconVersion)")
    }

    func getLocalIconVersion() -> Int {
        readLocalMetadata()?.iconVersion
            ?? readMetadataFromBundle()?.iconVersion
            ?? 0
    }

    private func read(from url: URL) -> CloudKitMetadata? {
        do {
            return try JSONDecoder().decode(CloudKitMetadata.self, from: Data(contentsOf: url))
        } catch {
            Logger.error("读取 metadata 失败: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Local Download / Extract

final class SDEDownloader {
    private var fm: FileManager {
        .default
    }

    var downloadDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("SDEDownload")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var documentsDirectory: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func clearDownloadDirectory() throws {
        let dir = downloadDirectory
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func clearCloudKitAssets() {
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let root = caches.appendingPathComponent("CloudKit")
        guard fm.fileExists(atPath: root.path),
              let containers = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }

        var count = 0
        for container in containers where !container.lastPathComponent.hasPrefix(".") {
            let assets = container.appendingPathComponent("Assets")
            guard let files = try? fm.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                try? fm.removeItem(at: file)
                count += 1
            }
        }
        if count > 0 {
            Logger.info("已清理 \(count) 个 CloudKit Asset 缓存文件")
        }
    }

    func stageAsset(_ source: URL, as fileName: String) throws -> URL {
        let dest = downloadDirectory.appendingPathComponent(fileName)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
        try? fm.removeItem(at: source)
        return dest
    }

    func verifySHA256(of fileURL: URL, expected: String) throws -> Bool {
        guard fm.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "SDEDownloader", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "文件不存在: \(fileURL.lastPathComponent)"])
        }
        let hash = try sha256(of: fileURL)
        let ok = hash.compare(expected, options: .caseInsensitive) == .orderedSame
        Logger.info("SHA256 \(fileURL.lastPathComponent): \(ok ? "OK" : "FAIL")")
        return ok
    }

    /// 安装图标到本地目录（OTA / Bundle 共用）
    private func installIcons(from zip: URL, progress: @escaping (Double) -> Void) async throws {
        guard fm.fileExists(atPath: zip.path) else {
            throw NSError(
                domain: "SDEDownloader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "\(zip.lastPathComponent) 不存在"]
            )
        }

        let dest = LocalSDELayout.iconsDirectory
        Logger.info("开始安装图标：源=\(zip.lastPathComponent)，目标=\(dest.path)")
        if fm.fileExists(atPath: dest.path) {
            Logger.info("清理旧图标目录：\(dest.path)")
            try fm.removeItem(at: dest)
        }
        try await IconManager.shared.unzipIcons(from: zip, to: dest, progress: progress)
        Logger.info("图标安装完成")
    }

    /// 从 CloudKit 下载目录解压图标（OTA 更新）
    func extractIcons(progress: @escaping (Double) -> Void) async throws {
        Logger.info("OTA 更新：从下载目录解压 icons.zip")
        let zip = await downloadDirectory.appendingPathComponent(SDECloudKitManager.iconsZipName)
        try await installIcons(from: zip, progress: progress)
    }

    /// 从 Bundle 解压图标
    func extractBundledIcons(progress: @escaping (Double) -> Void) async throws {
        Logger.info("Bundle 解压：释放 icons.zip")
        guard let zip = BundleSDEResources.iconsZipURL else {
            throw NSError(
                domain: "SDEDownloader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Bundle 中未找到 icons.zip"]
            )
        }
        try await installIcons(from: zip, progress: progress)
    }

    /// 安装 SDE 到本地目录（OTA / Bundle 共用）
    /// - parameter preserveSidecars: 是否保留旧 icons 与 metadata（OTA 更新时为 true）
    private func installSDE(
        from zip: URL,
        preserveSidecars: Bool,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard fm.fileExists(atPath: zip.path) else {
            throw NSError(
                domain: "SDEDownloader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "\(zip.lastPathComponent) 不存在"]
            )
        }

        let dest = LocalSDELayout.root
        Logger.info("开始安装 SDE：源=\(zip.lastPathComponent)，目标=\(dest.path)，保留 sidecars=\(preserveSidecars)")
        let sidecarTmp = documentsDirectory.appendingPathComponent("sde_sidecar_tmp", isDirectory: true)

        if preserveSidecars {
            Logger.info("保留旧 icons/metadata 到临时目录")
            try? fm.removeItem(at: sidecarTmp)
            try fm.createDirectory(at: sidecarTmp, withIntermediateDirectories: true)
            let icons = LocalSDELayout.iconsDirectory
            let meta = LocalSDELayout.metadataURL
            if fm.fileExists(atPath: icons.path) {
                try? fm.moveItem(at: icons, to: sidecarTmp.appendingPathComponent("icons"))
            }
            if fm.fileExists(atPath: meta.path) {
                try? fm.moveItem(at: meta, to: sidecarTmp.appendingPathComponent("metadata.json"))
            }
        }

        defer {
            if preserveSidecars {
                Logger.info("从临时目录恢复 icons/metadata")
                let tmpIcons = sidecarTmp.appendingPathComponent("icons")
                let tmpMeta = sidecarTmp.appendingPathComponent("metadata.json")
                if fm.fileExists(atPath: tmpIcons.path) {
                    try? fm.removeItem(at: LocalSDELayout.iconsDirectory)
                    try? fm.moveItem(at: tmpIcons, to: LocalSDELayout.iconsDirectory)
                    IconManager.shared.adoptIconsDirectory(LocalSDELayout.iconsDirectory)
                }
                if fm.fileExists(atPath: tmpMeta.path) {
                    try? fm.removeItem(at: LocalSDELayout.metadataURL)
                    try? fm.moveItem(at: tmpMeta, to: LocalSDELayout.metadataURL)
                }
                try? fm.removeItem(at: sidecarTmp)
            }
        }

        try await unzipFile(zip, to: dest, progress: progress)
        try finishSDEInstall(at: dest)
        Logger.info("SDE 安装完成")
    }

    /// 从 CloudKit 下载目录解压 SDE（OTA 更新，保留 sidecars）
    func extractSDE(progress: @escaping (Double) -> Void) async throws {
        Logger.info("OTA 更新：从下载目录解压 sde.zip（保留旧 icons/metadata）")
        let zip = await downloadDirectory.appendingPathComponent(SDECloudKitManager.sdeZipName)
        try await installSDE(from: zip, preserveSidecars: true, progress: progress)
    }

    /// 从 Bundle 解压 SDE（不保留旧 icons；随后应再装 icons）
    func extractBundledSDE(progress: @escaping (Double) -> Void) async throws {
        Logger.info("Bundle 解压：释放 sde.zip（不保留旧 icons/metadata）")
        guard let zip = BundleSDEResources.sdeZipURL else {
            throw NSError(
                domain: "SDEDownloader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Bundle 中未找到 sde.zip"]
            )
        }
        try await installSDE(from: zip, preserveSidecars: false, progress: progress)
    }

    /// 从 Bundle 播种完整包到 Documents/sde（库 + icons + metadata）
    func seedFromBundle(progress: @escaping (Double) -> Void) async throws {
        Logger.info("开始从 Bundle 播种完整 SDE 包（sde.zip + icons.zip + metadata）")
        try await extractBundledSDE { progress($0 * 0.65) }
        try await extractBundledIcons { progress(0.65 + $0 * 0.3) }
        if var meta = MetadataManager.shared.readMetadataFromBundle() {
            meta.source = CloudKitMetadata.sourceBundle
            try MetadataManager.shared.saveLocalMetadata(meta)
        }
        LocalSDELayout.purgeLegacyInstallArtifacts()
        progress(1)
        Logger.info("Bundle 播种完成")
    }

    private func finishSDEInstall(at dest: URL) throws {
        NotificationCenter.default.post(name: NSNotification.Name("SDEDataUpdated"), object: nil)

        let textsZip = dest.appendingPathComponent("texts.zip")
        guard fm.fileExists(atPath: textsZip.path) else { return }
        do {
            try ItemTextStore.shared.installFromSDEPackage(textsZipURL: textsZip)
            try? fm.removeItem(at: textsZip)
        } catch {
            Logger.error("安装 texts.zip 失败: \(error)")
        }
    }

    private func unzipFile(_ zip: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try Zip.unzipFile(zip, destination: destination, overwrite: true, password: nil, progress: progress)
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }

        let contents = (try? fm.contentsOfDirectory(atPath: destination.path)) ?? []
        guard !contents.isEmpty else {
            throw NSError(domain: "SDEDownloader", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "\(zip.lastPathComponent) 解压结果为空"])
        }
    }

    private func sha256(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CloudKit

/// CloudKit SDE 查询与下载；故障时软失败，不影响 App
@MainActor
final class SDECloudKitManager {
    static let shared = SDECloudKitManager()

    static let fieldIcons = "icons"
    static let fieldSDE = "sde"
    static let fieldMetadata = "metadata"
    static let fieldMinAppVersion = "minimum_app_version"
    static let fieldSDEVersion = "sde_version"
    static let iconsZipName = "icons.zip"
    static let sdeZipName = "sde.zip"

    private let database = CKContainer.default().publicCloudDatabase
    private let queryTimeout: TimeInterval = 20

    private var recordType: String {
        AppConfiguration.SDE.recordType
    }

    private var minAppVersion: String {
        AppConfiguration.SDE.minimumAppVersion
    }

    private init() {}

    /// 软失败返回 nil。按 sde_version 选最新记录，详情来自 metadata String（JSON）。
    func fetchLatestSDEUpdate() async -> SDEUpdateInfo? {
        Logger.info("CloudKit 查询 SDE: type=\(recordType)")
        guard let (recordID, metadata) = await latestCompatiblePackage() else { return nil }
        Logger.info("命中 SDE: \(metadata.versionLabel), icon=\(metadata.iconVersion)")
        return SDEUpdateInfo(metadata: metadata, recordID: recordID)
    }

    func fetchAsset(
        recordID: CKRecord.ID,
        field: String,
        progress: @escaping (Double) -> Void = { _ in },
        timeout: TimeInterval? = nil
    ) async throws -> URL {
        let op = CKFetchRecordsOperation(recordIDs: [recordID])
        op.desiredKeys = [field]
        op.perRecordProgressBlock = { _, p in
            Task { @MainActor in progress(p) }
        }

        let asset: CKAsset = try await run(op, timeout: timeout) { finish in
            op.perRecordResultBlock = { _, result in
                switch result {
                case let .success(record):
                    if let asset = record[field] as? CKAsset {
                        finish(.success(asset))
                    } else {
                        finish(.failure(SDECloudKitError.missingAssetField(field)))
                    }
                case let .failure(error):
                    finish(.failure(error))
                }
            }
            self.database.add(op)
        }
        guard let url = asset.fileURL else { throw SDECloudKitError.invalidAsset }
        return url
    }

    private static func recordTypeIssue(_ name: String) -> String? {
        if name.isEmpty {
            return "不能为空"
        }
        if let bad = name.first(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) {
            return "含非法字符「\(bad)」（仅允许字母、数字、下划线）"
        }
        if let first = name.first, !first.isLetter {
            return "必须以字母开头，当前以「\(first)」开头"
        }
        return nil
    }

    private func latestCompatiblePackage() async -> (CKRecord.ID, CloudKitMetadata)? {
        if let issue = Self.recordTypeIssue(recordType) {
            Logger.error("非法 RecordType「\(recordType)」：\(issue)，跳过 CloudKit 查询")
            return nil
        }

        do {
            let records = try await queryRecords(
                keys: [Self.fieldMinAppVersion, Self.fieldSDEVersion, Self.fieldMetadata],
                limit: 50
            )
            guard !records.isEmpty else { return nil }

            let matched = records.filter {
                ($0[Self.fieldMinAppVersion] as? String).map { $0 == minAppVersion } ?? true
            }
            let pool = matched.isEmpty ? records : matched
            let candidates = pool.compactMap { record -> (CKRecord.ID, CloudKitMetadata, Int)? in
                guard let meta = Self.decodeMetadata(record[Self.fieldMetadata]) else { return nil }
                return (record.recordID, meta, Self.intValue(record[Self.fieldSDEVersion]))
            }
            guard let best = candidates.max(by: { $0.2 < $1.2 }) else {
                Logger.warning("CloudKit 记录均无可用 metadata String")
                return nil
            }
            return (best.0, best.1)
        } catch {
            Logger.warning("CloudKit 查询失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func queryRecords(keys: [String], limit: Int) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let op = CKQueryOperation(query: query)
        op.desiredKeys = keys
        op.resultsLimit = limit

        return try await run(op, timeout: queryTimeout) { finish in
            var records: [CKRecord] = []
            op.recordMatchedBlock = { _, result in
                if case let .success(record) = result {
                    records.append(record)
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .success: finish(.success(records))
                case let .failure(error): finish(.failure(error))
                }
            }
            self.database.add(op)
        }
    }

    /// `metadata` 为 CloudKit String，内容为 JSON
    private static func decodeMetadata(_ value: Any?) -> CloudKitMetadata? {
        let data: Data?
        switch value {
        case let s as String:
            data = s.data(using: .utf8)
        case let d as Data:
            data = d
        default:
            return nil
        }
        guard let data, !data.isEmpty else { return nil }
        do {
            let meta = try JSONDecoder().decode(CloudKitMetadata.self, from: data)
            return meta.isValid ? meta : nil
        } catch {
            Logger.warning("metadata JSON 解析失败: \(error.localizedDescription)")
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        case let s as String: return Int(s) ?? Int(Double(s) ?? 0)
        default: return 0
        }
    }

    private func run<T>(
        _ operation: CKOperation,
        timeout: TimeInterval?,
        _ body: (@escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var done = false
            func finish(_ result: Result<T, Error>) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                continuation.resume(with: result)
            }

            var timeoutItem: DispatchWorkItem?
            if let timeout {
                let item = DispatchWorkItem {
                    operation.cancel()
                    finish(.failure(SDECloudKitError.timeout))
                }
                timeoutItem = item
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            }

            body { result in
                timeoutItem?.cancel()
                finish(result)
            }
        }
    }
}

// MARK: - GitHub（仅 Debug 构建可用；正式版永远走 CloudKit）

#if DEBUG
    /// GitHub Release SDE 查询与下载；故障时软失败，不影响 App
    /// 非 MainActor：下载写盘在后台线程执行，避免阻塞 UI（progress 由调用方切主线程）
    final class SDEGitHubManager {
        static let shared = SDEGitHubManager()

        static let latestReleaseAPI = URL(
            string: "https://api.github.com/repos/EstamelGG/EveSDE_3.0/releases/latest"
        )!

        private let requestTimeout: TimeInterval = 20
        private init() {}

        private func makeRequest(_ url: URL, timeout: TimeInterval) -> URLRequest {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            // GitHub API 强制要求 User-Agent
            request.setValue("EVE-Nexus-Debug", forHTTPHeaderField: "User-Agent")
            return request
        }

        /// 软失败返回 nil。拉取最新 Release，下载 assets 中的 metadata.json 并解析
        func fetchLatestSDEUpdate() async -> SDEUpdateInfo? {
            do {
                Logger.info("GitHub 查询 SDE: latest release")
                let (data, _) = try await URLSession.shared.data(for: makeRequest(Self.latestReleaseAPI, timeout: requestTimeout))
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard let metaAsset = release.asset(named: "metadata.json") else {
                    Logger.warning("GitHub Release 缺少 metadata.json asset")
                    return nil
                }

                // metadata.json 体积很小（<1KB），直接整体下载
                let (metaData, _) = try await URLSession.shared.data(
                    for: makeRequest(metaAsset.browserDownloadURL, timeout: requestTimeout)
                )
                let meta = try JSONDecoder().decode(CloudKitMetadata.self, from: metaData)
                guard meta.isValid else {
                    Logger.warning("GitHub metadata.json 无效")
                    return nil
                }

                Logger.info("命中 SDE(GitHub): \(meta.versionLabel), icon=\(meta.iconVersion), tag=\(release.tagName)")
                return SDEUpdateInfo(
                    metadata: meta,
                    recordID: nil,
                    githubIconsURL: release.asset(named: "icons.zip")?.browserDownloadURL,
                    githubSDEURL: release.asset(named: "sde.zip")?.browserDownloadURL
                )
            } catch {
                Logger.warning("GitHub 查询 SDE 失败: \(error.localizedDescription)")
                return nil
            }
        }

        /// 流式下载安装包到指定路径，支持进度回调（0-1）
        func download(
            from url: URL,
            to destination: URL,
            progress: @escaping (Double) -> Void
        ) async throws {
            let (bytes, response) = try await URLSession.shared.bytes(
                for: makeRequest(url, timeout: 60)
            )
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw SDEGitHubError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
            }

            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            // FileHandle(forWritingTo:) 不会创建文件，必须先建空文件
            guard fm.createFile(atPath: destination.path, contents: nil) else {
                throw SDEGitHubError.createFileFailed(destination.lastPathComponent)
            }

            let expected = http.expectedContentLength
            var received: Int64 = 0
            var buffer = [UInt8]()
            buffer.reserveCapacity(1 << 20)

            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }

            for try await byte in bytes {
                buffer.append(byte)
                received += 1
                if buffer.count >= 1 << 20 { // 每累积 1MB 落盘一次
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    if expected > 0 {
                        progress(Double(received) / Double(expected))
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
            }
            progress(1)
        }
    }

    /// GitHub Release API 响应中我们关心的字段
    struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        func asset(named name: String) -> Asset? {
            assets.first { $0.name == name }
        }
    }

    enum SDEGitHubError: LocalizedError {
        case badResponse(Int)
        case createFileFailed(String)

        var errorDescription: String? {
            switch self {
            case let .badResponse(code): return "GitHub 下载失败，HTTP \(code)"
            case let .createFileFailed(name): return "创建下载文件失败: \(name)"
            }
        }
    }
#endif
