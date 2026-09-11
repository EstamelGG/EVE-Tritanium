import SwiftUI

/// 行星信息模型
struct PlanetTypeInfo {
    let name: String
    let icon: String
}

/// 多人物多选时：各星球类型在已选人物下的殖民数量汇总
struct AggregatedPlanetTypeSummary: Identifiable {
    let planetTypeKey: String
    let count: Int
    let displayName: String
    let iconFileName: String

    var id: String {
        planetTypeKey
    }
}

/// 最终产品模型
struct FinalProduct: Identifiable {
    let id: Int // typeId
    let typeId: Int
    let icon: String
}

/// 采集器状态模型
struct ExtractorStatus {
    let totalCount: Int // 总采集器数量
    let expiredCount: Int // 已停工的采集器数量
    let expiringSoonCount: Int // 即将在1小时内停工的采集器数量
}

/// 扩展CharacterPlanetaryInfo来包含角色归属信息
struct PlanetWithOwner {
    let planet: CharacterPlanetaryInfo
    let ownerId: Int // 该行星归属的角色ID
}

@MainActor
final class CharacterPlanetaryViewModel: ObservableObject {
    @Published private(set) var planets: [CharacterPlanetaryInfo] = []
    @Published private(set) var planetNames: [Int: String] = [:]
    @Published private(set) var planetTypeInfo: [Int: PlanetTypeInfo] = [:]
    @Published private(set) var systemSecurities: [Int: Double] = [:] // 星系安等信息 [systemId: security]
    @Published private(set) var earliestExtractorExpiry: [String: Date] = [:] // 每个行星的最早采集器过期时间 [key: Date]，key格式为 "characterId_planetId"
    @Published private(set) var finalProducts: [String: [FinalProduct]] = [:] // 每个行星的最终产品 [key: [FinalProduct]]，key格式为 "characterId_planetId"
    @Published private(set) var loadingPlanets: Set<String> = [] // 正在加载的行星ID集合，key格式为 "characterId_planetId"
    @Published private(set) var extractorStatus: [String: ExtractorStatus] = [:] // 每个行星的采集器状态 [key: ExtractorStatus]，key格式为 "characterId_planetId"
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var loadingProgress: (current: Int, total: Int)? = nil // 加载进度 (已加载/总数)

    /// 多人物聚合相关
    @Published var multiCharacterMode = false {
        didSet {
            UserDefaults.standard.set(multiCharacterMode, forKey: "multiCharacterMode_planetary")
            if initialLoadDone {
                Task {
                    await loadPlanets(forceRefresh: true)
                }
            }
        }
    }

    @Published var selectedCharacterIds: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_planetary"
            )
            if initialLoadDone, multiCharacterMode {
                Task {
                    await loadPlanets(forceRefresh: true)
                }
            }
        }
    }

    /// 多人物模式下是否在列表顶部展示星球类型汇总（默认关闭，写入 UserDefaults）
    @Published var showPlanetTypeSummaryInMultiSelect = false {
        didSet {
            UserDefaults.standard.set(
                showPlanetTypeSummaryInMultiSelect,
                forKey: "showPlanetTypeSummary_planetary"
            )
        }
    }

    @Published var availableCharacters: [(id: Int, name: String)] = []

    var planetsWithOwner: [PlanetWithOwner] = [] // 包含所有者信息的行星列表
    @Published var planetOwners: [Int: Int] = [:] // 每个行星对应的角色ID [planetId: characterId]
    @Published var maxPlanetsByCharacter: [Int: Int] = [:] // 每个角色的可支配星球数 [characterId: maxPlanets]

    private var loadingTask: Task<Void, Never>?
    private var expiryLoadingTask: Task<Void, Never>?
    private let characterId: Int?
    private var initialLoadDone = false

    /// Schematic 缓存，避免重复查询数据库
    private var schematicCache: [Int: Schematic] = [:]

    /// Type 缓存（包括图标信息），避免重复查询数据库
    private var typeCache: [Int: (name: String, icon: String)] = [:]

    init(characterId: Int?) {
        self.characterId = characterId

        // 从 UserDefaults 读取多人物聚合设置
        multiCharacterMode = UserDefaults.standard.bool(forKey: "multiCharacterMode_planetary")
        showPlanetTypeSummaryInMultiSelect = UserDefaults.standard.bool(
            forKey: "showPlanetTypeSummary_planetary"
        )
        let savedCharacterIds =
            UserDefaults.standard.array(forKey: "selectedCharacterIds_planetary") as? [Int] ?? []
        selectedCharacterIds = Set(savedCharacterIds)

        // 加载可用角色列表
        availableCharacters = CharacterSkillsUtils.getAllCharacters()

        // 过滤掉已保存但已不在可用角色列表中的角色ID
        let availableCharacterIds = Set(availableCharacters.map { $0.id })
        let validSelectedIds = selectedCharacterIds.intersection(availableCharacterIds)

        // 如果有角色被过滤掉，更新 UserDefaults
        if validSelectedIds.count != selectedCharacterIds.count {
            selectedCharacterIds = validSelectedIds
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_planetary"
            )
        }

        // 如果没有选中的角色，默认选择当前角色
        if selectedCharacterIds.isEmpty, let characterId = characterId {
            selectedCharacterIds.insert(characterId)
        }

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadPlanets()
        }
    }

    deinit {
        loadingTask?.cancel()
        expiryLoadingTask?.cancel()
    }

    private func loadPlanetTypeInfo() async throws -> [Int: PlanetTypeInfo] {
        let typeIds = Array(PlanetaryUtils.planetTypeToColumn.keys).sorted()
        var tempPlanetTypeInfo: [Int: PlanetTypeInfo] = [:]

        for typeId in typeIds {
            guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else { continue }
            tempPlanetTypeInfo[typeId] = PlanetTypeInfo(
                name: info.name, icon: info.iconFilename
            )
        }

        return tempPlanetTypeInfo
    }

    func loadPlanets(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                // 首先加载行星类型信息（静态数据）
                let planetTypeInfo = try await loadPlanetTypeInfo()

                // 确定要加载的角色ID列表
                let characterIdsToLoad: [Int]
                if multiCharacterMode, selectedCharacterIds.count > 1 {
                    characterIdsToLoad = Array(selectedCharacterIds)
                } else if multiCharacterMode, !selectedCharacterIds.isEmpty {
                    characterIdsToLoad = [selectedCharacterIds.first!]
                } else if let characterId = characterId {
                    characterIdsToLoad = [characterId]
                } else {
                    characterIdsToLoad = []
                }

                if !characterIdsToLoad.isEmpty {
                    var allPlanets: [CharacterPlanetaryInfo] = []
                    var allPlanetsWithOwner: [PlanetWithOwner] = []
                    var tempPlanetOwners: [Int: Int] = [:]
                    let totalCharacters = characterIdsToLoad.count

                    // 初始化加载进度
                    await MainActor.run {
                        self.loadingProgress = (current: 0, total: totalCharacters)
                    }

                    // 并发获取所有角色的行星信息
                    await withTaskGroup(of: (Int, Result<[CharacterPlanetaryInfo], Error>).self) { group in
                        for charId in characterIdsToLoad {
                            group.addTask {
                                do {
                                    let planetsList = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(
                                        characterId: charId, forceRefresh: forceRefresh
                                    )
                                    return (charId, .success(planetsList))
                                } catch {
                                    Logger.error("获取角色\(charId)行星数据失败: \(error)")
                                    return (charId, .failure(error))
                                }
                            }
                        }

                        // 使用 Actor 来线程安全地更新进度
                        let progressActor = ProgressActor(total: totalCharacters) { current, total in
                            Task { @MainActor in
                                self.loadingProgress = (current: current, total: total)
                            }
                        }

                        // 收集结果
                        for await (charId, result) in group {
                            switch result {
                            case let .success(planetsList):
                                allPlanets.append(contentsOf: planetsList)
                                // 为每个行星添加所有者信息
                                for planet in planetsList {
                                    allPlanetsWithOwner.append(PlanetWithOwner(planet: planet, ownerId: charId))
                                    tempPlanetOwners[planet.planetId] = charId
                                }
                            case .failure:
                                // 失败时继续处理，不中断
                                break
                            }

                            // 更新进度
                            await progressActor.increment()
                        }
                    }

                    if Task.isCancelled { return }

                    // 获取所有行星ID
                    let planetIds = allPlanets.map { $0.planetId }

                    if Task.isCancelled { return }

                    var tempSystemSecurities: [Int: Double] = [:]

                    // 批量获取星系安等信息（内存索引）
                    for systemId in Set(allPlanets.map { $0.solarSystemId }) {
                        if let info = SDEMemoryStore.universeSystems[systemId] {
                            tempSystemSecurities[systemId] = info.security
                        }
                    }

                    let tempPlanetNames = DatabaseManager.shared.getCelestialNames(itemIDs: planetIds)

                    if Task.isCancelled { return }

                    await MainActor.run {
                        self.planets = allPlanets
                        self.planetsWithOwner = allPlanetsWithOwner
                        self.planetOwners = tempPlanetOwners
                        self.planetNames = tempPlanetNames
                        self.planetTypeInfo = planetTypeInfo
                        self.systemSecurities = tempSystemSecurities
                        self.isLoading = false
                        self.initialLoadDone = true
                        // 清除加载进度
                        self.loadingProgress = nil
                    }

                    // 加载技能数据计算可支配星球数
                    await loadMaxPlanets(characterIds: characterIdsToLoad, forceRefresh: forceRefresh)

                    // 异步加载所有行星的采集器过期时间（最多6线程）
                    // 需要为每个行星传递对应的角色ID
                    await loadExtractorExpiryTimes(planetsWithOwner: allPlanetsWithOwner)
                } else {
                    // 如果没有选择角色，只加载静态数据
                    await MainActor.run {
                        self.planets = []
                        self.planetsWithOwner = []
                        self.planetOwners = [:]
                        self.planetNames = [:]
                        self.planetTypeInfo = planetTypeInfo
                        self.systemSecurities = [:]
                        self.isLoading = false
                        self.initialLoadDone = true
                    }
                }
            } catch {
                Logger.error("加载行星数据失败: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    func getPlanetTypeInfo(for planetType: String) -> PlanetTypeInfo? {
        // 通过columnToPlanetType找到对应的行星类型ID
        if let typeId = PlanetaryUtils.columnToPlanetType[planetType],
           let info = planetTypeInfo[typeId]
        {
            return info
        }
        return nil
    }

    func getPlanetName(for planetId: Int) -> String {
        return planetNames[planetId]
            ?? NSLocalizedString("Main_Planetary_Unknown_Planet", comment: "")
    }

    func getSystemSecurity(for systemId: Int) -> Double? {
        return systemSecurities[systemId]
    }

    /// 生成行星数据的唯一键
    private func makePlanetKey(characterId: Int, planetId: Int) -> String {
        return "\(characterId)_\(planetId)"
    }

    func getEarliestExtractorExpiry(for planetId: Int, characterId: Int? = nil) -> Date? {
        if let characterId = characterId {
            return earliestExtractorExpiry[makePlanetKey(characterId: characterId, planetId: planetId)]
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return earliestExtractorExpiry[makePlanetKey(characterId: ownerId, planetId: planetId)]
        }
        return nil
    }

    func getFinalProducts(for planetId: Int, characterId: Int? = nil) -> [FinalProduct] {
        if let characterId = characterId {
            return finalProducts[makePlanetKey(characterId: characterId, planetId: planetId)] ?? []
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return finalProducts[makePlanetKey(characterId: ownerId, planetId: planetId)] ?? []
        }
        return []
    }

    func getExtractorStatus(for planetId: Int, characterId: Int? = nil) -> ExtractorStatus? {
        if let characterId = characterId {
            return extractorStatus[makePlanetKey(characterId: characterId, planetId: planetId)]
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return extractorStatus[makePlanetKey(characterId: ownerId, planetId: planetId)]
        }
        return nil
    }

    /// 与 `PlanetRow` 采集器提示共用：该殖民地是否应以红色突出采集器状态（已停工、约 1 小时内停工、或最早到期已过期 / 不足 24h）
    func planetNeedsExtractorAttention(planetId: Int, characterId: Int) -> Bool {
        if let status = getExtractorStatus(for: planetId, characterId: characterId), status.totalCount > 0 {
            if status.expiredCount > 0 { return true }
            if status.expiringSoonCount > 0 { return true }
        }
        guard let expiryDate = getEarliestExtractorExpiry(for: planetId, characterId: characterId) else {
            return false
        }
        // 已过期（remaining ≤ 0）与 24h 内到期均满足 remaining < 24h
        return expiryDate.timeIntervalSince(Date()) < 24 * 3600
    }

    /// 表头部署数标红：该角色下列表行所需的行星详情**全部加载完成后**，若任一行会出现红色采集器提示则为 true
    func characterHeaderShowsExtractorAttention(planets: [CharacterPlanetaryInfo], characterId: Int) -> Bool {
        guard planets.allSatisfy({ !isLoadingPlanetDetail(for: $0.planetId, characterId: characterId) }) else {
            return false
        }
        return planets.contains { planetNeedsExtractorAttention(planetId: $0.planetId, characterId: characterId) }
    }

    func isLoadingPlanetDetail(for planetId: Int, characterId: Int? = nil) -> Bool {
        if let characterId = characterId {
            return loadingPlanets.contains(makePlanetKey(characterId: characterId, planetId: planetId))
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return loadingPlanets.contains(makePlanetKey(characterId: ownerId, planetId: planetId))
        }
        return false
    }

    /// 获取行星对应的角色ID
    func getPlanetOwner(for planetId: Int) -> Int? {
        return planetOwners[planetId]
    }

    /// 加载每个角色的可支配星球数（基于技能ID 2495）
    private func loadMaxPlanets(characterIds: [Int], forceRefresh: Bool = false) async {
        var tempMaxPlanets: [Int: Int] = [:]

        // 并发获取所有角色的技能数据
        await withTaskGroup(of: (Int, Int).self) { group in
            for charId in characterIds {
                group.addTask {
                    do {
                        let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                            characterId: charId,
                            forceRefresh: forceRefresh
                        )

                        // 查找技能ID 2495的等级
                        let skillLevel = skillsResponse.skillsMap[2495]?.trained_skill_level ?? 0

                        // 可支配星球数 = 技能等级 + 1
                        let maxPlanets = skillLevel + 1
                        return (charId, maxPlanets)
                    } catch {
                        Logger.error("获取角色\(charId)技能数据失败: \(error)")
                        // 如果获取失败，默认设置为1
                        return (charId, 1)
                    }
                }
            }

            // 收集结果
            for await (charId, maxPlanets) in group {
                tempMaxPlanets[charId] = maxPlanets
            }
        }

        await MainActor.run {
            self.maxPlanetsByCharacter = tempMaxPlanets
        }
    }

    /// 按人物ID分组行星（用于多人物聚合模式）
    var groupedPlanetsByCharacter: [(characterId: Int, characterName: String, planets: [CharacterPlanetaryInfo], maxPlanets: Int)] {
        guard multiCharacterMode, selectedCharacterIds.count > 1 else {
            return []
        }

        var grouped: [Int: [CharacterPlanetaryInfo]] = [:]

        // 按角色ID分组
        for planetWithOwner in planetsWithOwner {
            if grouped[planetWithOwner.ownerId] == nil {
                grouped[planetWithOwner.ownerId] = []
            }
            grouped[planetWithOwner.ownerId]?.append(planetWithOwner.planet)
        }

        // 转换为数组并排序：当前登录人物排在第一位，其他按角色ID排序
        return grouped.compactMap { charId, planets -> (characterId: Int, characterName: String, planets: [CharacterPlanetaryInfo], maxPlanets: Int)? in
            // 获取角色名称
            let characterName = availableCharacters.first(where: { $0.id == charId })?.name ?? "Unknown"
            // 获取可支配星球数，如果未加载则默认为1
            let maxPlanets = maxPlanetsByCharacter[charId] ?? 1
            return (characterId: charId, characterName: characterName, planets: planets, maxPlanets: maxPlanets)
        }
        .sorted { first, second in
            // 如果第一个是当前登录人物，排在前面
            if first.characterId == characterId {
                return true
            }
            // 如果第二个是当前登录人物，排在前面
            if second.characterId == characterId {
                return false
            }
            // 其他情况按角色ID排序
            return first.characterId < second.characterId
        }
    }

    /// 多选人物（>1）时：已选人物殖民星球按 `planet_type` 的数量汇总，供列表顶部 Section 使用
    var aggregatedPlanetTypeSummariesForMultiSelect: [AggregatedPlanetTypeSummary] {
        guard multiCharacterMode, selectedCharacterIds.count > 1, showPlanetTypeSummaryInMultiSelect else {
            return []
        }

        var counts: [String: Int] = [:]
        for planetWithOwner in planetsWithOwner where selectedCharacterIds.contains(planetWithOwner.ownerId) {
            let key = planetWithOwner.planet.planetType
            counts[key, default: 0] += 1
        }

        return counts.map { planetTypeKey, count -> AggregatedPlanetTypeSummary in
            if let info = getPlanetTypeInfo(for: planetTypeKey) {
                let icon = info.icon.isEmpty ? IconManager.defaultItemIcon : info.icon
                return AggregatedPlanetTypeSummary(
                    planetTypeKey: planetTypeKey,
                    count: count,
                    displayName: info.name,
                    iconFileName: icon
                )
            }
            return AggregatedPlanetTypeSummary(
                planetTypeKey: planetTypeKey,
                count: count,
                displayName: NSLocalizedString("Main_Planetary_Unknown_Type", comment: ""),
                iconFileName: IconManager.defaultItemIcon
            )
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// 异步加载所有行星的采集器过期时间，最多6个并发线程
    private func loadExtractorExpiryTimes(planetsWithOwner: [PlanetWithOwner]) async {
        // 取消之前的任务
        expiryLoadingTask?.cancel()

        // 清理之前的加载状态
        await MainActor.run {
            self.loadingPlanets.removeAll()
        }

        expiryLoadingTask = Task {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]

            // 初始化加载状态：将所有行星标记为正在加载
            await MainActor.run {
                self.loadingPlanets = Set(planetsWithOwner.map { planetWithOwner in
                    self.makePlanetKey(characterId: planetWithOwner.ownerId, planetId: planetWithOwner.planet.planetId)
                })
            }

            // 第一步：先加载所有行星详情，收集所有需要的 schematicId
            // 同时检查是否有缓存的计算结果
            var allDetails: [PlanetaryDetail] = []
            var detailMap: [String: PlanetaryDetail] = [:] // key: "characterId_planetId"
            var cachedResultsMap: [String: CachedPlanetaryResults] = [:] // key: "characterId_planetId"

            // 手动控制并发数量（最多6个并发）
            let maxConcurrent = 6
            var pendingPlanets = Array(planetsWithOwner)

            await withTaskGroup(of: (String, PlanetaryDetail?, CachedPlanetaryResults?).self) { group in
                // 初始添加并发数量的任务
                for _ in 0 ..< min(maxConcurrent, pendingPlanets.count) {
                    if Task.isCancelled { break }
                    if pendingPlanets.isEmpty { break }

                    let planetWithOwner = pendingPlanets.removeFirst()
                    let planetKey = "\(planetWithOwner.ownerId)_\(planetWithOwner.planet.planetId)"

                    group.addTask {
                        do {
                            let (detail, cachedResults) = try await CharacterPlanetaryAPI.fetchPlanetaryDetailWithCache(
                                characterId: planetWithOwner.ownerId,
                                planetId: planetWithOwner.planet.planetId,
                                forceRefresh: false
                            )
                            return (planetKey, detail, cachedResults)
                        } catch {
                            Logger.warning("获取行星 \(planetWithOwner.planet.planetId) (角色: \(planetWithOwner.ownerId)) 详情失败: \(error.localizedDescription)")
                            return (planetKey, nil, nil)
                        }
                    }
                }

                // 处理结果并添加新任务
                while let (planetKey, detail, cachedResults) = await group.next() {
                    if Task.isCancelled { break }

                    if let detail = detail {
                        allDetails.append(detail)
                        detailMap[planetKey] = detail

                        // 如果有缓存的计算结果，保存并立即更新UI（采集器信息）
                        if let cachedResults = cachedResults {
                            cachedResultsMap[planetKey] = cachedResults

                            // 立即更新UI（从缓存读取采集器信息，最终产品等 typeCache 加载后再更新）
                            await MainActor.run {
                                // 更新采集器过期时间
                                if let expiry = cachedResults.earliestExtractorExpiry {
                                    self.earliestExtractorExpiry[planetKey] = expiry
                                }

                                // 更新采集器状态
                                let extractorStatus = ExtractorStatus(
                                    totalCount: cachedResults.extractorStatus.totalCount,
                                    expiredCount: cachedResults.extractorStatus.expiredCount,
                                    expiringSoonCount: cachedResults.extractorStatus.expiringSoonCount
                                )
                                self.extractorStatus[planetKey] = extractorStatus

                                // 注意：最终产品需要等 typeCache 加载完成后再更新（在第四步处理）
                                // loadingPlanets 会在第四步最终产品更新完成后移除
                            }
                        }
                    }

                    // 如果还有待处理的行星，添加新任务
                    if !pendingPlanets.isEmpty {
                        let planetWithOwner = pendingPlanets.removeFirst()
                        let newPlanetKey = "\(planetWithOwner.ownerId)_\(planetWithOwner.planet.planetId)"

                        group.addTask {
                            do {
                                let (detail, cachedResults) = try await CharacterPlanetaryAPI.fetchPlanetaryDetailWithCache(
                                    characterId: planetWithOwner.ownerId,
                                    planetId: planetWithOwner.planet.planetId,
                                    forceRefresh: false
                                )
                                return (newPlanetKey, detail, cachedResults)
                            } catch {
                                Logger.warning("获取行星 \(planetWithOwner.planet.planetId) (角色: \(planetWithOwner.ownerId)) 详情失败: \(error.localizedDescription)")
                                return (newPlanetKey, nil, nil)
                            }
                        }
                    }
                }
            }

            if Task.isCancelled { return }

            // 第二步：从所有行星详情中收集所有需要的 schematicId 和采集器输出的 typeId
            var schematicIds = Set<Int>()
            var extractorProductTypeIds = Set<Int>() // 采集器输出的产品类型ID

            for detail in allDetails {
                for pin in detail.pins {
                    if let factoryDetails = pin.factoryDetails {
                        schematicIds.insert(factoryDetails.schematicId)
                    } else if let schematicId = pin.schematicId {
                        schematicIds.insert(schematicId)
                    }

                    // 收集采集器输出的产品类型ID
                    if let extractorDetails = pin.extractorDetails,
                       let productTypeId = extractorDetails.productTypeId
                    {
                        extractorProductTypeIds.insert(productTypeId)
                    }
                }
            }

            // 第三步：批量加载所有 schematic 和相关的 type 信息到缓存
            if !schematicIds.isEmpty || !extractorProductTypeIds.isEmpty {
                await loadSchematicsAndTypesBatch(
                    schematicIds: Array(schematicIds),
                    extractorProductTypeIds: Array(extractorProductTypeIds),
                    allDetails: allDetails
                )
            }

            if Task.isCancelled { return }

            // 第四步：处理所有行星数据
            // 1. 对于有缓存结果的行星，从 typeCache 获取图标信息并更新UI
            // 2. 对于没有缓存结果的行星，进行计算并保存到缓存
            await withTaskGroup(of: (String, Date?, [FinalProduct], ExtractorStatus?, Bool).self) { group in
                for planetWithOwner in planetsWithOwner {
                    if Task.isCancelled { break }

                    let planetKey = "\(planetWithOwner.ownerId)_\(planetWithOwner.planet.planetId)"

                    // 如果详情未加载，跳过
                    guard let detail = detailMap[planetKey] else {
                        continue
                    }

                    // 检查是否有缓存的计算结果
                    if let cachedResults = cachedResultsMap[planetKey] {
                        // 有缓存结果：从 typeCache 获取图标信息并更新UI
                        group.addTask {
                            // 从 typeCache 获取最终产品的图标信息
                            let cachedTypes = await MainActor.run {
                                self.typeCache
                            }

                            let finalProducts = cachedResults.finalProductIds.compactMap { typeId -> FinalProduct? in
                                if let typeInfo = cachedTypes[typeId] {
                                    return FinalProduct(id: typeId, typeId: typeId, icon: typeInfo.icon)
                                }
                                return nil
                            }

                            // 如果 typeCache 中还没有这些类型，重新计算最终产品
                            // （这种情况应该很少见，因为第三步已经批量加载了所有类型）
                            if finalProducts.count != cachedResults.finalProductIds.count {
                                // typeCache 中缺少某些类型，重新计算
                                let recalculatedProducts = await self.calculateFinalProducts(detail: detail)
                                return (
                                    planetKey,
                                    cachedResults.earliestExtractorExpiry,
                                    recalculatedProducts,
                                    ExtractorStatus(
                                        totalCount: cachedResults.extractorStatus.totalCount,
                                        expiredCount: cachedResults.extractorStatus.expiredCount,
                                        expiringSoonCount: cachedResults.extractorStatus.expiringSoonCount
                                    ),
                                    false // 不需要保存到缓存（已有缓存）
                                )
                            }

                            return (
                                planetKey,
                                cachedResults.earliestExtractorExpiry,
                                finalProducts,
                                ExtractorStatus(
                                    totalCount: cachedResults.extractorStatus.totalCount,
                                    expiredCount: cachedResults.extractorStatus.expiredCount,
                                    expiringSoonCount: cachedResults.extractorStatus.expiringSoonCount
                                ),
                                false // 不需要保存到缓存（已有缓存）
                            )
                        }
                    } else {
                        // 没有缓存结果：进行计算
                        group.addTask {
                            // 查找所有采集器的最早过期时间和统计停工状态
                            var earliestExpiry: Date? = nil
                            let currentTime = Date()
                            var totalExtractors = 0
                            var expiredCount = 0
                            var expiringSoonCount = 0
                            let oneHourFromNow = currentTime.addingTimeInterval(3600) // 1小时后

                            for pin in detail.pins {
                                // 检查是否是采集器（通过extractorDetails判断）
                                if pin.extractorDetails != nil {
                                    totalExtractors += 1

                                    if let expiryTimeString = pin.expiryTime,
                                       let expiryTime = dateFormatter.date(from: expiryTimeString)
                                    {
                                        if expiryTime <= currentTime {
                                            // 已停工
                                            expiredCount += 1
                                        } else if expiryTime <= oneHourFromNow {
                                            // 即将在1小时内停工
                                            expiringSoonCount += 1
                                            // 更新最早过期时间
                                            if let existing = earliestExpiry {
                                                if expiryTime < existing {
                                                    earliestExpiry = expiryTime
                                                }
                                            } else {
                                                earliestExpiry = expiryTime
                                            }
                                        } else {
                                            // 更新最早过期时间
                                            if let existing = earliestExpiry {
                                                if expiryTime < existing {
                                                    earliestExpiry = expiryTime
                                                }
                                            } else {
                                                earliestExpiry = expiryTime
                                            }
                                        }
                                    }
                                }
                            }

                            // 计算最终产品：找出只输出，不输入到其他设施的资源
                            // 使用缓存的 schematic
                            let finalProducts = await self.calculateFinalProducts(detail: detail)

                            // 创建采集器状态
                            let extractorStatus = ExtractorStatus(
                                totalCount: totalExtractors,
                                expiredCount: expiredCount,
                                expiringSoonCount: expiringSoonCount
                            )

                            // 保存计算结果到缓存
                            let finalProductIds = finalProducts.map { $0.typeId }
                            let cachedExtractorStatus = CachedExtractorStatus(
                                totalCount: totalExtractors,
                                expiredCount: expiredCount,
                                expiringSoonCount: expiringSoonCount
                            )

                            CharacterPlanetaryAPI.savePlanetaryDetailCalculations(
                                characterId: planetWithOwner.ownerId,
                                planetId: planetWithOwner.planet.planetId,
                                earliestExtractorExpiry: earliestExpiry,
                                finalProductIds: finalProductIds,
                                extractorStatus: cachedExtractorStatus
                            )

                            return (planetKey, earliestExpiry, finalProducts, extractorStatus, true) // 已保存到缓存
                        }
                    }
                }

                // 增量更新UI：每计算完一个行星就立即更新
                for await (planetKey, expiry, products, status, _) in group {
                    if Task.isCancelled { break }

                    // 立即更新该行星的数据
                    await MainActor.run {
                        // 更新采集器过期时间
                        if let expiry = expiry {
                            self.earliestExtractorExpiry[planetKey] = expiry
                        }

                        // 更新最终产品
                        if !products.isEmpty {
                            self.finalProducts[planetKey] = products
                        }

                        // 更新采集器状态
                        if let status = status {
                            self.extractorStatus[planetKey] = status
                        }

                        // 从加载集合中移除该行星
                        self.loadingPlanets.remove(planetKey)
                    }
                }
            }
        }

        await expiryLoadingTask?.value
    }

    /// 批量加载所有需要的 schematic 和 type 信息到缓存
    private func loadSchematicsAndTypesBatch(
        schematicIds: [Int],
        extractorProductTypeIds: [Int],
        allDetails _: [PlanetaryDetail]
    ) async {
        var allTypeIds = Set<Int>()

        // 1. 批量获取所有 schematic 基本信息（内存索引）
        if !schematicIds.isEmpty {
            var schematicData: [Int: (outputTypeId: Int, cycleTime: Int, outputValue: Int, inputTypeIdString: String?, inputValueString: String?)] = [:]

            for schematicId in schematicIds {
                guard let schematic = SDEMemoryStore.planetSchematicsByID[schematicId] else { continue }
                allTypeIds.insert(schematic.outputTypeID)
                schematicData[schematicId] = (
                    schematic.outputTypeID,
                    schematic.cycleTime,
                    schematic.outputValue,
                    schematic.rawInputTypeIDs.isEmpty ? nil : schematic.rawInputTypeIDs,
                    schematic.rawInputValues.isEmpty ? nil : schematic.rawInputValues
                )

                // 解析输入类型ID
                for input in schematic.inputs {
                    allTypeIds.insert(input.typeID)
                }
            }

            // 2. 添加采集器输出的产品类型ID
            allTypeIds.formUnion(extractorProductTypeIds)

            // 3. 计算所有可能的最终产品 typeId
            // 最终产品 = (所有生产的产品 + 所有采集的产品) - 所有消费的产品
            var producingTypeIds = Set<Int>()
            var consumingTypeIds = Set<Int>()

            // 从 schematic 中获取生产和消费的类型
            for (_, data) in schematicData {
                producingTypeIds.insert(data.outputTypeId)

                if let inputTypeIdString = data.inputTypeIdString {
                    let inputTypeIds = inputTypeIdString.components(separatedBy: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    consumingTypeIds.formUnion(inputTypeIds)
                }
            }

            // 从采集器中获取生产的产品类型
            producingTypeIds.formUnion(extractorProductTypeIds)

            // 最终产品 = 生产的产品 - 消费的产品
            let finalProductTypeIds = producingTypeIds.subtracting(consumingTypeIds)
            allTypeIds.formUnion(finalProductTypeIds)

            // 4. 批量查询所有需要的 type 信息（包括图标）
            var tempTypeCache: [Int: (name: String, icon: String)] = [:]
            var schematicTypeCache: [Int: Type] = [:] // 用于构建 Schematic 对象

            if !allTypeIds.isEmpty {
                for typeId in allTypeIds {
                    guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else {
                        continue
                    }
                    tempTypeCache[typeId] = (name: info.name, icon: info.iconFilename)
                    schematicTypeCache[typeId] = Type(id: typeId, name: info.name, volume: info.volume)
                }
            }

            // 5. 构建 Schematic 对象并缓存
            var tempSchematicCache: [Int: Schematic] = [:]
            for (schematicId, data) in schematicData {
                guard let outputType = schematicTypeCache[data.outputTypeId] else {
                    continue
                }

                // 解析输入
                var inputs: [Type: Int64] = [:]
                if let inputTypeIdString = data.inputTypeIdString,
                   let inputValueString = data.inputValueString
                {
                    let inputTypeIds = inputTypeIdString.components(separatedBy: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    let inputValues = inputValueString.components(separatedBy: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
                    }

                    if inputTypeIds.count == inputValues.count {
                        for i in 0 ..< inputTypeIds.count {
                            let typeId = inputTypeIds[i]
                            let quantity = inputValues[i]

                            if let inputType = schematicTypeCache[typeId] {
                                inputs[inputType] = Int64(quantity)
                            }
                        }
                    }
                }

                let schematic = Schematic(
                    id: schematicId,
                    cycleTime: TimeInterval(data.cycleTime),
                    outputType: outputType,
                    outputQuantity: Int64(data.outputValue),
                    inputs: inputs
                )
                tempSchematicCache[schematicId] = schematic
            }

            // 6. 更新缓存（需要在主线程上更新，因为可能被多个任务访问）
            await MainActor.run {
                self.schematicCache.merge(tempSchematicCache) { _, new in new }
                self.typeCache.merge(tempTypeCache) { _, new in new }
            }

            Logger.info("批量加载了 \(tempSchematicCache.count) 个 schematic 和 \(tempTypeCache.count) 个 type")
        } else if !extractorProductTypeIds.isEmpty {
            // 如果没有 schematic，只加载采集器输出的 type
            var tempTypeCache: [Int: (name: String, icon: String)] = [:]
            for typeId in extractorProductTypeIds {
                guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else {
                    continue
                }
                tempTypeCache[typeId] = (name: info.name, icon: info.iconFilename)
            }

            await MainActor.run {
                self.typeCache.merge(tempTypeCache) { _, new in new }
            }

            Logger.info("批量加载了 \(tempTypeCache.count) 个 type")
        }
    }

    /// 计算最终产品：找出只输出，不输入到其他设施的资源
    /// 参考 RIFT：最终产品 = (生产的产品 + 采集的产品) - 消费的产品
    /// 即：所有被生产/采集的资源中，没有被工厂消费的资源就是最终产品
    private func calculateFinalProducts(detail: PlanetaryDetail) async -> [FinalProduct] {
        // 1. 获取所有生产的产品（工厂的输出）
        var producingTypeIds = Set<Int>()
        for pin in detail.pins {
            // 检查是否是工厂
            if let factoryDetails = pin.factoryDetails {
                let schematicId = factoryDetails.schematicId
                if let schematic = await getSchematic(schematicId) {
                    producingTypeIds.insert(schematic.outputType.id)
                }
            } else if let schematicId = pin.schematicId {
                // 备用：直接从 pin 获取 schematicId
                if let schematic = await getSchematic(schematicId) {
                    producingTypeIds.insert(schematic.outputType.id)
                }
            }
        }

        // 2. 获取所有采集的产品（采集器的输出）
        var extractingTypeIds = Set<Int>()
        for pin in detail.pins {
            if let extractorDetails = pin.extractorDetails,
               let productTypeId = extractorDetails.productTypeId
            {
                extractingTypeIds.insert(productTypeId)
            }
        }

        // 3. 合并生产和采集的产品
        let allProducedTypeIds = producingTypeIds.union(extractingTypeIds)

        // 4. 获取所有消费的产品（工厂的输入）
        var consumingTypeIds = Set<Int>()
        for pin in detail.pins {
            if let factoryDetails = pin.factoryDetails {
                let schematicId = factoryDetails.schematicId
                if let schematic = await getSchematic(schematicId) {
                    for inputType in schematic.inputs.keys {
                        consumingTypeIds.insert(inputType.id)
                    }
                }
            } else if let schematicId = pin.schematicId {
                if let schematic = await getSchematic(schematicId) {
                    for inputType in schematic.inputs.keys {
                        consumingTypeIds.insert(inputType.id)
                    }
                }
            }
        }

        // 5. 最终产品 = 生产/采集的产品 - 消费的产品
        let finalProductIds = allProducedTypeIds.subtracting(consumingTypeIds)

        // 从缓存获取这些资源的图标信息（不再查询数据库）
        var finalProducts: [FinalProduct] = []
        if !finalProductIds.isEmpty {
            let cachedTypes = await MainActor.run {
                self.typeCache
            }

            for typeId in finalProductIds {
                if let typeInfo = cachedTypes[typeId] {
                    finalProducts.append(FinalProduct(id: typeId, typeId: typeId, icon: typeInfo.icon))
                }
            }
        }

        // 按typeId排序，确保显示顺序一致
        finalProducts.sort { $0.typeId < $1.typeId }

        return finalProducts
    }

    /// 从缓存获取配方信息，如果缓存中没有则返回 nil
    /// 注意：此方法应该在批量加载 schematic 之后调用
    private func getSchematic(_ schematicId: Int) async -> Schematic? {
        // 从缓存中获取
        return await MainActor.run {
            self.schematicCache[schematicId]
        }
    }
}

/// 进度更新 Actor（用于线程安全地更新进度）
actor ProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

/// 用于存储选中星球信息的结构
struct SelectedPlanet {
    let characterId: Int
    let planetId: Int
    let planetName: String
}

struct CharacterPlanetaryView: View {
    let characterId: Int?
    @StateObject private var viewModel: CharacterPlanetaryViewModel
    @State private var selectedPlanet: SelectedPlanet?
    @State private var showSettingsSheet = false
    /// 多人物模式下已折叠的角色 ID；默认空 = 全部展开
    @State private var collapsedCharacterIdsInMultiMode: Set<Int> = []

    init(characterId: Int?) {
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: CharacterPlanetaryViewModel(characterId: characterId)
        )
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                Section(header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))) {
                    if let progress = viewModel.loadingProgress, progress.total > 1 {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Planetary_Loading_Progress", comment: "已加载人物 %d/%d"), progress.current, progress.total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            } else {
                if characterId != nil || viewModel.multiCharacterMode {
                    if viewModel.planets.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                        ) {
                            NoDataSection()
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    } else {
                        // 多人物聚合模式：按人物分组显示
                        if viewModel.multiCharacterMode, viewModel.selectedCharacterIds.count > 1 {
                            let groupedPlanets = viewModel.groupedPlanetsByCharacter
                            if groupedPlanets.isEmpty {
                                Section(
                                    header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                                ) {
                                    NoDataSection()
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            } else {
                                if !viewModel.aggregatedPlanetTypeSummariesForMultiSelect.isEmpty {
                                    Section(
                                        header:
                                        Text(NSLocalizedString("Planetary_MultiSelect_Planet_Type_Summary", comment: ""))
                                    ) {
                                        ForEach(viewModel.aggregatedPlanetTypeSummariesForMultiSelect) { summary in
                                            HStack(spacing: 12) {
                                                Image(uiImage: IconManager.shared.loadUIImage(for: summary.iconFileName))
                                                    .resizable()
                                                    .frame(width: 32, height: 32)
                                                    .cornerRadius(6)
                                                Text(summary.displayName)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                Text("\(summary.count)")
                                                    .font(.headline)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                }
                                ForEach(groupedPlanets, id: \.characterId) { group in
                                    let isCollapsed = collapsedCharacterIdsInMultiMode.contains(
                                        group.characterId
                                    )
                                    if groupedPlanets.count > 1 {
                                        Section(
                                            header: HStack(spacing: 16) {
                                                CharacterPortraitView(characterId: group.characterId)
                                                    .frame(width: 24, height: 24)
                                                Text(group.characterName)
                                                Spacer()
                                                deployedColoniesCountCaption(
                                                    deployed: group.planets.count,
                                                    max: group.maxPlanets,
                                                    needsAttention: viewModel.characterHeaderShowsExtractorAttention(
                                                        planets: group.planets,
                                                        characterId: group.characterId
                                                    )
                                                )
                                                Image(
                                                    systemName: isCollapsed ? "chevron.right" : "chevron.down"
                                                )
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(.secondary)
                                                .accessibilityHidden(true)
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                toggleMultiCharacterSectionExpansion(characterId: group
                                                    .characterId)
                                            }
                                            .accessibilityAddTraits(.isButton)
                                            .accessibilityLabel(
                                                accessibilityLabelForMultiCharacterHeader(
                                                    characterName: group.characterName,
                                                    isCollapsed: isCollapsed
                                                )
                                            )
                                        ) {
                                            if !isCollapsed {
                                                ForEach(group.planets, id: \.planetId) { planet in
                                                    PlanetRow(
                                                        planet: planet,
                                                        viewModel: viewModel,
                                                        characterId: group.characterId,
                                                        onPlanetSelected: { planetId, planetName in
                                                            selectedPlanet = SelectedPlanet(
                                                                characterId: group.characterId,
                                                                planetId: planetId,
                                                                planetName: planetName
                                                            )
                                                        }
                                                    )
                                                }
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                    } else {
                                        Section(
                                            header: HStack(spacing: 16) {
                                                CharacterPortraitView(characterId: group.characterId)
                                                    .frame(width: 24, height: 24)
                                                Text(group.characterName)
                                                Spacer()
                                                deployedColoniesCountCaption(
                                                    deployed: group.planets.count,
                                                    max: group.maxPlanets,
                                                    needsAttention: viewModel.characterHeaderShowsExtractorAttention(
                                                        planets: group.planets,
                                                        characterId: group.characterId
                                                    )
                                                )
                                            }
                                        ) {
                                            ForEach(group.planets, id: \.planetId) { planet in
                                                PlanetRow(
                                                    planet: planet,
                                                    viewModel: viewModel,
                                                    characterId: group.characterId,
                                                    onPlanetSelected: { planetId, planetName in
                                                        selectedPlanet = SelectedPlanet(
                                                            characterId: group.characterId,
                                                            planetId: planetId,
                                                            planetName: planetName
                                                        )
                                                    }
                                                )
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                    }
                                }
                            }
                        } else {
                            // 单人物模式：保持原有显示方式
                            let currentCharacterId = viewModel.multiCharacterMode && !viewModel.selectedCharacterIds.isEmpty
                                ? viewModel.selectedCharacterIds.first!
                                : characterId
                            let maxPlanets = currentCharacterId != nil ? (viewModel.maxPlanetsByCharacter[currentCharacterId!] ?? 1) : 1
                            let headerAttentionCharacterId = currentCharacterId ?? characterId
                            let headerNeedsAttention =
                                headerAttentionCharacterId.map {
                                    viewModel.characterHeaderShowsExtractorAttention(
                                        planets: viewModel.planets, characterId: $0
                                    )
                                } ?? false

                            Section(
                                header: HStack {
                                    Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                                    Spacer()
                                    deployedColoniesCountCaption(
                                        deployed: viewModel.planets.count,
                                        max: maxPlanets,
                                        needsAttention: headerNeedsAttention
                                    )
                                }
                            ) {
                                ForEach(viewModel.planets, id: \.planetId) { planet in
                                    PlanetRow(
                                        planet: planet,
                                        viewModel: viewModel,
                                        characterId: viewModel.getPlanetOwner(for: planet.planetId) ?? characterId ?? 0,
                                        onPlanetSelected: { planetId, planetName in
                                            let planetOwnerId = viewModel.getPlanetOwner(for: planetId) ?? characterId ?? 0
                                            selectedPlanet = SelectedPlanet(
                                                characterId: planetOwnerId,
                                                planetId: planetId,
                                                planetName: planetName
                                            )
                                        }
                                    )
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Title", comment: ""))
        .refreshable {
            // 清理星球详情缓存，防止数据不同步
            let characterIdsToClear: [Int]
            if viewModel.multiCharacterMode, viewModel.selectedCharacterIds.count > 1 {
                characterIdsToClear = Array(viewModel.selectedCharacterIds)
            } else if let characterId = characterId {
                characterIdsToClear = [characterId]
            } else {
                characterIdsToClear = []
            }

            for charId in characterIdsToClear {
                CharacterPlanetaryAPI.clearPlanetDetailCache(characterId: charId)
            }
            await viewModel.loadPlanets(forceRefresh: true)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSettingsSheet = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            PlanetarySettingsSheet(viewModel: viewModel)
        }
        .sheet(item: $selectedPlanet) { planet in
            NavigationStack {
                PlanetDetailView(
                    characterId: planet.characterId,
                    planetId: planet.planetId,
                    planetName: planet.planetName
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            selectedPlanet = nil
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func deployedColoniesCountCaption(deployed: Int, max: Int, needsAttention: Bool) -> some View {
        HStack(spacing: 0) {
            Text("\(deployed)")
                .foregroundColor(needsAttention ? .red : .secondary)
            Text("/\(max)")
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }

    private func toggleMultiCharacterSectionExpansion(characterId: Int) {
        withAnimation {
            var next = collapsedCharacterIdsInMultiMode
            if next.contains(characterId) {
                next.remove(characterId)
            } else {
                next.insert(characterId)
            }
            collapsedCharacterIdsInMultiMode = next
        }
    }

    private func accessibilityLabelForMultiCharacterHeader(characterName: String, isCollapsed: Bool)
        -> String
    {
        let action = isCollapsed
            ? NSLocalizedString("Planetary_Expand_Character_Colonies", comment: "")
            : NSLocalizedString("Planetary_Collapse_Character_Colonies", comment: "")
        return "\(characterName). \(action)"
    }
}

/// 行星设置界面
struct PlanetarySettingsSheet: View {
    @ObservedObject var viewModel: CharacterPlanetaryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $viewModel.multiCharacterMode) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Planetary_Settings_Multi_Character", comment: "多人物聚合"
                                )
                            )
                            Text(
                                NSLocalizedString(
                                    "Planetary_Settings_Multi_Character_Description",
                                    comment: "聚合显示多个角色的行星数据"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    if viewModel.multiCharacterMode {
                        Toggle(isOn: $viewModel.showPlanetTypeSummaryInMultiSelect) {
                            Text(
                                NSLocalizedString(
                                    "Planetary_Settings_Show_Type_Summary", comment: "显示汇总"
                                )
                            )
                        }
                    }
                }

                // 只有在多人物模式开启时才显示角色选择
                if viewModel.multiCharacterMode {
                    MultiCharacterSelectionSection(
                        availableCharacters: viewModel.availableCharacters,
                        selectedCharacterIds: $viewModel.selectedCharacterIds
                    )
                }
            }
            .navigationTitle(NSLocalizedString("Planetary_Settings_Title", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 让 SelectedPlanet 遵循 Identifiable 协议
extension SelectedPlanet: Identifiable {
    var id: Int {
        planetId
    }
}

/// 最终产品图标网格视图
struct FinalProductsGridView: View {
    let products: [FinalProduct]

    var body: some View {
        let count = products.count
        let iconSize: CGFloat = count == 1 ? 28 : (count == 2 ? 20 : 16)
        let spacing: CGFloat = count == 1 ? 0 : 4

        VStack(spacing: spacing) {
            if count == 1 {
                // 1个：显示1个
                ProductIcon(product: products[0], size: iconSize)
            } else if count == 2 {
                // 2个：上下显示
                ProductIcon(product: products[0], size: iconSize)
                ProductIcon(product: products[1], size: iconSize)
            } else if count == 3 {
                // 3个：第一行2个，第二行1个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[2], size: iconSize)
                    Spacer()
                }
            } else if count == 4 {
                // 4个：第一行2个，第二行2个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[2], size: iconSize)
                    ProductIcon(product: products[3], size: iconSize)
                }
            } else if count == 5 {
                // 5个：第一行3个，第二行2个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                    ProductIcon(product: products[2], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[3], size: iconSize)
                    ProductIcon(product: products[4], size: iconSize)
                }
            } else {
                // 6个或更多：第一行3个，第二行3个（只显示前6个）
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                    ProductIcon(product: products[2], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[3], size: iconSize)
                    ProductIcon(product: products[4], size: iconSize)
                    if products.count > 5 {
                        ProductIcon(product: products[5], size: iconSize)
                    }
                }
            }
        }
    }
}

/// 产品图标视图
struct ProductIcon: View {
    let product: FinalProduct
    let size: CGFloat

    var body: some View {
        Image(uiImage: IconManager.shared.loadUIImage(for: product.icon))
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(4)
    }
}

/// 行星行组件
struct PlanetRow: View {
    let planet: CharacterPlanetaryInfo
    let viewModel: CharacterPlanetaryViewModel
    let characterId: Int
    let onPlanetSelected: (Int, String) -> Void

    var body: some View {
        Button {
            let planetName = viewModel.getPlanetName(for: planet.planetId)
            onPlanetSelected(planet.planetId, planetName)
        } label: {
            HStack {
                if let typeInfo = viewModel.getPlanetTypeInfo(for: planet.planetType) {
                    Image(uiImage: IconManager.shared.loadUIImage(for: typeInfo.icon))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        // 显示星系安等（如果有）
                        if let security = viewModel.getSystemSecurity(for: planet.solarSystemId) {
                            Text(formatSystemSecurity(security))
                                .foregroundColor(getSecurityColor(security))
                                .font(.system(.headline, design: .monospaced))
                        }
                        Text(viewModel.getPlanetName(for: planet.planetId))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .contextMenu {
                        let planetName = viewModel.getPlanetName(for: planet.planetId)
                        Button {
                            UIPasteboard.general.string = planetName
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Name", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }

                    HStack(spacing: 6) {
                        if let typeInfo = viewModel.getPlanetTypeInfo(for: planet.planetType) {
                            Text(typeInfo.name)
                        } else {
                            Text(NSLocalizedString("Main_Planetary_Unknown_Type", comment: ""))
                        }
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString("Planet_Colony_Upgrade_Level", comment: ""),
                                planet.upgradeLevel
                            )
                        )
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)

                    // 显示采集器停工状态
                    if let status = viewModel.getExtractorStatus(for: planet.planetId, characterId: characterId), status.totalCount > 0 {
                        if status.expiredCount > 0 {
                            // 显示已停工的采集器数量
                            Text(String.localizedStringWithFormat(NSLocalizedString("Planet_Extractor_Expired_Count", comment: "%d/%d个采集器已停工"), status.expiredCount, status.totalCount))
                                .font(.caption2)
                                .foregroundColor(.red)
                        } else if status.expiringSoonCount > 0 {
                            // 显示即将停工的采集器数量
                            Text(String.localizedStringWithFormat(NSLocalizedString("Planet_Extractor_Expiring_Soon_Count", comment: "%d/%d个采集器即将停工"), status.expiringSoonCount, status.totalCount))
                                .font(.caption2)
                                .foregroundColor(.red)
                        } else if let expiryDate = viewModel.getEarliestExtractorExpiry(for: planet.planetId, characterId: characterId) {
                            // 显示采集器最早过期时间
                            let timeRemaining = expiryDate.timeIntervalSince(Date())
                            if timeRemaining > 0 {
                                Text("\(NSLocalizedString("Planet_Detail_Extractor_Expiry_Time", comment: "")): \(FormatUtil.formatRemainingDuration(timeRemaining))")
                                    .font(.caption2)
                                    .foregroundColor(
                                        viewModel.planetNeedsExtractorAttention(
                                            planetId: planet.planetId,
                                            characterId: characterId
                                        ) ? .red : .green
                                    )
                            } else {
                                Text(NSLocalizedString("Planet_Detail_Extractor_Expired", comment: ""))
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    } else if let expiryDate = viewModel.getEarliestExtractorExpiry(for: planet.planetId, characterId: characterId) {
                        // 兼容旧逻辑：如果没有状态信息，显示过期时间
                        let timeRemaining = expiryDate.timeIntervalSince(Date())
                        if timeRemaining > 0 {
                            Text("\(NSLocalizedString("Planet_Detail_Extractor_Expiry_Time", comment: "")): \(FormatUtil.formatRemainingDuration(timeRemaining))")
                                .font(.caption2)
                                .foregroundColor(
                                    viewModel.planetNeedsExtractorAttention(
                                        planetId: planet.planetId,
                                        characterId: characterId
                                    ) ? .red : .green
                                )
                        } else {
                            Text(NSLocalizedString("Planet_Detail_Extractor_Expired", comment: ""))
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }

                Spacer()

                // 显示加载指示器或最终产品图标
                if viewModel.isLoadingPlanetDetail(for: planet.planetId, characterId: characterId) {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    let products = viewModel.getFinalProducts(for: planet.planetId, characterId: characterId)
                    if !products.isEmpty {
                        FinalProductsGridView(products: products)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
