import Foundation

// MARK: - 可用模型API

actor AvailableModelsAPI {
    static let shared = AvailableModelsAPI()

    private let urlString =
        "https://carbon-models.vanquisher.online/res/available_typeids.json"

    /// 临时内存缓存（不持久化，app运行期间有效）
    private var availableModels: [Int]?

    private init() {}

    // MARK: - 公开方法

    /// 获取可用模型列表
    /// - Parameter forceRefresh: 是否强制刷新缓存
    /// - Returns: 可用模型ID数组
    func fetchAvailableModels(forceRefresh: Bool = false) async throws -> [Int] {
        // 检查内存缓存（app运行期间有效）
        if !forceRefresh, let cached = availableModels {
            Logger.debug("使用缓存的可用模型列表，共\(cached.count)个模型")
            return cached
        }

        // 从网络获取
        Logger.info("开始获取可用模型列表")
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)

        do {
            let models = try Self.decodeAvailableModels(from: data)

            // 保存到内存缓存（app运行期间有效）
            availableModels = models

            Logger.success("可用模型列表获取完成，共\(models.count)个模型")
            return models
        } catch {
            Logger.error("解析可用模型列表失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    static func decodeAvailableModels(from data: Data) throws -> [Int] {
        try JSONDecoder().decode([Int].self, from: data)
    }

    /// 检查指定模型ID是否在可用列表中
    /// - Parameter modelId: 模型ID
    /// - Returns: 如果模型可用则返回true，否则返回false
    func isModelAvailable(_ modelId: Int) async throws -> Bool {
        let models = try await fetchAvailableModels()
        return models.contains(modelId)
    }
}
