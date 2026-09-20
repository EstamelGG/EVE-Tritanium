import SwiftUI

/// 数组分块扩展
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

@MainActor
struct StructureSearchView {
    let characterId: Int
    let searchText: String
    @Binding var searchResults: [SearcherView.SearchResult]
    @Binding var filteredResults: [SearcherView.SearchResult]
    @Binding var searchingStatus: String
    @Binding var error: Error?
    let structureType: SearcherView.StructureType

    let strictMatch: Bool

    init(
        characterId: Int,
        searchText: String,
        searchResults: Binding<[SearcherView.SearchResult]>,
        filteredResults: Binding<[SearcherView.SearchResult]>,
        searchingStatus: Binding<String>,
        error: Binding<Error?>,
        structureType: SearcherView.StructureType,
        strictMatch: Bool = false
    ) {
        self.characterId = characterId
        self.searchText = searchText
        _searchResults = searchResults
        _filteredResults = filteredResults
        _searchingStatus = searchingStatus
        _error = error
        self.structureType = structureType
        self.strictMatch = strictMatch
    }

    /// 批量加载位置信息
    private func loadBatchLocationInfo(systemIds: [Int]) async throws -> [Int: (
        security: Double, systemName: String, regionName: String
    )] {
        let solarSystemInfoMap = await getBatchSolarSystemInfo(
            solarSystemIds: systemIds, databaseManager: DatabaseManager.shared
        )

        var result: [Int: (security: Double, systemName: String, regionName: String)] = [:]

        for (systemId, info) in solarSystemInfoMap {
            result[systemId] = (
                security: info.security,
                systemName: info.systemName,
                regionName: info.regionName
            )
        }

        return result
    }

    /// 从 SDEMemoryStore 内存缓存批量加载空间站信息
    private func loadStationsInfo(stationIds: [Int]) -> [(
        id: Int, name: String, typeId: Int, systemId: Int
    )] {
        stationIds.compactMap { stationId in
            guard let info = SDEMemoryStore.station(for: stationId),
                  let typeId = info.stationTypeID,
                  let systemId = info.solarSystemID
            else { return nil }
            return (id: stationId, name: info.name, typeId: typeId, systemId: systemId)
        }
    }

    /// 从 SDEMemoryStore 内存缓存搜索空间站
    private func searchLocalStations(searchText: String) -> [Int] {
        SDEMemoryStore.stations.values
            .filter { $0.name.localizedStandardContains(searchText) }
            .prefix(500)
            .map { $0.id }
    }

    func search() async throws {
        // 检查是否被取消
        try Task.checkCancellation()

        guard !searchText.isEmpty else {
            searchingStatus = ""
            return
        }

        // 设置搜索状态
        Logger.debug("开始搜索建筑，关键词: \(searchText)")
        searchingStatus = NSLocalizedString("Main_Search_Status_Finding_Structures", comment: "")

        // 收集所有找到的空间站ID
        var allStationIds = Set<Int>()
        var structureIds: [Int] = []

        // 1. 从内存缓存搜索空间站
        let localStationIds = searchLocalStations(searchText: searchText)
        allStationIds.formUnion(localStationIds)
        Logger.debug("本地缓存找到 \(localStationIds.count) 个空间站")

        // 2. 使用CharacterSearchAPI进行在线搜索
        do {
            let data = try await CharacterSearchAPI.shared.search(
                characterId: characterId,
                categories: [.station, .structure],
                searchText: searchText,
                strict: strictMatch
            )

            // 检查是否被取消
            try Task.checkCancellation()

            let response = try JSONDecoder().decode(SearcherView.SearchResponse.self, from: data)

            // 处理在线搜索结果
            if let stations = response.station {
                allStationIds.formUnion(stations)
                Logger.debug("在线搜索找到 \(stations.count) 个空间站")
            }

            // 处理建筑物
            if let structures = response.structure {
                structureIds = structures
                Logger.debug("找到 \(structures.count) 个建筑物")
            }
        } catch {
            Logger.error("在线搜索失败: \(error)")
            // 在线搜索失败时，继续使用本地搜索结果
        }

        // 合并所有结果并继续处理
        guard !allStationIds.isEmpty || !structureIds.isEmpty else {
            Logger.debug("没有找到任何建筑")
            searchResults = []
            filteredResults = []
            searchingStatus = ""
            return
        }

        var results: [SearcherView.SearchResult] = []

        // 处理空间站结果
        if !allStationIds.isEmpty {
            searchingStatus = NSLocalizedString(
                "Main_Search_Status_Loading_Station_Info", comment: ""
            )
            do {
                try Task.checkCancellation()

                // 批量获取空间站信息
                let stationsInfo = loadStationsInfo(stationIds: Array(allStationIds))

                // 批量获取位置信息
                let locationInfoMap = try await loadBatchLocationInfo(
                    systemIds: stationsInfo.map { $0.systemId }
                )

                // 处理每个空间站
                for info in stationsInfo {
                    try Task.checkCancellation()

                    guard let locationInfo = locationInfoMap[info.systemId] else {
                        Logger.error("未找到空间站位置信息: \(info.id)")
                        continue
                    }

                    results.append(
                        SearcherView.SearchResult(
                            id: info.id,
                            name: info.name,
                            type: .structure,
                            structureType: .station,
                            locationInfo: locationInfo,
                            typeId: info.typeId
                        )
                    )
                }
            } catch {
                if error is CancellationError {
                    throw error
                }
                Logger.error("批量获取空间站信息失败: \(error)")
            }
        }

        // 处理建筑物结果
        if !structureIds.isEmpty {
            searchingStatus = NSLocalizedString(
                "Main_Search_Status_Loading_Structure_Info", comment: ""
            )

            // 计算合适的批次大小：最小1，最大10，默认为总数的1/5
            let batchSize = min(max(structureIds.count / 5, 1), 10)
            Logger.info("batchSize: \(batchSize)")
            var allSystemIds: [Int] = []
            var structureInfos: [(id: Int, name: String, typeId: Int, systemId: Int)] = []

            // 使用 TaskGroup 并发获取建筑物基本信息
            try await withThrowingTaskGroup(of: (Int, String, Int, Int)?.self) { group in
                var processedCount = 0

                for batch in structureIds.chunked(into: batchSize) {
                    for structureId in batch {
                        group.addTask {
                            try Task.checkCancellation()

                            do {
                                let info = try await UniverseStructureAPI.shared.fetchStructureInfo(
                                    structureId: Int64(structureId),
                                    characterId: characterId,
                                    forceRefresh: true, // 建筑搜索功能总是联网搜索
                                    cacheTimeOut: 1
                                )

                                return (structureId, info.name, info.type_id, info.solar_system_id)
                            } catch {
                                if error is CancellationError {
                                    throw error
                                }
                                Logger.error("获取建筑物信息失败 - ID: \(structureId), 错误: \(error)")
                                return nil
                            }
                        }
                    }

                    // 等待当前批次完成
                    for try await result in group {
                        if let (id, name, typeId, systemId) = result {
                            structureInfos.append(
                                (id: id, name: name, typeId: typeId, systemId: systemId)
                            )
                            allSystemIds.append(systemId)
                        }
                        processedCount += 1
                        searchingStatus = String(
                            format: NSLocalizedString(
                                "Main_Search_Status_Loading_Structure_Progress", comment: ""
                            ),
                            processedCount,
                            structureIds.count
                        )
                    }
                }
            }

            let locationInfoMap = try await loadBatchLocationInfo(systemIds: allSystemIds)

            for info in structureInfos {
                try Task.checkCancellation()

                guard let locationInfo = locationInfoMap[info.systemId] else {
                    Logger.error("未找到建筑物位置信息: \(info.id)")
                    continue
                }

                results.append(
                    SearcherView.SearchResult(
                        id: info.id,
                        name: info.name,
                        type: .structure,
                        structureType: .structure,
                        locationInfo: locationInfo,
                        typeId: info.typeId
                    )
                )
            }
        }

        // 最后一次检查是否被取消
        try Task.checkCancellation()

        Logger.success("成功创建 \(results.count) 个搜索结果")

        // 按照指定的类型ID顺序排序
        results.sort { result1, result2 in
            // 定义优先级类型ID顺序
            let priorityTypeIds = [40340, 35834, 35833, 35827, 35832, 35825, 35836, 35826, 35835]

            let typeId1 = result1.typeId ?? 0
            let typeId2 = result2.typeId ?? 0

            // 获取优先级索引
            let priority1 = priorityTypeIds.firstIndex(of: typeId1) ?? Int.max
            let priority2 = priorityTypeIds.firstIndex(of: typeId2) ?? Int.max

            // 如果两个都在优先级列表中
            if priority1 != Int.max, priority2 != Int.max {
                if priority1 != priority2 {
                    return priority1 < priority2
                }
                // 同类型按建筑名称进行本地化比较排序
                return result1.name.localizedCompare(result2.name) == .orderedAscending
            }

            // 如果只有一个在优先级列表中
            if priority1 != Int.max {
                return true
            }
            if priority2 != Int.max {
                return false
            }

            // 两个都不在优先级列表中，按建筑名称进行本地化比较排序
            return result1.name.localizedCompare(result2.name) == .orderedAscending
        }

        searchResults = results

        // 根据当前的过滤条件设置过滤后的结果
        if structureType == .all {
            filteredResults = results
        } else {
            filteredResults = results.filter { result in
                result.structureType == structureType
            }
        }

        Logger.debug("建筑搜索完成，共有 \(results.count) 个结果，过滤后显示 \(filteredResults.count) 个结果")

        // 打印前5个结果的详细信息
        if !filteredResults.isEmpty {
            Logger.debug("前 \(min(5, filteredResults.count)) 个过滤后的结果:")
            for (index, result) in filteredResults.prefix(5).enumerated() {
                Logger.debug(
                    "\(index + 1). ID: \(result.id), 名称: \(result.name), 类型: \(result.structureType?.rawValue ?? "unknown")"
                )
            }
        }

        // 清除搜索状态
        searchingStatus = ""
    }
}
