import Foundation

// MARK: - Data Models

/// 军团资产数据结构与人物资产一致
public typealias CorporationAsset = CharacterAsset

/// 空间站信息
private struct StationInfo: Codable {
    let name: String
    let station_id: Int64
    let system_id: Int
    let type_id: Int
    let region_id: Int
    let security: Double
}

/// 资产名称响应
private struct AssetNameResponse: Codable {
    let item_id: Int64
    let name: String
}

/// 多语言系统信息
private struct SysInfo {
    let regionId: Int // 星域ID
    let security: Double // 安全等级
}

/// 顶层位置元数据（一次拉取后缓存，避免重复请求）
private struct LocationMeta {
    let name: String?
    let typeId: Int?
    let systemId: Int?
    let securityStatus: Double?
    let regionId: Int?
}

public class CorporationAssetsJsonAPI {
    public static let shared = CorporationAssetsJsonAPI()
    private let cacheTimeout: TimeInterval = 24 * 3600 // 24 小时缓存

    private init() {}

    // MARK: - Public Methods

    public func generateAssetTree(
        corporationId: Int,
        characterId: Int,
        forceRefresh: Bool = false,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> AssetTreeWrapper? {
        if !forceRefresh, let cached = loadCachedWrapper(corporationId: corporationId) {
            return cached
        }

        Logger.info("开始获取新的军团资产数据 - 原因: \(forceRefresh ? "强制刷新" : "无缓存或缓存过期")")
        // 403 负缓存统一由 CorpForbiddenCache 管理
        let assets = try await CorpForbiddenCache.shared.perform(
            scope: "corpAssets",
            corporationId: corporationId,
            characterId: characterId,
            forceRefresh: forceRefresh
        ) {
            try await fetchAllAssets(
                corporationId: corporationId,
                characterId: characterId
            ) { progress in
                progressCallback?(progress)
            }
        }

        if let wrapper = try await buildAssetTree(
            assets: assets,
            corporationId: corporationId,
            characterId: characterId,
            databaseManager: DatabaseManager(),
            progressCallback: progressCallback
        ) {
            saveToCache(wrapper: wrapper, corporationId: corporationId)
            progressCallback?(.completed)
            return wrapper
        }

        progressCallback?(.completed)
        return nil
    }

    // MARK: - Cache Methods

    private func getCacheFilePath(corporationId: Int, timestamp _: Date? = nil) -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "AssetCache", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )

        return cacheDirectory.appendingPathComponent("corp_asset_tree_\(corporationId).json")
    }

    private func loadCachedWrapper(corporationId: Int) -> AssetTreeWrapper? {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId),
              let data = try? Data(contentsOf: cacheFile),
              let wrapper = try? JSONDecoder().decode(AssetTreeWrapper.self, from: data)
        else {
            return nil
        }

        let cacheDate = Date(timeIntervalSince1970: TimeInterval(wrapper.update_time))
        guard Date().timeIntervalSince(cacheDate) < cacheTimeout else { return nil }

        let remainingTime = cacheTimeout - Date().timeIntervalSince(cacheDate)
        let remainingHours = Int(remainingTime / 3600)
        let remainingMinutes = Int((remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)
        Logger.info(
            "使用有效的缓存数据 - 剩余有效期: \(remainingHours)小时\(remainingMinutes)分钟 - 文件: \(cacheFile.path)"
        )
        return wrapper
    }

    private func saveToCache(wrapper: AssetTreeWrapper, corporationId: Int) {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else { return }

        do {
            let data = try JSONEncoder().encode(wrapper)
            try data.write(to: cacheFile)
            Logger.debug("军团资产树JSON已缓存到文件: \(cacheFile.path)")
        } catch {
            Logger.error("保存军团资产树缓存失败: \(error)")
        }
    }

    /// 获取所有资产
    private func fetchAllAssets(
        corporationId: Int,
        characterId: Int,
        forceRefresh _: Bool = false,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> [CorporationAsset] {
        let baseUrlString =
            "https://esi.evetech.net/corporations/\(corporationId)/assets/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw AssetError.invalidURL
        }

        return try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,
            decoder: { try JSONDecoder().decode([CorporationAsset].self, from: $0) },
            progressCallback: { currentPage, _ in
                progressCallback?(.loading(page: currentPage))
            }
        )
    }

    /// 获取空间站信息（来自 SDEMemoryStore 内存缓存）
    private func fetchStationInfo(stationId: Int64) async throws -> StationInfo {
        guard let info = SDEMemoryStore.station(for: Int(stationId)),
              let stationTypeID = info.stationTypeID,
              let solarSystemID = info.solarSystemID,
              let regionID = info.regionID,
              let security = info.security
        else {
            throw AssetError.locationFetchError("Failed to fetch station info from database")
        }

        return StationInfo(
            name: info.name,
            station_id: stationId,
            system_id: solarSystemID,
            type_id: stationTypeID,
            region_id: regionID,
            security: security
        )
    }

    /// 收集所有容器的ID (除了最顶层建筑物)
    /// 只收集categoryID为6、22、65的容器
    private func collectContainerIds(
        from nodes: [AssetTreeNode],
        databaseManager _: DatabaseManager
    ) -> (ids: Set<Int64>, idToTypeId: [Int64: Int]) {
        var containerCandidates: [(itemId: Int64, typeId: Int)] = []

        func collect(from node: AssetTreeNode, isRoot: Bool = false) {
            // 如果不是根节点且有子项，则这是一个容器
            if !isRoot, node.items != nil, !node.items!.isEmpty {
                containerCandidates.append((itemId: node.item_id, typeId: node.type_id))
            }

            // 递归处理子节点
            if let items = node.items {
                for item in items {
                    collect(from: item)
                }
            }
        }

        // 从根节点开始收集，但标记为根节点以跳过它们
        for node in nodes {
            collect(from: node, isRoot: true)
        }

        // 如果没有任何容器，直接返回
        if containerCandidates.isEmpty {
            return (Set<Int64>(), [:])
        }

        // 查询这些type_id的categoryID，只保留categoryID为2、6、22、65的容器
        let typeIds = Set(containerCandidates.map { $0.typeId })
        var validTypeIds = Set<Int>()
        for typeId in typeIds {
            if let categoryID = ItemInfoMap.typeInfo(for: typeId)?.categoryID,
               [2, 6, 22, 65].contains(categoryID)
            {
                validTypeIds.insert(typeId)
            }
        }

        // 过滤掉不符合categoryID要求的容器
        let filteredContainers = containerCandidates
            .filter { validTypeIds.contains($0.typeId) }

        var containerIds = Set<Int64>()
        var idToTypeId: [Int64: Int] = [:]
        for container in filteredContainers {
            containerIds.insert(container.itemId)
            idToTypeId[container.itemId] = container.typeId
        }

        Logger.debug("收集容器ID - 总候选数: \(containerCandidates.count), 符合categoryID(2,6,22,65)的数量: \(containerIds.count)")

        return (containerIds, idToTypeId)
    }

    /// 获取容器名称
    private func fetchContainerNames(
        containerIds: [Int64],
        idToTypeId _: [Int64: Int],
        corporationId: Int,
        characterId: Int,
        databaseManager _: DatabaseManager
    ) async throws -> [Int64: String] {
        guard !containerIds.isEmpty else { return [:] }

        let urlString =
            "https://esi.evetech.net/corporations/\(corporationId)/assets/names/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw AssetError.invalidURL
        }

        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]

        // 将ID列表转换为JSON数据
        guard let jsonData = try? JSONEncoder().encode(containerIds) else {
            throw AssetError.invalidData("Failed to encode container IDs")
        }

        do {
            let data = try await NetworkManager.shared.postDataWithToken(
                to: url,
                body: jsonData,
                characterId: characterId,
                headers: headers
            )

            let nameResponses = try JSONDecoder().decode([AssetNameResponse].self, from: data)

            // 转换为字典
            var namesDict: [Int64: String] = [:]
            for response in nameResponses {
                namesDict[response.item_id] = response.name
            }

            return namesDict
        } catch {
            Logger.error("获取容器名称失败: \(error)")
            throw error
        }
    }

    /// 递归构建树节点的辅助函数
    private func buildTreeNode(
        from asset: CorporationAsset,
        locationMap: [Int64: [CorporationAsset]],
        names: [Int64: String]
    ) -> AssetTreeNode {
        let children = locationMap[asset.item_id, default: []].map { childAsset in
            buildTreeNode(from: childAsset, locationMap: locationMap, names: names)
        }

        return AssetTreeNode(
            location_id: asset.location_id,
            item_id: asset.item_id,
            type_id: asset.type_id,
            location_type: asset.location_type,
            location_flag: asset.location_flag,
            quantity: asset.quantity,
            name: names[asset.item_id],
            is_singleton: asset.is_singleton,
            is_blueprint_copy: asset.is_blueprint_copy,
            items: children.isEmpty ? nil : children
        )
    }

    private func buildAssetTree(
        assets: [CorporationAsset],
        corporationId: Int,
        characterId: Int,
        databaseManager: DatabaseManager,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> AssetTreeWrapper? {
        progressCallback?(.buildingTree)

        var locationMap: [Int64: [CorporationAsset]] = [:]
        for asset in assets {
            locationMap[asset.location_id, default: []].append(asset)
        }

        var topLocations: Set<Int64> = Set(assets.map { $0.location_id })
        for asset in assets {
            topLocations.remove(asset.item_id)
        }

        progressCallback?(.processingLocations)
        let locationMeta = try await fetchLocationMetaBatch(
            topLocations: topLocations,
            locationMap: locationMap,
            characterId: characterId,
            databaseManager: databaseManager,
            progressCallback: progressCallback
        )

        var rootNodes = buildRootNodes(
            topLocations: topLocations,
            locationMap: locationMap,
            locationMeta: locationMeta,
            names: [:],
            databaseManager: databaseManager
        )

        progressCallback?(.preparingContainers)
        let (containerIds, idToTypeId) = collectContainerIds(
            from: rootNodes, databaseManager: databaseManager
        )

        var allNames: [Int64: String] = [:]
        if !containerIds.isEmpty {
            progressCallback?(.loadingNames(current: 0, total: containerIds.count))
            do {
                let containerNames = try await fetchContainerNames(
                    containerIds: Array(containerIds),
                    idToTypeId: idToTypeId,
                    corporationId: corporationId,
                    characterId: characterId,
                    databaseManager: databaseManager
                )
                allNames = containerNames
            } catch {
                Logger.warning("获取容器名称失败，将不显示自定义名称: \(error)")
            }
        }

        if !allNames.isEmpty {
            applyNamesToTree(&rootNodes, names: allNames)
        }

        progressCallback?(.savingCache)
        return AssetTreeWrapper(
            update_time: Int64(Date().timeIntervalSince1970),
            assetsTree: rootNodes
        )
    }

    private func fetchLocationMetaBatch(
        topLocations: Set<Int64>,
        locationMap: [Int64: [CorporationAsset]],
        characterId: Int,
        databaseManager: DatabaseManager,
        progressCallback: ((AssetLoadingProgress) -> Void)? = nil
    ) async throws -> [Int64: LocationMeta] {
        var result: [Int64: LocationMeta] = [:]
        let locationArray = Array(topLocations)
        let totalLocations = locationArray.count
        let concurrentLimit = 5
        var currentIndex = 0
        var processedLocations = 0

        while currentIndex < locationArray.count {
            try await withThrowingTaskGroup(of: (Int64, LocationMeta).self) { group in
                let endIndex = min(currentIndex + concurrentLimit, locationArray.count)
                for locationId in locationArray[currentIndex ..< endIndex] {
                    guard let items = locationMap[locationId] else { continue }
                    let locationType =
                        items.first?.location_type ?? NSLocalizedString("Unknown", comment: "")
                    group.addTask {
                        let info = try await self.fetchLocationInfo(
                            locationId: locationId,
                            locationType: locationType,
                            characterId: characterId,
                            databaseManager: databaseManager
                        )
                        return (
                            locationId,
                            LocationMeta(
                                name: info.name,
                                typeId: info.typeId,
                                systemId: info.systemId,
                                securityStatus: info.securityStatus,
                                regionId: info.regionId
                            )
                        )
                    }
                }

                for try await (locationId, meta) in group {
                    processedLocations += 1
                    progressCallback?(
                        .fetchingStructureInfo(current: processedLocations, total: totalLocations)
                    )
                    result[locationId] = meta
                }
            }

            currentIndex += concurrentLimit
            if currentIndex < locationArray.count {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        return result
    }

    private func buildRootNodes(
        topLocations: Set<Int64>,
        locationMap: [Int64: [CorporationAsset]],
        locationMeta: [Int64: LocationMeta],
        names _: [Int64: String],
        databaseManager: DatabaseManager
    ) -> [AssetTreeNode] {
        var rootNodes: [AssetTreeNode] = []

        for locationId in topLocations {
            guard let items = locationMap[locationId] else { continue }
            let locationType = items.first?.location_type ?? NSLocalizedString("Unknown", comment: "")
            let meta = locationMeta[locationId]

            let nodeName = rootNodeName(
                locationType: locationType,
                meta: meta,
                databaseManager: databaseManager
            )

            rootNodes.append(
                AssetTreeNode(
                    location_id: locationId,
                    item_id: locationId,
                    type_id: meta?.typeId ?? 0,
                    location_type: locationType,
                    location_flag: "root",
                    quantity: 1,
                    name: nodeName,
                    is_singleton: true,
                    system_id: meta?.systemId,
                    region_id: meta?.regionId,
                    security_status: meta?.securityStatus,
                    items: items.map {
                        buildTreeNode(from: $0, locationMap: locationMap, names: [:])
                    }
                )
            )
        }

        return rootNodes
    }

    private func rootNodeName(
        locationType: String,
        meta: LocationMeta?,
        databaseManager _: DatabaseManager
    ) -> String? {
        switch locationType {
        case "station", "solar_system":
            return nil
        default:
            if let name = meta?.name {
                return name
            }
            if let typeId = meta?.typeId {
                return ItemInfoMap.typeName(for: typeId)
            }
            return nil
        }
    }

    private func applyNamesToTree(_ nodes: inout [AssetTreeNode], names: [Int64: String]) {
        for index in nodes.indices {
            applyNames(to: &nodes[index], names: names)
        }
    }

    private func applyNames(to node: inout AssetTreeNode, names: [Int64: String]) {
        if let name = names[node.item_id] {
            node.name = name
        }
        if var items = node.items {
            for index in items.indices {
                applyNames(to: &items[index], names: names)
            }
            node.items = items
        }
    }

    /// 获取多语言星系信息
    private func fetchSystemInfo(solarSystemId: Int, databaseManager: DatabaseManager) async
        -> SysInfo?
    {
        // 构建查询语句获取星系信息和区域信息
        let query = """
            SELECT region_id, system_security from universe where solarsystem_id = ?
        """

        if case let .success(rows) = databaseManager.executeQuery(
            query, parameters: [solarSystemId]
        ) {
            if let row = rows.first,
               let security = row["system_security"] as? Double,
               let region_id = row["region_id"] as? Int
            {
                return SysInfo(
                    regionId: region_id,
                    security: security
                )
            }
        }
        return nil
    }

    /// 获取位置信息的辅助方法
    private func fetchLocationInfo(
        locationId: Int64,
        locationType: String,
        characterId: Int,
        databaseManager: DatabaseManager
    ) async throws -> (
        name: String?, typeId: Int?, systemId: Int?, securityStatus: Double?, regionId: Int?
    ) {
        var locationName: String?
        var typeId: Int?
        var systemId: Int?
        var securityStatus: Double?
        var regionId: Int?

        // 处理太空中的物资（solar_system类型）
        if locationType == "solar_system" {
            systemId = Int(locationId)
            if let systemInfo = await fetchSystemInfo(
                solarSystemId: Int(locationId), databaseManager: databaseManager
            ) {
                securityStatus = systemInfo.security
                regionId = systemInfo.regionId
            }
            // typeId 存 system_type 供图标解析（内存索引）
            typeId = SDEMemoryStore.universeSystems[Int(locationId)]?.systemType
            return (locationName, typeId, systemId, securityStatus, regionId)
        }

        if locationType == "station" {
            if let stationInfo = try? await fetchStationInfo(
                stationId: locationId
            ) {
                locationName = stationInfo.name
                typeId = stationInfo.type_id
                systemId = stationInfo.system_id
                securityStatus = stationInfo.security
                regionId = stationInfo.region_id

                // 获取星系和星域名称（多语言）
                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: stationInfo.system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                }
            } else if let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: locationId, characterId: characterId
            ) {
                locationName = structureInfo.name
                typeId = structureInfo.type_id
                systemId = structureInfo.solar_system_id

                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                    regionId = systemInfo.regionId
                }
            }
        } else {
            if let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: locationId, characterId: characterId
            ) {
                locationName = structureInfo.name
                typeId = structureInfo.type_id
                systemId = structureInfo.solar_system_id

                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: structureInfo.solar_system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                    regionId = systemInfo.regionId
                }
            } else if let stationInfo = try? await fetchStationInfo(
                stationId: locationId
            ) {
                locationName = stationInfo.name
                typeId = stationInfo.type_id
                systemId = stationInfo.system_id
                securityStatus = stationInfo.security
                regionId = stationInfo.region_id

                if let systemInfo = await fetchSystemInfo(
                    solarSystemId: stationInfo.system_id, databaseManager: databaseManager
                ) {
                    securityStatus = systemInfo.security
                }
            }
        }

        return (locationName, typeId, systemId, securityStatus, regionId)
    }
}
