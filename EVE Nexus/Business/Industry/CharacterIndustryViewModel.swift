import SwiftUI

@MainActor
class CharacterIndustryViewModel: ObservableObject {
    /// 配置常量
    private let soonCompleteThreshold: TimeInterval = 8 * 3600 // 即将完成阈值：8小时

    @Published var jobs: [IndustryJob] = []
    @Published var groupedJobs: [String: [IndustryJob]] = [:] // 按日期分组的工作项目
    var jobsWithOwner: [IndustryJobWithOwner] = [] // 包含所有者信息的工业项目
    @Published var isLoading = true
    @Published var isFiltering = false // 新增：过滤刷新状态
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var loadingProgress: (current: Int, total: Int)? = nil // 工业项目加载进度 (已加载/总数)
    @Published var skillLoadingProgress: (current: Int, total: Int)? = nil // 技能加载进度 (已加载/总数)
    @Published var itemNames: [Int: String] = [:]
    @Published var locationInfoCache: [Int64: LocationInfoDetail] = [:]
    @Published var itemIcons: [Int: String] = [:]

    /// 多人物聚合相关
    @Published var multiCharacterMode = false {
        didSet {
            UserDefaults.standard.set(multiCharacterMode, forKey: "multiCharacterMode_industry")
            if initialLoadDone {
                Task {
                    // 重新计算槽位和操作范围
                    await loadMaxSlots(forceRefresh: true)
                    await loadOperationRanges(forceRefresh: true)
                    // 重新加载工业项目数据
                    await loadJobs(forceRefresh: true, isFiltering: true)
                }
            }
        }
    }

    @Published var selectedCharacterIds: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_industry"
            )
            if initialLoadDone, multiCharacterMode {
                Task {
                    // 重新计算槽位和操作范围
                    await loadMaxSlots(forceRefresh: true)
                    await loadOperationRanges(forceRefresh: true)
                    // 重新加载工业项目数据
                    await loadJobs(forceRefresh: true, isFiltering: true)
                }
            }
        }
    }

    @Published var availableCharacters: [(id: Int, name: String)] = []

    // 发起人信息缓存
    @Published var installerNames: [Int: String] = [:]
    @Published var installerImages: [Int: UIImage] = [:]

    /// 过滤设置
    @Published var hideCompletedAndCancelled = false {
        didSet {
            UserDefaults.standard.set(
                hideCompletedAndCancelled, forKey: "hideCompletedAndCancelled_global"
            )
            // 当隐藏完成项目设置发生变化时，强制刷新数据
            if initialLoadDone {
                Task {
                    await loadJobs(forceRefresh: true, isFiltering: true)
                }
            }
        }
    }

    @Published var selectedActivityTypes: Set<Int> = [1, 3, 4, 5, 8, 9] // 默认全选
    @Published var selectedInstallers: Set<Int> = [] // 发起人筛选（仅在聚合模式下使用）
    @Published var selectedSolarSystems: Set<String> = []

    /// 可用的活动类型
    let availableActivityTypes = [1, 3, 4, 5, 8, 9] // 制造、ME研究、TE研究、复制、发明、反应

    /// 可用的发起人列表（仅在聚合模式下使用）
    @Published var availableInstallers: [Int] = []

    /// 可用的星系列表
    @Published var availableSolarSystems: [String] = []

    // 添加工业槽位统计相关属性
    @Published var manufacturingSlots: (used: Int, total: Int) = (0, 0)
    @Published var researchSlots: (used: Int, total: Int) = (0, 0)
    @Published var reactionSlots: (used: Int, total: Int) = (0, 0)

    // 添加操作范围相关属性
    @Published var manufacturingRange: Int = 0 // 加工类项目操作范围
    @Published var researchRange: Int = 0 // 科研类项目操作范围
    @Published var reactionRange: Int = 0 // 反应类项目操作范围

    /// 缓存最大槽位数据，在初始化时计算一次
    private var maxSlots: (manufacturing: Int, research: Int, reaction: Int) = (1, 1, 1)

    /// 缓存每个角色的详细信息
    @Published var characterSlotDetails: [CharacterSlotDetail] = []

    /// 生产清单数据
    struct ProductionItem {
        let typeId: Int
        let typeName: String
        let typeIcon: String
        var totalQuantity: Int
    }

    @Published var productionList: [ProductionItem] = []

    private let characterId: Int
    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var initialLoadDone = false
    private var cachedJobs: [IndustryJob]? // 缓存工业项目数据

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager

        // 从 UserDefaults 读取全局设置
        hideCompletedAndCancelled = UserDefaults.standard.bool(
            forKey: "hideCompletedAndCancelled_global"
        )

        // 从 UserDefaults 读取多人物聚合设置
        multiCharacterMode = UserDefaults.standard.bool(forKey: "multiCharacterMode_industry")
        let savedCharacterIds =
            UserDefaults.standard.array(forKey: "selectedCharacterIds_industry") as? [Int] ?? []
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
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_industry"
            )
        }

        // 如果没有选中的角色，默认选择当前角色
        if selectedCharacterIds.isEmpty {
            selectedCharacterIds.insert(characterId)
        }

        // 在初始化时立即加载技能数据和工业任务数据
        Task {
            // 先加载技能数据计算最大槽位和操作范围
            await loadMaxSlots()
            await loadOperationRanges()
            // 然后加载工业任务数据
            await loadJobs()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    /// 刷新所有数据（包括技能数据）
    func refreshAllIndustryData() async {
        // 重新加载技能数据（槽位和操作范围）- 强制刷新
        await loadMaxSlots(forceRefresh: true)
        await loadOperationRanges(forceRefresh: true)
        // 重新加载工业项目数据
        await loadJobs(forceRefresh: true)
    }

    /// 将工作项目按状态分组
    private func groupJobsByStatus() {
        var grouped = [String: [IndustryJob]]()
        let currentTime = Date()

        for job in jobs {
            let groupKey: String

            if job.status == "ready" || (job.status == "active" && job.end_date <= currentTime) {
                // 已完成但未交付的项目
                groupKey = "ready"
            } else if job.status == "active" && job.end_date > currentTime {
                // 检查是否即将完成（剩余时间小于阈值）
                let remainingTime = job.end_date.timeIntervalSince(currentTime)

                if remainingTime <= soonCompleteThreshold {
                    // 即将完成的项目
                    groupKey = "soon"
                } else {
                    // 正在进行中的项目
                    groupKey = "active"
                }
            } else if job.status == "delivered" || job.status == "cancelled"
                || job.status == "revoked" || job.status == "failed"
            {
                // 已交付或已取消的项目
                groupKey = "completed"
            } else {
                // 其他状态归为已完成
                groupKey = "completed"
            }

            if grouped[groupKey] == nil {
                grouped[groupKey] = []
            }
            grouped[groupKey]?.append(job)
        }

        // 对每个组内的工作项目排序
        for (key, value) in grouped {
            switch key {
            case "ready":
                // 已完成未交付：按job_id排序
                grouped[key] = value.sorted { $0.job_id > $1.job_id }
            case "soon":
                // 即将完成：按剩余时间从短到长排序
                grouped[key] = value.sorted { $0.end_date < $1.end_date }
            case "active":
                // 正在进行中：按剩余时间从短到长排序
                grouped[key] = value.sorted { $0.end_date < $1.end_date }
            case "completed":
                // 已交付/已取消：按完成时间从近到远排序
                grouped[key] = value.sorted {
                    let date1 = $0.completed_date ?? $0.end_date
                    let date2 = $1.completed_date ?? $1.end_date
                    return date1 > date2
                }
            default:
                break
            }
        }

        groupedJobs = grouped
    }

    func loadJobs(forceRefresh: Bool = false, isFiltering: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            // 根据是否是过滤刷新来设置不同的加载状态
            if isFiltering {
                self.isFiltering = true
            } else {
                self.isLoading = true
            }
            errorMessage = nil
            showError = false

            do {
                // 加载数据
                let jobs = try await fetchJobs(forceRefresh: forceRefresh)

                if Task.isCancelled {
                    return
                }

                // 更新数据
                self.jobs = jobs
                await loadItemNames()

                if Task.isCancelled {
                    return
                }

                await loadLocationNames()

                if Task.isCancelled {
                    return
                }

                groupJobsByStatus()

                // 更新过滤选项
                updateFilterOptions()

                // 计算工业槽位统计
                calculateIndustrySlotStats()

                // 更新characterSlotDetails中的已用槽位数
                updateCharacterSlotUsedCounts()

                // 计算生产清单
                calculateProductionList()

                // 根据是否是过滤刷新来清除相应的加载状态
                if isFiltering {
                    self.isFiltering = false
                } else {
                    self.isLoading = false
                }
                self.initialLoadDone = true

                // 如果是多人物模式，在后台加载发起人信息（不阻塞列表显示）
                if multiCharacterMode {
                    Task {
                        await loadInstallerInfo()
                    }
                }

            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.isFiltering = false
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    /// 封装获取数据逻辑，处理缓存
    private func fetchJobs(forceRefresh: Bool = false) async throws -> [IndustryJob] {
        // 如果不是强制刷新且有缓存，直接返回缓存
        if !forceRefresh, let cached = cachedJobs {
            Logger.info("使用内存缓存的工业项目数据")
            return cached
        }

        var allJobs: [IndustryJob] = []
        var allJobsWithOwner: [IndustryJobWithOwner] = []

        if multiCharacterMode, selectedCharacterIds.count > 1 {
            // 多人物模式：并发获取所有选中人物的工业项目
            let totalCharacters = selectedCharacterIds.count

            // 初始化加载进度
            await MainActor.run {
                self.loadingProgress = (current: 0, total: totalCharacters)
            }

            // 使用 Actor 来线程安全地更新进度
            let progressActor = IndustryProgressActor(total: totalCharacters) { current, total in
                Task { @MainActor in
                    self.loadingProgress = (current: current, total: total)
                }
            }

            await withTaskGroup(of: (Int, Result<[IndustryJob], Error>).self) { group in
                for characterId in selectedCharacterIds {
                    group.addTask { [weak self] in
                        guard let self = self else { return (characterId, .failure(NSError(domain: "CharacterIndustryViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "ViewModel已释放"]))) }
                        do {
                            let jobs = try await CharacterIndustryAPI.shared.fetchIndustryJobs(
                                characterId: characterId,
                                forceRefresh: forceRefresh,
                                includeCompleted: !self.hideCompletedAndCancelled
                            )
                            return (characterId, .success(jobs))
                        } catch {
                            Logger.error("获取角色\(characterId)工业项目失败: \(error)")
                            return (characterId, .failure(error))
                        }
                    }
                }

                // 收集结果
                for await (characterId, result) in group {
                    switch result {
                    case let .success(jobs):
                        allJobs.append(contentsOf: jobs)
                        // 为每个项目添加所有者信息
                        for job in jobs {
                            allJobsWithOwner.append(
                                IndustryJobWithOwner(
                                    job: job, ownerId: characterId, isFromCorporation: false
                                )
                            )
                        }
                    case .failure:
                        // 失败时继续处理，不中断
                        break
                    }

                    // 更新进度
                    await progressActor.increment()
                }
            }

            // 清除加载进度
            await MainActor.run {
                self.loadingProgress = nil
            }
        } else {
            // 单人物模式：只获取当前角色或选中的唯一角色
            let targetCharacterId =
                multiCharacterMode && !selectedCharacterIds.isEmpty
                    ? selectedCharacterIds.first!
                    : characterId

            allJobs = try await CharacterIndustryAPI.shared.fetchIndustryJobs(
                characterId: targetCharacterId,
                forceRefresh: forceRefresh,
                includeCompleted: !hideCompletedAndCancelled
            )

            // 单人模式也创建所有者信息
            for job in allJobs {
                allJobsWithOwner.append(
                    IndustryJobWithOwner(
                        job: job, ownerId: targetCharacterId, isFromCorporation: false
                    )
                )
            }
        }

        let characterIdsForCorpMerge: Set<Int> = {
            if multiCharacterMode, !selectedCharacterIds.isEmpty {
                return selectedCharacterIds
            }
            return [characterId]
        }()

        await appendCorpIndustryJobs(
            forCharacterIds: characterIdsForCorpMerge,
            allJobs: &allJobs,
            allJobsWithOwner: &allJobsWithOwner,
            forceRefresh: forceRefresh
        )

        // 更新缓存
        cachedJobs = allJobs
        jobsWithOwner = allJobsWithOwner

        return allJobs
    }

    /// 在个人工业列表之后，合并这些角色所在军团（军团 ID 去重）的工业项目。
    private func appendCorpIndustryJobs(
        forCharacterIds characterIds: Set<Int>,
        allJobs: inout [IndustryJob],
        allJobsWithOwner: inout [IndustryJobWithOwner],
        forceRefresh: Bool
    ) async {
        let includeCompleted = !hideCompletedAndCancelled

        var corpIdToCharacterIds: [Int: [Int]] = [:]
        for cid in characterIds {
            do {
                if let corpId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                    characterId: cid
                ) {
                    corpIdToCharacterIds[corpId, default: []].append(cid)
                }
            } catch {
                continue
            }
        }

        let uniqueCorpIds = Array(corpIdToCharacterIds.keys)
        guard !uniqueCorpIds.isEmpty else { return }

        var corpJobBatches: [[CorpIndustryAPI.CorpIndustryJob]] = []

        await withTaskGroup(of: Result<[CorpIndustryAPI.CorpIndustryJob], Error>.self) { group in
            // 军团权限按角色 token 各自独立，同军团下每个成员角色都各自请求
            // （军团级成功缓存命中时各调用直接返回缓存，不发网络请求；403 由 API 层负缓存节流）
            for corpId in uniqueCorpIds {
                for memberId in corpIdToCharacterIds[corpId]?.sorted() ?? [] {
                    group.addTask {
                        do {
                            let jobs = try await CorpIndustryAPI.shared.fetchCorpIndustryJobsForCorporation(
                                corporationId: corpId,
                                characterId: memberId,
                                forceRefresh: forceRefresh,
                                includeCompleted: includeCompleted,
                                progressCallback: nil
                            )
                            return .success(jobs)
                        } catch {
                            Logger.error(
                                "获取军团 \(corpId) 工业项目失败（角色 \(memberId)，跳过，可能无权限）: \(error.localizedDescription)"
                            )
                            return .failure(error)
                        }
                    }
                }
            }

            for await result in group {
                if case let .success(jobs) = result {
                    corpJobBatches.append(jobs)
                }
            }
        }

        var seenJobIds = Set(allJobs.map(\.job_id))
        let allowedInstallers = characterIds

        for batch in corpJobBatches {
            for cj in batch {
                guard allowedInstallers.contains(cj.installer_id) else { continue }
                let ij = Self.industryJob(fromCorpJob: cj)
                if seenJobIds.insert(ij.job_id).inserted {
                    allJobs.append(ij)
                    allJobsWithOwner.append(
                        IndustryJobWithOwner(
                            job: ij, ownerId: cj.installer_id, isFromCorporation: true
                        )
                    )
                }
            }
        }
    }

    private static func industryJob(fromCorpJob corp: CorpIndustryAPI.CorpIndustryJob) -> IndustryJob {
        IndustryJob(
            activity_id: corp.activity_id,
            blueprint_id: corp.blueprint_id,
            blueprint_location_id: corp.blueprint_location_id,
            blueprint_type_id: corp.blueprint_type_id,
            completed_character_id: corp.completed_character_id,
            completed_date: corp.completed_date,
            cost: corp.cost,
            duration: corp.duration,
            end_date: corp.end_date,
            facility_id: corp.facility_id,
            installer_id: corp.installer_id,
            job_id: corp.job_id,
            licensed_runs: corp.licensed_runs,
            output_location_id: corp.output_location_id,
            pause_date: corp.pause_date,
            probability: corp.probability,
            product_type_id: corp.product_type_id,
            runs: corp.runs,
            start_date: corp.start_date,
            station_id: corp.location_id,
            status: corp.status,
            successful_runs: corp.successful_runs
        )
    }

    func isJobFromCorporation(_ job: IndustryJob) -> Bool {
        jobsWithOwner.first(where: { $0.job.job_id == job.job_id })?.isFromCorporation ?? false
    }

    private func loadItemNames() async {
        var typeIds = Set<Int>()
        for job in jobs {
            typeIds.insert(job.blueprint_type_id)
        }

        // 如果没有物品ID，直接返回
        if typeIds.isEmpty {
            return
        }

        Logger.debug("开始批量加载\(typeIds.count)个蓝图信息")

        // 使用IN查询一次性获取所有物品信息
        let placeholders = Array(repeating: "?", count: typeIds.count).joined(separator: ",")
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(placeholders))
        """

        // 将Set转换为数组作为参数
        let parameters = typeIds.map { $0 as Any }

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String
                {
                    itemNames[typeId] = name
                    if let iconFileName = row["icon_filename"] as? String {
                        itemIcons[typeId] = iconFileName
                    }
                }
            }
            Logger.success("成功加载了\(rows.count)个蓝图信息")
        } else {
            Logger.error("批量加载蓝图信息失败")
        }
    }

    private func loadLocationNames() async {
        var locationIds = Set<Int64>()
        for job in jobs {
            locationIds.insert(job.station_id)
            locationIds.insert(job.facility_id)
        }

        let locationLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(characterId)
        )
        locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)
    }

    /// 加载发起人信息
    private func loadInstallerInfo() async {
        // 从jobsWithOwner中收集所有唯一的角色ID
        let installerIds = Set(jobsWithOwner.map { $0.ownerId })

        // 如果没有发起人ID，直接返回
        if installerIds.isEmpty {
            return
        }

        Logger.debug("开始加载\(installerIds.count)个发起人信息")

        // 并发获取发起人信息（网络请求在后台线程执行，只有更新UI时才切换到主线程）
        await withTaskGroup(of: Void.self) { group in
            for installerId in installerIds {
                group.addTask {
                    do {
                        // 网络请求在后台线程执行
                        let info = try await CharacterAPI.shared.fetchCharacterPublicInfo(
                            characterId: installerId, forceRefresh: false
                        )
                        let image = try await CharacterAPI.shared.fetchCharacterPortrait(
                            characterId: installerId, size: 64, forceRefresh: false,
                            catchImage: true
                        )

                        // 更新UI相关的@Published属性时切换到主线程
                        await MainActor.run {
                            self.installerNames[installerId] = info.name
                            self.installerImages[installerId] = image
                        }

                        Logger.success("成功加载发起人信息 - ID: \(installerId), 名称: \(info.name)")
                    } catch {
                        Logger.error("加载发起人信息失败 - ID: \(installerId), 错误: \(error)")
                        // 设置默认值，避免重复尝试
                        await MainActor.run {
                            self.installerNames[installerId] = "Unknown"
                        }
                    }
                }
            }
        }

        Logger.debug("完成加载发起人信息")
    }

    /// 过滤后的分组数据
    var filteredGroupedJobs: [String: [IndustryJob]] {
        var filtered = [String: [IndustryJob]]()

        for (groupKey, jobs) in groupedJobs {
            // 如果隐藏已交付和已取消，跳过completed组
            if hideCompletedAndCancelled, groupKey == "completed" {
                continue
            }

            let filteredJobs = jobs.filter { job in
                // 按活动类型过滤
                let activityMatches = selectedActivityTypes.contains(job.activity_id)

                // 按发起人过滤（仅在聚合模式下且选择了多个人物时才应用）
                var installerMatches = true
                if multiCharacterMode, selectedCharacterIds.count > 1,
                   !selectedInstallers.isEmpty
                {
                    // 从jobsWithOwner中找到该项目的所有者
                    if let jobWithOwner = jobsWithOwner.first(where: { $0.job.job_id == job.job_id }) {
                        installerMatches = selectedInstallers.contains(jobWithOwner.ownerId)
                    } else {
                        installerMatches = false
                    }
                }

                // 按星系过滤
                var solarSystemMatches = true
                if !selectedSolarSystems.isEmpty {
                    if let locationInfo = locationInfoCache[job.station_id] {
                        solarSystemMatches = selectedSolarSystems.contains(
                            locationInfo.solarSystemName
                        )
                    } else {
                        solarSystemMatches = false
                    }
                }

                return activityMatches && installerMatches && solarSystemMatches
            }

            if !filteredJobs.isEmpty {
                filtered[groupKey] = filteredJobs
            }
        }

        return filtered
    }

    /// 更新过滤选项
    private func updateFilterOptions() {
        // 更新可用的发起人列表（仅在聚合模式下且选择了多个人物时）
        if multiCharacterMode, selectedCharacterIds.count > 1 {
            let installerIds = Array(Set(jobsWithOwner.map { $0.ownerId }))
            let newAvailableInstallers = installerIds.sorted { id1, id2 in
                let name1 = installerNames[id1] ?? "Unknown"
                let name2 = installerNames[id2] ?? "Unknown"
                return name1.localizedCompare(name2) == .orderedAscending
            }

            // 检查发起人列表是否发生了变化
            let installersChanged = Set(newAvailableInstallers) != Set(availableInstallers)
            availableInstallers = newAvailableInstallers

            // 如果发起人列表发生了变化，自动选中所有发起人
            if installersChanged, !availableInstallers.isEmpty {
                selectedInstallers = Set(availableInstallers)
            } else if selectedInstallers.isEmpty, !availableInstallers.isEmpty {
                // 自动初始化过滤器选择（只在首次加载时）
                selectedInstallers = Set(availableInstallers)
            }
        } else {
            // 非聚合模式或只选择了一个人物，清空发起人筛选
            availableInstallers = []
            selectedInstallers = []
        }

        // 更新可用的星系列表，按星系名称排序
        var solarSystems = Set<String>()
        for job in jobs {
            if let locationInfo = locationInfoCache[job.station_id] {
                solarSystems.insert(locationInfo.solarSystemName)
            }
        }
        let newAvailableSolarSystems = Array(solarSystems).sorted {
            $0.localizedCompare($1) == .orderedAscending
        }

        // 检查星系列表是否发生了变化
        let solarSystemsChanged = Set(newAvailableSolarSystems) != Set(availableSolarSystems)
        availableSolarSystems = newAvailableSolarSystems

        // 如果星系列表发生了变化（比如切换了hideCompletedAndCancelled设置），自动选中所有星系
        if solarSystemsChanged, !availableSolarSystems.isEmpty {
            selectedSolarSystems = Set(availableSolarSystems)
        } else if selectedSolarSystems.isEmpty, !availableSolarSystems.isEmpty {
            // 自动初始化过滤器选择（只在首次加载时）
            selectedSolarSystems = Set(availableSolarSystems)
        }
    }

    /// 获取星系的安全等级信息
    func getSolarSystemSecurity(_ systemName: String) -> Double? {
        // 从locationInfoCache中查找该星系的安全等级
        for (_, locationInfo) in locationInfoCache {
            if locationInfo.solarSystemName == systemName {
                return locationInfo.security
            }
        }
        return nil
    }

    /// 加载最大槽位数据
    private func loadMaxSlots(forceRefresh: Bool = false) async {
        maxSlots = await calculateMaxIndustrySlots(forceRefresh: forceRefresh)
    }

    /// 计算并缓存所有角色的详细信息
    private func calculateCharacterSlotDetails(forceRefresh: Bool = false) async -> [CharacterSlotDetail] {
        // 获取技能槽位增加属性的映射
        let attributeQuery = """
            SELECT type_id, attribute_id, value 
            FROM typeAttributes 
            WHERE attribute_id IN (450, 471, 2661)
        """

        var skillSlotBonuses: [Int: (manufacturing: Int, research: Int, reaction: Int)] = [:]

        if case let .success(rows) = databaseManager.executeQuery(attributeQuery) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let attributeId = row["attribute_id"] as? Int,
                      let value = row["value"] as? Double
                else { continue }

                if skillSlotBonuses[typeId] == nil {
                    skillSlotBonuses[typeId] = (manufacturing: 0, research: 0, reaction: 0)
                }

                let intValue = Int(value)
                switch attributeId {
                case 450: // 加工任务槽位增加数
                    skillSlotBonuses[typeId]?.manufacturing = intValue
                case 471: // 科研槽位增加数
                    skillSlotBonuses[typeId]?.research = intValue
                case 2661: // 反应任务增加数
                    skillSlotBonuses[typeId]?.reaction = intValue
                default:
                    break
                }
            }
        }

        // 确定要计算的角色ID列表（按ID排序）
        let characterIdsToCalculate: [Int]
        if multiCharacterMode, selectedCharacterIds.count > 1 {
            characterIdsToCalculate = Array(selectedCharacterIds).sorted()
        } else if multiCharacterMode, !selectedCharacterIds.isEmpty {
            characterIdsToCalculate = Array(selectedCharacterIds).sorted()
        } else {
            characterIdsToCalculate = [characterId]
        }

        // 初始化技能加载进度
        let totalCharacters = characterIdsToCalculate.count
        await MainActor.run {
            self.skillLoadingProgress = (current: 0, total: totalCharacters)
        }

        // 使用 Actor 来线程安全地更新进度
        let progressActor = SkillProgressActor(total: totalCharacters) { current, total in
            Task { @MainActor in
                self.skillLoadingProgress = (current: current, total: total)
            }
        }

        // 技能数据结果结构（仅包含需要并发获取的数据）
        struct SkillData {
            let characterId: Int
            let manufacturingSlots: Int
            let researchSlots: Int
            let reactionSlots: Int
            let manufacturingRange: Int
            let researchRange: Int
            let reactionRange: Int
        }

        var skillDataResults: [SkillData] = []

        // 并发获取所有角色的技能数据（仅网络请求部分）
        await withTaskGroup(of: SkillData?.self) { group in
            for charId in characterIdsToCalculate {
                group.addTask {
                    // 每个角色的基础槽位数
                    var manufacturingSlots = 1
                    var researchSlots = 1
                    var reactionSlots = 1
                    var manufacturingRange = 0
                    var researchRange = 0
                    var reactionRange = 0

                    // 使用 CharacterSkillsAPI 获取角色技能数据
                    do {
                        let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                            characterId: charId,
                            forceRefresh: forceRefresh
                        )

                        // 遍历技能槽位加成，从技能映射中查找对应技能
                        for (skillId, bonus) in skillSlotBonuses {
                            if let skill = skillsResponse.skillsMap[skillId] {
                                let level = skill.trained_skill_level
                                manufacturingSlots += bonus.manufacturing * level
                                researchSlots += bonus.research * level
                                reactionSlots += bonus.reaction * level
                            }
                        }

                        // 计算操作范围
                        manufacturingRange = (skillsResponse.skillsMap[24268]?.trained_skill_level ?? 0) * 5
                        researchRange = (skillsResponse.skillsMap[24270]?.trained_skill_level ?? 0) * 5
                        reactionRange = (skillsResponse.skillsMap[45750]?.trained_skill_level ?? 0) * 5

                        // 更新技能加载进度
                        await progressActor.increment()
                    } catch {
                        Logger.error("获取角色\(charId)技能数据失败: \(error)")
                        // 即使失败也要更新进度
                        await progressActor.increment()
                        return nil
                    }

                    return SkillData(
                        characterId: charId,
                        manufacturingSlots: manufacturingSlots,
                        researchSlots: researchSlots,
                        reactionSlots: reactionSlots,
                        manufacturingRange: manufacturingRange,
                        researchRange: researchRange,
                        reactionRange: reactionRange
                    )
                }
            }

            // 收集结果
            for await skillData in group {
                if let skillData = skillData {
                    skillDataResults.append(skillData)
                }
            }
        }

        // 在并发任务外处理本地数据（角色名称和已用槽位数）
        let availableCharactersSnapshot = await MainActor.run { self.availableCharacters }
        let jobsWithOwnerSnapshot = await MainActor.run { self.jobsWithOwner }

        var details: [CharacterSlotDetail] = []
        for skillData in skillDataResults {
            // 获取角色名称
            let characterName = availableCharactersSnapshot.first(where: { $0.id == skillData.characterId })?.name ?? "Unknown"

            // 计算该角色的已用槽位数
            let characterJobs = jobsWithOwnerSnapshot.filter { $0.ownerId == skillData.characterId }.map { $0.job }
            let activeJobs = characterJobs.filter { job in
                (job.status == "active" && job.end_date > Date()) // 正在进行中
                    || job.status == "ready" // 已完成但未交付
                    || (job.status == "active" && job.end_date <= Date()) // 已完成但状态未更新
            }

            let manufacturingUsed = activeJobs.filter { $0.activity_id == 1 }.count
            let researchUsed = activeJobs.filter { [3, 4, 5, 8].contains($0.activity_id) }.count
            let reactionUsed = activeJobs.filter { $0.activity_id == 9 }.count

            details.append(CharacterSlotDetail(
                characterId: skillData.characterId,
                characterName: characterName,
                manufacturingSlots: skillData.manufacturingSlots,
                researchSlots: skillData.researchSlots,
                reactionSlots: skillData.reactionSlots,
                manufacturingRange: skillData.manufacturingRange,
                researchRange: skillData.researchRange,
                reactionRange: skillData.reactionRange,
                manufacturingUsed: manufacturingUsed,
                researchUsed: researchUsed,
                reactionUsed: reactionUsed
            ))
        }

        // 按角色ID排序，保持一致性
        details.sort { $0.characterId < $1.characterId }

        // 清除技能加载进度
        await MainActor.run {
            self.skillLoadingProgress = nil
        }

        return details
    }

    /// 计算生产清单
    func calculateProductionList() {
        // 计算制造项目（activity_id == 1）和反应项目（activity_id == 9）
        // 只计算正在加工（status == "active" && end_date > Date()）和待交付（status == "ready"）的项目
        let productionJobs = jobs.filter { job in
            (job.activity_id == 1 || job.activity_id == 9) && (
                (job.status == "active" && job.end_date > Date()) ||
                    job.status == "ready"
            )
        }

        // 统计每个产品的总数量
        var productMap: [Int: ProductionItem] = [:]

        for job in productionJobs {
            if let productInfo = BlueprintCalcUtil.getBlueprintProductInfo(
                blueprintId: job.blueprint_type_id,
                runs: job.runs
            ) {
                if let existing = productMap[productInfo.typeId] {
                    // 如果已存在，累加数量
                    productMap[productInfo.typeId] = ProductionItem(
                        typeId: existing.typeId,
                        typeName: existing.typeName,
                        typeIcon: existing.typeIcon,
                        totalQuantity: existing.totalQuantity + productInfo.totalQuantity
                    )
                } else {
                    // 如果不存在，创建新条目
                    productMap[productInfo.typeId] = ProductionItem(
                        typeId: productInfo.typeId,
                        typeName: productInfo.typeName,
                        typeIcon: productInfo.typeIcon,
                        totalQuantity: productInfo.totalQuantity
                    )
                }
            }
        }

        // 转换为数组并按产品名称排序
        productionList = Array(productMap.values).sorted { $0.typeName.localizedCompare($1.typeName) == .orderedAscending }
    }

    /// 更新已用槽位数（在loadJobs完成后调用）
    private func updateCharacterSlotUsedCounts() {
        // 如果characterSlotDetails为空，说明还没有计算过，直接返回
        guard !characterSlotDetails.isEmpty else { return }

        // 重新创建characterSlotDetails数组，更新已用槽位数
        characterSlotDetails = characterSlotDetails.map { detail in
            // 计算该角色的已用槽位数
            let characterJobs = jobsWithOwner.filter { $0.ownerId == detail.characterId }.map { $0.job }
            let activeJobs = characterJobs.filter { job in
                (job.status == "active" && job.end_date > Date()) // 正在进行中
                    || job.status == "ready" // 已完成但未交付
                    || (job.status == "active" && job.end_date <= Date()) // 已完成但状态未更新
            }

            let manufacturingUsed = activeJobs.filter { $0.activity_id == 1 }.count
            let researchUsed = activeJobs.filter { [3, 4, 5, 8].contains($0.activity_id) }.count
            let reactionUsed = activeJobs.filter { $0.activity_id == 9 }.count

            return CharacterSlotDetail(
                characterId: detail.characterId,
                characterName: detail.characterName,
                manufacturingSlots: detail.manufacturingSlots,
                researchSlots: detail.researchSlots,
                reactionSlots: detail.reactionSlots,
                manufacturingRange: detail.manufacturingRange,
                researchRange: detail.researchRange,
                reactionRange: detail.reactionRange,
                manufacturingUsed: manufacturingUsed,
                researchUsed: researchUsed,
                reactionUsed: reactionUsed
            )
        }
    }

    /// 加载操作范围技能等级
    private func loadOperationRanges(forceRefresh: Bool = false) async {
        // 如果已经有缓存的详细信息，直接使用
        if !characterSlotDetails.isEmpty, !forceRefresh {
            let maxManufacturingRange = characterSlotDetails.map { $0.manufacturingRange }.max() ?? 0
            let maxResearchRange = characterSlotDetails.map { $0.researchRange }.max() ?? 0
            let maxReactionRange = characterSlotDetails.map { $0.reactionRange }.max() ?? 0

            manufacturingRange = maxManufacturingRange
            researchRange = maxResearchRange
            reactionRange = maxReactionRange
            return
        }

        // 重新计算详细信息
        let details = await calculateCharacterSlotDetails(forceRefresh: forceRefresh)
        characterSlotDetails = details

        // 计算最大操作范围
        let maxManufacturingRange = details.map { $0.manufacturingRange }.max() ?? 0
        let maxResearchRange = details.map { $0.researchRange }.max() ?? 0
        let maxReactionRange = details.map { $0.reactionRange }.max() ?? 0

        manufacturingRange = maxManufacturingRange
        researchRange = maxResearchRange
        reactionRange = maxReactionRange
    }

    /// 获取操作范围显示文本
    func getOperationRangeText(_ range: Int) -> String {
        if range == 0 {
            return NSLocalizedString("Industry_Range_Current_System", comment: "当前星系")
        } else {
            return String.localizedStringWithFormat(NSLocalizedString("Industry_Range_Jumps", comment: "%d 跳"), range)
        }
    }

    /// 计算工业槽位统计（只计算使用数量，不重新计算最大值）
    private func calculateIndustrySlotStats() {
        // 计算当前使用的槽位数，包括已完成但未交付的任务
        let activeJobs = jobs.filter { job in
            (job.status == "active" && job.end_date > Date()) // 正在进行中
                || job.status == "ready" // 已完成但未交付
                || (job.status == "active" && job.end_date <= Date()) // 已完成但状态未更新
        }

        let manufacturingUsed = activeJobs.filter { $0.activity_id == 1 }.count
        let researchUsed = activeJobs.filter { [3, 4, 5, 8].contains($0.activity_id) }.count
        let reactionUsed = activeJobs.filter { $0.activity_id == 9 }.count

        // 取计算出的最大槽位数和实际使用数量中的较大值，避免缓存不同步问题
        let actualManufacturingTotal = max(maxSlots.manufacturing, manufacturingUsed)
        let actualResearchTotal = max(maxSlots.research, researchUsed)
        let actualReactionTotal = max(maxSlots.reaction, reactionUsed)

        manufacturingSlots = (used: manufacturingUsed, total: actualManufacturingTotal)
        researchSlots = (used: researchUsed, total: actualResearchTotal)
        reactionSlots = (used: reactionUsed, total: actualReactionTotal)
    }

    /// 计算最大工业槽位数
    private func calculateMaxIndustrySlots(forceRefresh: Bool = false) async -> (
        manufacturing: Int, research: Int, reaction: Int
    ) {
        // 如果已经有缓存的详细信息，直接使用
        if !characterSlotDetails.isEmpty, !forceRefresh {
            let totalManufacturingSlots = characterSlotDetails.reduce(0) { $0 + $1.manufacturingSlots }
            let totalResearchSlots = characterSlotDetails.reduce(0) { $0 + $1.researchSlots }
            let totalReactionSlots = characterSlotDetails.reduce(0) { $0 + $1.reactionSlots }

            return (
                manufacturing: totalManufacturingSlots,
                research: totalResearchSlots,
                reaction: totalReactionSlots
            )
        }

        // 重新计算详细信息
        let details = await calculateCharacterSlotDetails(forceRefresh: forceRefresh)
        characterSlotDetails = details

        // 累计所有角色的槽位
        let totalManufacturingSlots = details.reduce(0) { $0 + $1.manufacturingSlots }
        let totalResearchSlots = details.reduce(0) { $0 + $1.researchSlots }
        let totalReactionSlots = details.reduce(0) { $0 + $1.reactionSlots }

        return (
            manufacturing: totalManufacturingSlots,
            research: totalResearchSlots,
            reaction: totalReactionSlots
        )
    }
}
