import SwiftUI

typealias CorpIndustryJob = CorpIndustryAPI.CorpIndustryJob

/// 军团工业项目倒计时组件 - 使用SwiftUI原生TimelineView
struct CorpIndustryCountdownView: View {
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(getDisplayText(at: context.date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func getDisplayText(at currentDate: Date) -> String {
        let remainingTime = endDate.timeIntervalSince(currentDate)

        if remainingTime <= 0 {
            return NSLocalizedString("Industry_Status_completed", comment: "")
        }

        let totalSeconds = Int(remainingTime)
        let days = totalSeconds / (24 * 3600)
        let hours = (totalSeconds % (24 * 3600)) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            if hours > 0 {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days_Hours", comment: ""),
                    days, hours
                )
            } else {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days", comment: ""),
                    days
                )
            }
        } else if hours > 0 {
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Hours_Minutes", comment: ""),
                    hours, minutes
                )
            } else {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Hours", comment: ""),
                    hours
                )
            }
        } else if minutes > 0 {
            return String(
                format: NSLocalizedString("Industry_Remaining_Minutes_Seconds", comment: "%d分%d秒"),
                minutes, seconds
            )
        } else {
            return String(
                format: NSLocalizedString("Industry_Remaining_Seconds", comment: "%d秒"),
                seconds
            )
        }
    }
}

/// 军团工业项目实时进度条组件
struct CorpIndustryProgressView: View {
    let job: CorpIndustryJob

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            PulsingProgressBar(
                progress: getProgress(at: context.date),
                color: getProgressColor(at: context.date),
                height: 4,
                cornerRadius: 2
            )
        }
    }

    private func getProgress(at currentDate: Date) -> Double {
        // 先检查是否已完成（根据状态或时间）
        if job.status == "delivered" || job.status == "ready" || currentDate >= job.end_date {
            return 1.0
        }

        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return 1.0
        default: // 进行中
            let totalDuration = Double(job.duration)
            let elapsedTime = currentDate.timeIntervalSince(job.start_date)
            let progress = elapsedTime / totalDuration
            return min(max(progress, 0), 1)
        }
    }

    private func getProgressColor(at _: Date) -> Color {
        // 先检查特殊状态
        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return .red
        case "delivered", "ready": // 已完成
            return .green
        case "active", "paused": // 进行中或暂停
            // 根据活动类型返回不同颜色
            switch job.activity_id {
            case 1: // 制造
                return Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
            case 3, 4: // 时间效率研究、材料效率研究
                return Color.blue
            case 5: // 复制
                return Color.blue
            case 8: // 发明
                return Color.blue
            case 9: // 反应
                return Color.cyan
            default:
                return Color.gray
            }
        default:
            return Color.gray
        }
    }
}

@MainActor
class CorpIndustryViewModel: ObservableObject {
    /// 配置常量
    private let soonCompleteThreshold: TimeInterval = 8 * 3600 // 即将完成阈值：8小时

    @Published var jobs: [CorpIndustryJob] = []
    @Published var groupedJobs: [String: [CorpIndustryJob]] = [:] // 按日期分组的工作项目
    @Published var isLoading = true
    @Published var isFiltering = false // 新增：过滤刷新状态
    @Published var error: Error?
    @Published var itemNames: [Int: String] = [:]
    @Published var locationInfoCache: [Int64: LocationInfoDetail] = [:]
    @Published var itemIcons: [Int: String] = [:]
    @Published var loadingProgress: String = "" // 加载进度信息

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
    @Published var selectedInstallers: Set<Int> = []
    @Published var selectedSolarSystems: Set<String> = []

    /// 可用的活动类型
    let availableActivityTypes = [1, 3, 4, 5, 8, 9] // 制造、ME研究、TE研究、复制、发明、反应

    /// 可用的发起人列表
    @Published var availableInstallers: [Int] = []

    /// 可用的星系列表
    @Published var availableSolarSystems: [String] = []

    private let characterId: Int
    private let databaseManager: DatabaseManager
    var initialLoadDone = false
    private var cachedJobs: [CorpIndustryJob]? // 缓存工业项目数据

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager

        // 从 UserDefaults 读取全局设置
        hideCompletedAndCancelled = UserDefaults.standard.bool(
            forKey: "hideCompletedAndCancelled_global"
        )

        // 创建即加载（与月矿/建筑页一致），视图层无需触发
        Task {
            await loadJobs()
        }
    }

    /// 将工作项目按状态分组
    private func groupJobsByStatus() {
        var grouped = [String: [CorpIndustryJob]]()
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

        // 根据是否是过滤刷新来设置不同的加载状态
        if isFiltering {
            self.isFiltering = true
        } else {
            isLoading = true
        }
        error = nil
        loadingProgress = NSLocalizedString("Loading_Corp_Industry_Jobs", comment: "正在加载军团工业项目...")

        do {
            // 加载数据
            let jobs = try await fetchJobs(forceRefresh: forceRefresh)

            // 更新数据
            self.jobs = jobs
            loadingProgress = NSLocalizedString("Loading_Item_Names", comment: "正在加载物品名称...")
            await loadItemNames()

            loadingProgress = NSLocalizedString("Loading_Location_Names", comment: "正在加载位置信息...")
            await loadLocationNames()

            loadingProgress = NSLocalizedString("Loading_Installer_Info", comment: "正在加载发起人信息...")
            await loadInstallerInfo()

            loadingProgress = NSLocalizedString("Processing_Data", comment: "正在处理数据...")
            groupJobsByStatus()

            // 更新过滤选项
            updateFilterOptions()

            // 根据是否是过滤刷新来清除相应的加载状态
            if isFiltering {
                self.isFiltering = false
            } else {
                isLoading = false
            }
            initialLoadDone = true
            loadingProgress = ""

        } catch {
            self.error = error
            isLoading = false
            self.isFiltering = false
            loadingProgress = ""
        }
    }

    /// 封装获取数据逻辑，处理缓存
    private func fetchJobs(forceRefresh: Bool = false) async throws -> [CorpIndustryJob] {
        // 如果不是强制刷新且有缓存，直接返回缓存
        if !forceRefresh, let cached = cachedJobs {
            Logger.info("使用内存缓存的军团工业项目数据 - 角色ID: \(characterId)")
            return cached
        }

        // 从API获取数据，带进度回调
        let jobs = try await CorpIndustryAPI.shared.fetchCorpIndustryJobs(
            characterId: characterId,
            forceRefresh: forceRefresh,
            includeCompleted: !hideCompletedAndCancelled,
            progressCallback: { currentPage, totalPages in
                Task { @MainActor in
                    self.loadingProgress = String(
                        format: NSLocalizedString(
                            "Loading_Corp_Industry_Page_Progress", comment: "正在加载第 %d/%d 页军团工业项目..."
                        ),
                        currentPage, totalPages
                    )
                }
            }
        )

        // 更新缓存
        cachedJobs = jobs

        return jobs
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
            locationIds.insert(job.location_id)
            locationIds.insert(job.facility_id)
        }

        let locationLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(characterId)
        )
        locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)
    }

    /// 加载发起人信息
    private func loadInstallerInfo() async {
        var installerIds = Set<Int>()
        for job in jobs {
            installerIds.insert(job.installer_id)
        }

        // 如果没有发起人ID，直接返回
        if installerIds.isEmpty {
            return
        }

        Logger.debug("开始加载\(installerIds.count)个发起人信息")

        // 计数器
        var successCount = 0
        var failureCount = 0

        // 并发获取发起人信息
        await withTaskGroup(of: Void.self) { group in
            for installerId in installerIds {
                group.addTask { @MainActor in
                    do {
                        // 获取发起人基本信息
                        let info = try await CharacterAPI.shared.fetchCharacterPublicInfo(
                            characterId: installerId, forceRefresh: false
                        )
                        self.installerNames[installerId] = info.name

                        // 获取发起人头像
                        let image = try await CharacterAPI.shared.fetchCharacterPortrait(
                            characterId: installerId, size: 64, forceRefresh: false,
                            catchImage: true
                        )
                        self.installerImages[installerId] = image

                        Logger.success("成功加载发起人信息 - ID: \(installerId), 名称: \(info.name)")
                        successCount += 1
                    } catch {
                        Logger.error("加载发起人信息失败 - ID: \(installerId), 错误: \(error)")
                        // 设置默认值，避免重复尝试
                        self.installerNames[installerId] = "Unknown"
                        failureCount += 1
                    }
                }
            }
        }

        Logger.debug("完成加载发起人信息 - 成功: \(successCount)个, 失败: \(failureCount)个")
    }

    /// 过滤后的分组数据
    var filteredGroupedJobs: [String: [CorpIndustryJob]] {
        var filtered = [String: [CorpIndustryJob]]()

        for (groupKey, jobs) in groupedJobs {
            // 如果隐藏已交付和已取消，跳过completed组
            if hideCompletedAndCancelled, groupKey == "completed" {
                continue
            }

            let filteredJobs = jobs.filter { job in
                // 按活动类型过滤
                let activityMatches = selectedActivityTypes.contains(job.activity_id)

                // 按发起人过滤
                let installerMatches =
                    selectedInstallers.isEmpty || selectedInstallers.contains(job.installer_id)

                // 按星系过滤
                var solarSystemMatches = true
                if !selectedSolarSystems.isEmpty {
                    if let locationInfo = locationInfoCache[job.location_id] {
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
        // 更新可用的发起人列表，按人物名称排序
        let installerIds = Array(Set(jobs.map { $0.installer_id }))
        let newAvailableInstallers = installerIds.sorted { id1, id2 in
            let name1 = installerNames[id1] ?? "Unknown"
            let name2 = installerNames[id2] ?? "Unknown"
            return name1.localizedCompare(name2) == .orderedAscending
        }

        // 更新可用的星系列表，按星系名称排序
        var solarSystems = Set<String>()
        for job in jobs {
            if let locationInfo = locationInfoCache[job.location_id] {
                solarSystems.insert(locationInfo.solarSystemName)
            }
        }
        let newAvailableSolarSystems = Array(solarSystems).sorted {
            $0.localizedCompare($1) == .orderedAscending
        }

        // 检查发起人列表是否发生了变化
        let installersChanged = Set(newAvailableInstallers) != Set(availableInstallers)
        availableInstallers = newAvailableInstallers

        // 检查星系列表是否发生了变化
        let solarSystemsChanged = Set(newAvailableSolarSystems) != Set(availableSolarSystems)
        availableSolarSystems = newAvailableSolarSystems

        // 如果发起人列表发生了变化，自动选中所有发起人
        if installersChanged, !availableInstallers.isEmpty {
            selectedInstallers = Set(availableInstallers)
        } else if selectedInstallers.isEmpty, !availableInstallers.isEmpty {
            // 自动初始化过滤器选择（只在首次加载时）
            selectedInstallers = Set(availableInstallers)
        }

        // 如果星系列表发生了变化，自动选中所有星系
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
}

struct CorpIndustryView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpIndustryViewModel
    @State private var showFilterSheet = false

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        // 构造表达式内联在 autoclosure 中，避免父视图每次重渲染都新建 ViewModel
        _viewModel = StateObject(wrappedValue: CorpIndustryViewModel(
            characterId: characterId, databaseManager: databaseManager
        ))
    }

    /// 格式化状态组标题
    private func formatStatusGroupHeader(_ statusKey: String) -> String {
        switch statusKey {
        case "ready":
            return NSLocalizedString("Industry_Ready_For_Delivery", comment: "准备交付")
        case "soon":
            return NSLocalizedString("Industry_Soon_Complete", comment: "即将完成")
        case "active":
            return NSLocalizedString("Industry_In_Progress", comment: "进行中")
        case "completed":
            return NSLocalizedString("Industry_Completed_Cancelled", comment: "已交付/已取消")
        default:
            return statusKey
        }
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }

                    if !viewModel.loadingProgress.isEmpty {
                        Text(viewModel.loadingProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            } else if let error = viewModel.error,
                      !viewModel.isLoading && viewModel.jobs.isEmpty
            {
                // 显示错误信息
                ErrorStateSection(message: error.localizedDescription) {
                    Task {
                        await viewModel.loadJobs(forceRefresh: true)
                    }
                }
            } else {
                // 工业槽位统计 Section - 始终显示
                Section(
                    header: Text(NSLocalizedString("Industry_Task_List_Header", comment: "任务清单"))
                ) {
                    // 计算各类任务的活跃项目数量（参考人物工业项目的过滤逻辑）
                    let currentTime = Date()
                    let activeJobs = viewModel.jobs.filter { job in
                        (job.status == "active" && job.end_date > currentTime) // 正在进行中
                            || job.status == "ready" // 已完成但未交付
                            || (job.status == "active" && job.end_date <= currentTime) // 已完成但状态未更新
                    }

                    let manufacturingCount = activeJobs.filter { $0.activity_id == 1 }.count
                    let researchCount = activeJobs.filter { [3, 4, 5, 8].contains($0.activity_id) }
                        .count
                    let reactionCount = activeJobs.filter { $0.activity_id == 9 }.count

                    // 加工任务
                    HStack {
                        Text(NSLocalizedString("Industry_Slots_Manufacturing", comment: "加工任务"))
                            .font(.body)
                        Spacer()
                        Text("\(manufacturingCount)")
                            .font(.body)
                            .fontDesign(.monospaced)
                            .foregroundColor(Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255))
                    }

                    // 科研任务
                    HStack {
                        Text(NSLocalizedString("Industry_Slots_Research", comment: "研究任务"))
                            .font(.body)
                        Spacer()
                        Text("\(researchCount)")
                            .font(.body)
                            .fontDesign(.monospaced)
                            .foregroundColor(Color.blue)
                    }

                    // 反应任务
                    HStack {
                        Text(NSLocalizedString("Industry_Slots_Reaction", comment: "反应任务"))
                            .font(.body)
                        Spacer()
                        Text("\(reactionCount)")
                            .font(.body)
                            .fontDesign(.monospaced)
                            .foregroundColor(Color.cyan)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                .listSectionSpacing(.compact)

                // 过滤刷新指示器
                if viewModel.isFiltering {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(
                                    NSLocalizedString(
                                        "Industry_Filtering_Data", comment: "正在更新数据..."
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                }

                // 工业任务列表部分
                if viewModel.filteredGroupedJobs.isEmpty && !viewModel.isFiltering {
                    Section {
                        // 计算总项目数和过滤后的项目数
                        let totalJobsCount = viewModel.groupedJobs.values.reduce(0) {
                            $0 + $1.count
                        }

                        ContentUnavailableView {
                            Label(
                                NSLocalizedString("Misc_No_Data", comment: ""),
                                systemImage: totalJobsCount > 0
                                    ? "line.3.horizontal.decrease.circle" : "exclamationmark.triangle"
                            )
                        } description: {
                            // 如果有总项目但被过滤完了，显示过滤信息
                            if totalJobsCount > 0 {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Industry_Filtered_Count", comment: "已过滤 %d 个项目"
                                        ),
                                        totalJobsCount
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.orange)
                            }
                        }
                    }
                    .listSectionSpacing(.compact)
                } else if !viewModel.isFiltering {
                    // 按优先级排序：ready -> soon -> active -> completed
                    ForEach(
                        ["ready", "soon", "active", "completed"].filter {
                            viewModel.filteredGroupedJobs.keys.contains($0)
                        },
                        id: \.self
                    ) { statusKey in
                        Section(
                            header: HStack {
                                Text(formatStatusGroupHeader(statusKey))

                                Spacer()

                                // 显示每个section的项目数量
                                let sectionCount =
                                    viewModel.filteredGroupedJobs[statusKey]?.count ?? 0
                                Text("(\(sectionCount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        ) {
                            ForEach(viewModel.filteredGroupedJobs[statusKey] ?? [], id: \.job_id) {
                                job in
                                CorpIndustryJobRow(
                                    job: job,
                                    blueprintName: viewModel.itemNames[job.blueprint_type_id]
                                        ?? "Unknown BP",
                                    blueprintIcon: viewModel.itemIcons[job.blueprint_type_id],
                                    locationInfo: viewModel.locationInfoCache[job.location_id],
                                    currentTime: Date(), // 使用当前时间作为倒计时基准
                                    installerName: viewModel.installerNames[job.installer_id],
                                    installerImage: viewModel.installerImages[job.installer_id]
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadJobs(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_Industry", comment: "军团工业"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showFilterSheet = true
                }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            CorpIndustryFilterSheet(viewModel: viewModel)
        }
    }
}

struct CorpIndustryJobRow: View {
    let job: CorpIndustryJob
    let blueprintName: String
    let blueprintIcon: String?
    let locationInfo: LocationInfoDetail?
    let currentTime: Date
    let installerName: String?
    let installerImage: UIImage?
    @StateObject private var databaseManager = DatabaseManager()
    @Environment(\.colorScheme) private var colorScheme

    /// 带颜色的状态文本结构体
    struct StatusText {
        let text: String
        let color: Color
    }

    /// 修改时间显示格式
    private func getTimeDisplay() -> String {
        let currentTime = Date()
        let dateStr = formatDate(job.end_date)

        // 如果已经完成，只显示完成时间
        if job.status == "delivered" || job.status == "ready" || currentTime >= job.end_date {
            return dateStr
        }

        // 如果是活动状态，添加剩余时间
        if job.status == "active" {
            return dateStr
        }

        return dateStr
    }

    /// 获取活动状态文本和颜色
    private func getActivityStatus() -> StatusText {
        // 先检查特殊状态
        switch job.status {
        case "cancelled":
            return StatusText(
                text: NSLocalizedString("Industry_Status_cancelled", comment: ""),
                color: .red
            )
        case "revoked":
            return StatusText(
                text: NSLocalizedString("Industry_Status_revoked", comment: ""),
                color: .red
            )
        case "failed":
            return StatusText(
                text: NSLocalizedString("Industry_Status_failed", comment: ""),
                color: .red
            )
        case "delivered":
            let statusText = NSLocalizedString("Industry_Status_delivered", comment: "")
            var finalText = statusText
            // 只在概率不为1且runs大于1时显示成功比例
            if job.probability != nil && job.probability! != 1.0 && job.runs > 1 {
                let successfulRuns = job.successful_runs ?? 0
                finalText = "\(statusText) (\(successfulRuns)/\(job.runs))"
            }
            return StatusText(text: finalText, color: .secondary)
        case "ready":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_ready", comment: ""))",
                color: .green
            )
        default:
            // 检查是否已完成但未交付
            if Date() >= job.end_date {
                return StatusText(
                    text:
                    "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_ready", comment: ""))",
                    color: .green
                )
            }

            if job.status != "active" {
                return StatusText(
                    text: NSLocalizedString("Industry_Status_\(job.status)", comment: ""),
                    color: .secondary
                )
            }

            // 如果是活动状态，根据活动类型返回对应文本和颜色
            // https://sde.hoboleaks.space/tq/industryactivities.json
            switch job.activity_id {
            case 1:
                return StatusText(
                    text: NSLocalizedString("Industry_Type_Manufacturing_Short", comment: ""),
                    color: Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                )
            case 3:
                return StatusText(
                    text: NSLocalizedString("Industry_Type_Research_Time_Short", comment: ""),
                    color: Color.blue
                )
            case 4:
                return StatusText(
                    text: NSLocalizedString("Industry_Type_Research_Material_Short", comment: ""),
                    color: Color.blue
                )
            case 5:
                return StatusText(
                    text: NSLocalizedString("Industry_Type_Copying", comment: ""),
                    color: Color.blue
                )
            case 8:
                return StatusText(
                    text: NSLocalizedString("Industry_Type_Invention", comment: ""),
                    color: Color.blue
                )
            case 9:
                return StatusText(
                    text: NSLocalizedString("Industry_Type_Reaction", comment: ""),
                    color: Color.cyan
                )
            default:
                return StatusText(
                    text: NSLocalizedString("Industry_Status_active", comment: ""),
                    color: .secondary
                )
            }
        }
    }

    /// 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// 获取活动类型文本
    private func getActivityTypeText() -> String {
        switch job.activity_id {
        case 1:
            return NSLocalizedString("Industry_Type_Manufacturing_Short", comment: "")
        case 3:
            return NSLocalizedString("Industry_Type_Research_Time_Short", comment: "")
        case 4:
            return NSLocalizedString("Industry_Type_Research_Material_Short", comment: "")
        case 5:
            return NSLocalizedString("Industry_Type_Copying", comment: "")
        case 8:
            return NSLocalizedString("Industry_Type_Invention", comment: "")
        case 9:
            return NSLocalizedString("Industry_Type_Reaction", comment: "")
        default:
            return ""
        }
    }

    var body: some View {
        NavigationLink(
            destination: ShowBluePrintInfo(
                blueprintID: job.blueprint_type_id, databaseManager: databaseManager
            )
        ) {
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：蓝图图标、名称和状态
                HStack(spacing: 12) {
                    // 蓝图图标
                    if let iconFileName = blueprintIcon {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // 蓝图名称和状态
                        HStack(spacing: 6) {
                            // 工业类型图标
                            if colorScheme == .light {
                                IconManager.shared.loadImage(
                                    for: getActivityTypeIcon(for: job.activity_id)
                                )
                                .resizable()
                                .frame(width: 14, height: 14)
                                .cornerRadius(2)
                                .colorInvert()
                            } else {
                                IconManager.shared.loadImage(
                                    for: getActivityTypeIcon(for: job.activity_id)
                                )
                                .resizable()
                                .frame(width: 14, height: 14)
                                .cornerRadius(2)
                            }

                            Text(blueprintName)
                                .font(.headline)
                                .lineLimit(1)

                            Spacer()

                            // 已完成可交付标记
                            if job.status == "ready" || (job.status == "active" && currentTime >= job.end_date) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                            }
                        }

                        // 数量信息
                        HStack {
                            Text(
                                job.activity_id == 5
                                    ? String(
                                        format: NSLocalizedString(
                                            "Industry_Runs_With_Copies_Format", comment: ""
                                        ),
                                        job.runs, job.licensed_runs ?? 1
                                    )
                                    : String(
                                        format: NSLocalizedString(
                                            "Industry_Runs_Format", comment: ""
                                        ), job.runs
                                    )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            Spacer()
                            if job.status == "active" {
                                CorpIndustryCountdownView(endDate: job.end_date)
                            }
                        }
                    }
                }

                // 进度条
                CorpIndustryProgressView(job: job)
                    .padding(.vertical, 4)

                // 第二行：位置信息和发起人信息
                if installerName != nil {
                    GeometryReader { geometry in
                        HStack(spacing: 8) {
                            // 左侧 2/3：位置信息
                            LocationInfoView(
                                stationName: locationInfo?.stationName,
                                solarSystemName: locationInfo?.solarSystemName,
                                security: locationInfo?.security,
                                font: .caption,
                                textColor: .secondary
                            )
                            .lineLimit(1)
                            .frame(width: geometry.size.width * 0.67, alignment: .leading)

                            Spacer()

                            // 右侧 1/3：发起人信息
                            if let installerName = installerName {
                                HStack(spacing: 4) {
                                    // 发起人头像
                                    if let installerImage = installerImage {
                                        Image(uiImage: installerImage)
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } else {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 18, height: 18)
                                    }

                                    // 发起人名称
                                    Text(installerName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: geometry.size.width * 0.33 - 8, alignment: .trailing)
                            }
                        }
                    }
                    .frame(height: 16)
                } else {
                    // 没有发起人信息：只显示位置信息
                    LocationInfoView(
                        stationName: locationInfo?.stationName,
                        solarSystemName: locationInfo?.solarSystemName,
                        security: locationInfo?.security,
                        font: .caption,
                        textColor: .secondary
                    )
                    .lineLimit(1)
                }
                HStack {
                    let statusInfo = getActivityStatus()
                    Text(statusInfo.text)
                        .font(.caption)
                        .foregroundColor(statusInfo.color)
                    Spacer()

                    // 根据完成状态显示不同的时间前缀
                    let isCompleted = job.status == "delivered" || job.status == "ready" || currentTime >= job.end_date
                    let timePrefix = isCompleted
                        ? NSLocalizedString("Industry_Completed_At", comment: "已完成于")
                        : NSLocalizedString("Finished_on", comment: "")

                    Text("\(timePrefix) \(getTimeDisplay())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            // 复制发起人名称
            if let installerName = installerName {
                Button {
                    UIPasteboard.general.string = installerName
                } label: {
                    Label(
                        NSLocalizedString("Industry_Copy_Installer_Name", comment: "复制发起人名称: %@"),
                        systemImage: "person.crop.circle"
                    )
                }
            }

            // 复制地点信息
            if let locationInfo = locationInfo {
                Button {
                    let locationText =
                        !locationInfo.stationName.isEmpty
                            ? locationInfo.stationName : locationInfo.solarSystemName
                    UIPasteboard.general.string = locationText
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Location", comment: "复制地点"),
                        systemImage: "doc.on.doc"
                    )
                }
            }
        }
    }
}

struct CorpIndustryFilterSheet: View {
    @ObservedObject var viewModel: CorpIndustryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 获取活动类型的本地化名称
    private func getActivityTypeName(_ activityId: Int) -> String {
        switch activityId {
        case 1:
            return NSLocalizedString("Industry_Type_Manufacturing_Short", comment: "制造")
        case 3:
            return NSLocalizedString("Industry_Type_Research_Time_Short", comment: "时间效率研究")
        case 4:
            return NSLocalizedString("Industry_Type_Research_Material_Short", comment: "材料效率研究")
        case 5:
            return NSLocalizedString("Industry_Type_Copying", comment: "复制")
        case 8:
            return NSLocalizedString("Industry_Type_Invention", comment: "发明")
        case 9:
            return NSLocalizedString("Industry_Type_Reaction", comment: "反应")
        default:
            return "Unknown Activity \(activityId)"
        }
    }

    /// 获取活动类型对应的颜色
    private func getActivityTypeColor(_ activityId: Int) -> Color {
        switch activityId {
        case 1: // 制造
            return Color(red: 0.9, green: 0.7, blue: 0.3) // 土黄色
        case 3, 4, 5, 8: // 时间效率研究、材料效率研究、复制、发明
            return Color.blue // 蓝色
        case 9: // 反应
            return Color.cyan // 青蓝色
        default:
            return Color.gray
        }
    }

    /// 获取活动类型对应的图标文件名
    private func getActivityTypeIcon(_ activityId: Int) -> String {
        switch activityId {
        case 1: // 制造
            return "Icon_Manufacturing.png"
        case 3: // 时间效率研究
            return "Icon_ResearchTime.png"
        case 4: // 材料效率研究
            return "Icon_ResearchMaterial.png"
        case 5: // 复制
            return "Icon_Copying.png"
        case 8: // 发明
            return "Icon_Invention.png"
        case 9: // 反应
            return "Icon_reaction.png"
        default:
            return "Icon_Manufacturing.png"
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // 第一个section：隐藏已交付和已取消的项目
                Section {
                    Toggle(isOn: $viewModel.hideCompletedAndCancelled) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Industry_Filter_Hide_Completed", comment: "隐藏已交付和已取消的项目"
                                )
                            )
                            Text(
                                NSLocalizedString(
                                    "Industry_Filter_Hide_Completed_Description",
                                    comment: "隐藏已完成、已取消、已撤销等状态的项目"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                // 第二个section：按项目类型过滤
                Section {
                    ForEach(viewModel.availableActivityTypes, id: \.self) { activityId in
                        Button(action: {
                            if viewModel.selectedActivityTypes.contains(activityId) {
                                viewModel.selectedActivityTypes.remove(activityId)
                            } else {
                                viewModel.selectedActivityTypes.insert(activityId)
                            }
                        }) {
                            HStack {
                                // 添加彩色圆点
                                Circle()
                                    .fill(getActivityTypeColor(activityId))
                                    .frame(width: 8, height: 8)

                                // 添加工业类型图标
                                if colorScheme == .light {
                                    IconManager.shared.loadImage(
                                        for: getActivityTypeIcon(activityId)
                                    )
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(4)
                                    .colorInvert()
                                } else {
                                    IconManager.shared.loadImage(
                                        for: getActivityTypeIcon(activityId)
                                    )
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(4)
                                }
                                Text(getActivityTypeName(activityId))
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedActivityTypes.contains(activityId) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("Industry_Filter_Activity_Types", comment: "项目类型"))
                        Spacer()
                        Button(action: {
                            if viewModel.selectedActivityTypes.count
                                == viewModel.availableActivityTypes.count
                            {
                                viewModel.selectedActivityTypes = []
                            } else {
                                viewModel.selectedActivityTypes = Set(
                                    viewModel.availableActivityTypes
                                )
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: "全选"))
                                    .font(.caption)
                                if viewModel.selectedActivityTypes.count
                                    == viewModel.availableActivityTypes.count
                                {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // 第三个section：按发起人过滤
                if !viewModel.availableInstallers.isEmpty {
                    Section {
                        ForEach(viewModel.availableInstallers, id: \.self) { installerId in
                            Button(action: {
                                if viewModel.selectedInstallers.contains(installerId) {
                                    viewModel.selectedInstallers.remove(installerId)
                                } else {
                                    viewModel.selectedInstallers.insert(installerId)
                                }
                            }) {
                                HStack {
                                    // 显示发起人头像和名称
                                    if let installerImage = viewModel.installerImages[installerId] {
                                        Image(uiImage: installerImage)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } else {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 32, height: 32)
                                    }

                                    Text(viewModel.installerNames[installerId] ?? "Unknown")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if viewModel.selectedInstallers.contains(installerId) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Industry_Filter_Installers", comment: "发起人"))
                            Spacer()
                            Button(action: {
                                if viewModel.selectedInstallers.count
                                    == viewModel.availableInstallers.count
                                {
                                    viewModel.selectedInstallers = []
                                } else {
                                    viewModel.selectedInstallers = Set(
                                        viewModel.availableInstallers
                                    )
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Industry_Filter_Select_All", comment: "全选"
                                        )
                                    )
                                    .font(.caption)
                                    if viewModel.selectedInstallers.count
                                        == viewModel.availableInstallers.count
                                    {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // 第四个section：按星系过滤
                if !viewModel.availableSolarSystems.isEmpty {
                    Section {
                        ForEach(viewModel.availableSolarSystems, id: \.self) { solarSystem in
                            Button(action: {
                                if viewModel.selectedSolarSystems.contains(solarSystem) {
                                    viewModel.selectedSolarSystems.remove(solarSystem)
                                } else {
                                    viewModel.selectedSolarSystems.insert(solarSystem)
                                }
                            }) {
                                HStack {
                                    // 安全等级和星系名称
                                    if let security = viewModel.getSolarSystemSecurity(solarSystem) {
                                        Text(formatSystemSecurity(security))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(getSecurityColor(security))
                                        Text(solarSystem)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text(solarSystem)
                                            .foregroundColor(.primary)
                                    }

                                    Spacer()
                                    if viewModel.selectedSolarSystems.contains(solarSystem) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Industry_Filter_Solar_Systems", comment: "星系"))
                            Spacer()
                            Button(action: {
                                if viewModel.selectedSolarSystems.count
                                    == viewModel.availableSolarSystems.count
                                {
                                    viewModel.selectedSolarSystems = []
                                } else {
                                    viewModel.selectedSolarSystems = Set(
                                        viewModel.availableSolarSystems
                                    )
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Industry_Filter_Select_All", comment: "全选"
                                        )
                                    )
                                    .font(.caption)
                                    if viewModel.selectedSolarSystems.count
                                        == viewModel.availableSolarSystems.count
                                    {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Industry_Filter_Title", comment: "过滤设置"))
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
