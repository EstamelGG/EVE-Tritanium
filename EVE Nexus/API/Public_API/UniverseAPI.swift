import Foundation

struct UniverseNameResponse: Codable {
    let category: String
    let id: Int
    let name: String
}

@NetworkManagerActor
class UniverseAPI {
    static let shared = UniverseAPI()
    private let networkManager = NetworkManager.shared
    private let databaseManager = CharacterDatabaseManager.shared
    private let builtinDatabaseManager = DatabaseManager.shared

    private init() {}

    /// 从ESI获取ID对应的名称信息
    /// - Parameter ids: 要查询的ID数组
    /// - Returns: 成功获取的数量
    /// Resolve a set of IDs to names and categories. Supported ID's for resolving are: Characters, Corporations, Alliances, Stations, Solar Systems, Constellations, Regions, Types, Factions
    func fetchAndSaveNames(ids: [Int]) async throws -> Int {
        // 去重
        let uniqueIds = Array(Set(ids))

        if uniqueIds.count < ids.count {
            Logger.info("去重后：\(ids.count) -> \(uniqueIds.count) 个ID")
        }

        Logger.info("开始获取实体名称信息 - IDs: \(uniqueIds)")

        // 构建请求URL
        let urlString = "https://esi.evetech.net/universe/names/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 准备请求数据
        let jsonData = try JSONEncoder().encode(uniqueIds)

        // 发送POST请求
        let data = try await networkManager.fetchData(
            from: url,
            method: "POST",
            body: jsonData
        )

        // 解析响应数据
        let responses = try JSONDecoder().decode([UniverseNameResponse].self, from: data)
        Logger.success("成功获取 \(responses.count) 个实体的名称信息")

        // 准备批量插入的SQL语句（last_updated 由 SQLite 服务端时钟生成，避免依赖客户端时钟）
        let insertSQL = """
            INSERT OR REPLACE INTO universe_names (
                id,
                name,
                category,
                last_updated
            ) VALUES
        """

        // 构建值部分和参数数组
        let valuePlaceholders = responses.map { _ in "(?, ?, ?, strftime('%s','now'))" }.joined(separator: ",")
        let finalSQL = insertSQL + valuePlaceholders

        // 准备参数数组
        var parameters: [Any] = []
        for response in responses {
            parameters.append(response.id)
            parameters.append(response.name)
            parameters.append(response.category)
        }

        // 执行批量插入
        let result = databaseManager.executeQuery(finalSQL, parameters: parameters)

        switch result {
        case .success:
            Logger.success("成功批量保存 \(responses.count) 个实体的名称信息到数据库")
            return responses.count
        case let .error(error):
            Logger.error("批量保存实体信息失败 - 错误: \(error)")
            return 0
        }
    }

    /// 从内置数据库的agents表批量获取NPC角色信息
    /// - Parameter ids: 要查询的ID数组
    /// - Returns: ID到名称和所属军团的映射
    func getAgentsFromDatabase(ids: [Int]) -> [Int: (name: String, corporationID: Int?)] {
        guard !ids.isEmpty else { return [:] }

        let placeholders = String(repeating: "?,", count: ids.count).dropLast()
        let query = """
            SELECT agent_id, corporationID, COALESCE(agent_name, 'Unknown') as name
            FROM agents
            WHERE agent_id IN (\(placeholders))
        """

        let result = builtinDatabaseManager.executeQuery(query, parameters: ids)

        switch result {
        case let .success(rows):
            var agentMap: [Int: (name: String, corporationID: Int?)] = [:]
            for row in rows {
                if let agentId = row["agent_id"] as? Int,
                   let name = row["name"] as? String
                {
                    agentMap[agentId] = (name: name, corporationID: row["corporationID"] as? Int)
                }
            }
            if !agentMap.isEmpty {
                Logger.debug("从agents表找到 \(agentMap.count) 个NPC角色")
            }
            return agentMap

        case let .error(error):
            Logger.error("从agents表查询失败 - IDs: \(ids), 错误: \(error)")
            return [:]
        }
    }

    /// 从数据库批量获取ID对应的名称信息（仅返回缓存有效期 7天 内的记录）
    /// - Parameter ids: 要查询的ID数组
    /// - Returns: ID到名称和类型的映射
    func getNamesFromDatabase(ids: [Int]) async throws -> [Int: (name: String, category: String)] {
        let placeholders = String(repeating: "?,", count: ids.count).dropLast()
        let query = """
        SELECT id, name, category FROM universe_names
        WHERE id IN (\(placeholders))
          AND last_updated > strftime('%s','now') - 7
        """

        let result = databaseManager.executeQuery(query, parameters: ids)

        switch result {
        case let .success(rows):
            var namesMap: [Int: (name: String, category: String)] = [:]
            for row in rows {
                if let id = row["id"] as? Int64,
                   let name = row["name"] as? String,
                   let category = row["category"] as? String
                {
                    namesMap[Int(id)] = (name: name, category: category)
                }
            }
            return namesMap

        case let .error(error):
            Logger.error("从数据库批量获取实体信息失败 - IDs: \(ids), 错误: \(error)")
            throw DatabaseError.fetchError(error)
        }
    }

    /// 检查ID是否在ESI API支持的有效范围内
    /// ESI API支持的实体类型：Characters, Corporations, Alliances, Stations, Solar Systems, Constellations, Regions, Types, Factions
    /// - Parameter id: 要检查的ID
    /// - Returns: 如果ID在有效范围内返回true，否则返回false
    private func isValidEntityId(_ id: Int) -> Bool {
        // 根据ESI API文档，支持的实体类型及其ID范围：
        // - Factions: 500,000 - 599,999
        // - NPC Corporations: 1,000,000 - 1,999,999
        // - NPC Characters: 3,000,000 - 3,999,999
        // - Regions: 10,000,000 - 19,999,999
        // - Constellations: 20,000,000 - 29,999,999
        // - Solar Systems: 30,000,000 - 39,999,999
        // - Stations: 60,000,000 - 69,999,999
        // - EVE Characters (2010-11-03 to 2016-05-30): 90,000,000 - 97,999,999
        // - EVE Corporations (after 2010-11-03): 98,000,000 - 98,999,999
        // - EVE Alliances (after 2010-11-03): 99,000,000 - 99,999,999
        // - EVE Characters/Corporations/Alliances (before 2010-11-03): 100,000,000 - 2,099,999,999
        // - EVE / DUST Characters (after 2016-05-30): 2,100,000,000 - 2,111,999,999
        // - EVE Characters (after 2016-05-30): 2,112,000,000 - 2,129,999,999
        // - Types: 可能在 0 - 499,999 范围内（Various，经常在不同类型间重用）

        switch id {
        // Types (Various, 0-499,999)
        case 0 ... 499_999:
            return true
        // Factions
        case 500_000 ... 599_999:
            return true
        // NPC Corporations
        case 1_000_000 ... 1_999_999:
            return true
        // NPC Characters
        case 3_000_000 ... 3_999_999:
            return true
        // Regions
        case 10_000_000 ... 19_999_999:
            return true
        // Constellations
        case 20_000_000 ... 29_999_999:
            return true
        // Solar Systems
        case 30_000_000 ... 39_999_999:
            return true
        // Stations
        case 60_000_000 ... 69_999_999:
            return true
        // EVE Characters (2010-11-03 to 2016-05-30)
        case 90_000_000 ... 97_999_999:
            return true
        // EVE Corporations (after 2010-11-03)
        case 98_000_000 ... 98_999_999:
            return true
        // EVE Alliances (after 2010-11-03)
        case 99_000_000 ... 99_999_999:
            return true
        // EVE Characters/Corporations/Alliances (before 2010-11-03)
        case 100_000_000 ... 2_099_999_999:
            return true
        // EVE / DUST Characters (after 2016-05-30)
        case 2_100_000_000 ... 2_111_999_999:
            return true
        // EVE Characters (after 2016-05-30)
        case 2_112_000_000 ... 2_129_999_999:
            return true
        default:
            return false
        }
    }

    /// 批量获取ID对应的名称信息，对于数据库中不存在的条目会自动从API获取
    /// - Parameter ids: 要查询的ID数组
    /// - Returns: ID到名称和类型的映射
    func getNamesWithFallback(ids: [Int]) async throws -> [Int: (name: String, category: String)] {
        // 首先从内置数据库的agents表查询NPC角色（优先级最高）
        let agentNamesMap = getAgentsFromDatabase(ids: ids).mapValues { (name: $0.name, category: "character") }

        // 从角色数据库获取所有可用的名称（包括不在有效范围内的ID，因为它们可能已经在数据库中）
        Logger.debug("Fetch from DB. Total IDs: \(ids.count)")
        let namesMap = try await getNamesFromDatabase(ids: ids)

        // 合并结果：先合并universe_names表的结果，再合并agents表的结果（agents表优先级更高）
        var allNamesMap = namesMap
        allNamesMap.merge(agentNamesMap) { _, agent in agent }

        // 找出数据库中不存在的ID（排除已经在agents表或universe_names表中找到的）
        let missingIds = ids.filter { !allNamesMap.keys.contains($0) }

        // 如果有缺失的ID，在最终发送网络API请求前才进行批次处理和过滤
        if !missingIds.isEmpty {
            // 将缺失的ID数组分成每批1000个的子数组，用于API请求
            let batchSize = 1000
            let batches = stride(from: 0, to: missingIds.count, by: batchSize).map {
                Array(missingIds[$0 ..< min($0 + batchSize, missingIds.count)])
            }

            // 处理每一批缺失的ID
            for batch in batches {
                // 在最终发送网络API请求前才过滤出在有效范围内的ID
                let validMissingIds = batch.filter { isValidEntityId($0) }

                // 找出被过滤掉的ID（不在有效范围内）
                let filteredIds = batch.filter { !isValidEntityId($0) }

                if !filteredIds.isEmpty {
                    Logger.info("过滤掉 \(filteredIds.count) 个不在有效范围内的ID，将使用ID作为名称")
                    // 将被过滤掉的ID添加到结果中，name设为ID本身
                    for id in filteredIds {
                        allNamesMap[id] = (name: String(id), category: "unknown")
                    }
                }

                // 只对有效范围内的缺失ID发送API请求
                if !validMissingIds.isEmpty {
                    Logger.debug("Fetch from api. Missing IDs count: \(validMissingIds.count)")

                    // 尝试批量请求，如果失败则使用并发回退策略
                    do {
                        let result = try await fetchAndSaveNames(ids: validMissingIds)
                        if result > 0 {
                            // 获取新保存的数据
                            let newNames = try await getNamesFromDatabase(ids: validMissingIds)
                            // 合并API返回的结果（agents表的结果优先级更高，不会被覆盖）
                            for (id, info) in newNames {
                                // 如果agents表中没有这个ID，才使用API返回的结果
                                if !agentNamesMap.keys.contains(id) {
                                    allNamesMap[id] = info
                                }
                            }
                        }
                    } catch {
                        // 批量请求失败，使用并发回退策略
                        Logger.warning("批量获取实体名称失败，使用回退策略（10个并发单ID请求）: \(error)")
                        let fallbackResults = await fetchNamesWithConcurrentFallback(ids: validMissingIds)
                        // 合并回退策略的结果（agents表的结果优先级更高，不会被覆盖）
                        for (id, info) in fallbackResults {
                            // 如果agents表中没有这个ID，才使用回退策略的结果
                            if !agentNamesMap.keys.contains(id) {
                                allNamesMap[id] = info
                            }
                        }
                    }

                    // 处理API请求失败或未返回的ID，将ID作为名称
                    let unreturnedIds = validMissingIds.filter { !allNamesMap.keys.contains($0) }
                    if !unreturnedIds.isEmpty {
                        Logger.debug("API未返回 \(unreturnedIds.count) 个ID，将使用ID作为名称")
                        for id in unreturnedIds {
                            allNamesMap[id] = (name: String(id), category: "unknown")
                        }
                    }
                }
            }
        }

        return allNamesMap
    }

    /// 并发回退策略：使用10个并发对每个ID逐一调用API
    /// 当批量POST请求失败时，使用此方法作为回退策略
    /// - Parameter ids: 要查询的ID数组（这些ID已经在主流程中确认数据库中不存在且已过滤有效性）
    /// - Returns: ID到名称和类型的映射
    func fetchNamesWithConcurrentFallback(ids: [Int]) async -> [Int: (name: String, category: String)] {
        guard !ids.isEmpty else { return [:] }

        let maxConcurrency = min(10, ids.count)
        Logger.info("开始使用并发回退策略 - 总数: \(ids.count), 并发数: \(maxConcurrency)")

        var pendingIds = ids
        var completedIds: [Int] = []

        // 使用10个并发，对每个ID逐一调用API
        await withTaskGroup(of: Int?.self) { group in
            var inProgressCount = 0

            // 初始添加并发数量的任务
            while !pendingIds.isEmpty, inProgressCount < maxConcurrency {
                let id = pendingIds.removeFirst()
                group.addTask(priority: .userInitiated) { @NetworkManagerActor in
                    do {
                        _ = try await self.fetchAndSaveNames(ids: [id])
                        return id
                    } catch {
                        Logger.error("并发回退策略：获取实体名称失败 (ID: \(id)): \(error)")
                        return nil
                    }
                }
                inProgressCount += 1
            }

            // 处理结果并添加新任务
            while let taskResult = await group.next() {
                if let id = taskResult {
                    completedIds.append(id)
                }

                // 如果还有待处理的ID，添加新任务
                if !pendingIds.isEmpty {
                    let nextId = pendingIds.removeFirst()
                    group.addTask(priority: .userInitiated) { @NetworkManagerActor in
                        do {
                            _ = try await self.fetchAndSaveNames(ids: [nextId])
                            return nextId
                        } catch {
                            Logger.error("并发回退策略：获取实体名称失败 (ID: \(nextId)): \(error)")
                            return nil
                        }
                    }
                }
            }
        }

        // 批量从数据库读取所有成功保存的结果
        var results: [Int: (name: String, category: String)] = [:]
        if !completedIds.isEmpty {
            do {
                let savedNames = try await getNamesFromDatabase(ids: completedIds)
                results = savedNames
            } catch {
                Logger.error("并发回退策略：从数据库读取结果失败: \(error)")
            }
        }

        // 对于失败的ID，使用默认值
        for id in ids {
            if results[id] == nil {
                results[id] = (name: NSLocalizedString("Unknown", comment: ""), category: "unknown")
            }
        }

        Logger.info("并发回退策略完成 - 成功获取 \(results.count) 个实体名称")
        return results
    }
}
