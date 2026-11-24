import Foundation

actor CharacterIndustryAPI {
    static let shared = CharacterIndustryAPI()

    /// 缓存过期时间（1小时）
    private let cacheExpirationInterval: TimeInterval = 3600
    private let requests = AppDataRequests<Int, [IndustryJob]>()

    typealias IndustryJob = ESIIndustryJob

    private init() {}

    func fetchIndustryJobs(
        characterId: Int,
        forceRefresh: Bool = false,
        includeCompleted: Bool = true,
        maxCacheAge: TimeInterval? = nil
    ) async throws -> [IndustryJob] {
        let jobs: [IndustryJob]
        if !forceRefresh, let cached = loadJobsFromCache(
            characterId: characterId, maxAge: maxCacheAge ?? cacheExpirationInterval
        ) {
            jobs = cached
        } else {
            jobs = try await requests.run(characterId) {
                try await self.downloadJobs(characterId: characterId)
            }
        }
        return includeCompleted ? jobs : jobs.filter(\.isOpen)
    }

    private func downloadJobs(characterId: Int) async throws -> [IndustryJob] {
        let url = URL(
            string: "https://esi.evetech.net/characters/\(characterId)/industry/jobs/?datasource=tranquility&include_completed=true"
        )!
        let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let jobs = try decoder.decode([IndustryJob].self, from: data)
        saveJobsToCache(jobs, characterId: characterId)
        await AppDataUpdate.industry(characterID: characterId, jobs: jobs, at: Date()).publish()
        return jobs
    }

    // MARK: - Cache Methods

    private func getCacheDirectory() -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "IndustryJobs", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    func cachedAt(characterId: Int) -> Date? {
        getCacheFilePath(characterId: characterId)?.cacheModificationDate
    }

    private func getCacheFilePath(characterId: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("char_\(characterId)_all.json")
    }

    private func loadJobsFromCache(characterId: Int, maxAge: TimeInterval? = nil) -> [IndustryJob]? {
        guard let cacheFile = getCacheFilePath(characterId: characterId) else {
            Logger.error("获取缓存文件路径失败 - 角色ID: \(characterId)")
            return nil
        }

        Logger.info("尝试从缓存文件读取工业项目数据 - 路径: \(cacheFile.path)")

        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info("缓存文件不存在 - 角色ID: \(characterId), 路径: \(cacheFile.path)")
                return nil
            }

            // 检查文件修改时间是否过期
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
            if let modificationDate = fileAttributes[.modificationDate] as? Date {
                let timeSinceModification = Date().timeIntervalSince(modificationDate)
                if timeSinceModification >= (maxAge ?? cacheExpirationInterval) {
                    Logger.info(
                        "缓存文件已过期 - 角色ID: \(characterId), 路径: \(cacheFile.path), 修改时间: \(modificationDate)"
                    )
                    return nil
                }
            }

            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let jobs = try decoder.decode([IndustryJob].self, from: data)

            Logger.info(
                "成功从缓存加载工业项目信息 - 角色ID: \(characterId), 路径: \(cacheFile.path), 数据条数: \(jobs.count)"
            )
            return jobs
        } catch {
            Logger.error("读取缓存文件失败 - 角色ID: \(characterId), 路径: \(cacheFile.path), 错误: \(error)")
            // 删除损坏的缓存文件
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveJobsToCache(_ jobs: [IndustryJob], characterId: Int) {
        guard let cacheFile = getCacheFilePath(characterId: characterId) else {
            Logger.error("获取缓存文件路径失败 - 角色ID: \(characterId)")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encodedData = try encoder.encode(jobs)
            try encodedData.write(to: cacheFile, options: .atomic)
            Logger.info(
                "工业项目信息已缓存到文件 - 角色ID: \(characterId), 路径: \(cacheFile.path), 数据条数: \(jobs.count)"
            )
        } catch {
            Logger.error("保存工业项目信息缓存失败 - 角色ID: \(characterId), 路径: \(cacheFile.path), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
}
