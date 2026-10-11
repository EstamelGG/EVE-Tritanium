import SwiftUI

@MainActor
final class PersonalContractsViewModel: ObservableObject {
    @Published var contractGroups: [ContractGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentLoadingPage: Int?
    /// 合同类型枚举
    enum ContractType: Int, CaseIterable {
        case personal = 0
        case corporation = 1
        case alliance = 2

        var localizedName: String {
            switch self {
            case .personal:
                return NSLocalizedString("Contracts_Personal", comment: "")
            case .corporation:
                return NSLocalizedString("Contracts_Corporation", comment: "")
            case .alliance:
                return NSLocalizedString("Contracts_Alliance", comment: "")
            }
        }
    }

    /// 分组方式枚举
    enum GroupingMode: Int, CaseIterable {
        case byIssueDate = 0
        case byCompletionDate = 1

        var localizedName: String {
            switch self {
            case .byIssueDate:
                return NSLocalizedString("Contract_Group_By_Issue_Date", comment: "")
            case .byCompletionDate:
                return NSLocalizedString("Contract_Group_By_Completion_Date", comment: "")
            }
        }
    }

    @Published var selectedContractType: ContractType = .personal {
        didSet {
            Logger.debug("合同类型切换: \(selectedContractType.localizedName)")
        }
    }

    @Published var groupingMode: GroupingMode = .byIssueDate {
        didSet {
            // 保存设置到 UserDefaults
            UserDefaults.standard.set(groupingMode.rawValue, forKey: "groupingMode_\(characterId)")
            // 当切换分组方式时，重新分组
            Task {
                let groups = await processContractGroups(cachedContractsForSelectedType)
                await MainActor.run {
                    self.contractGroups = groups
                }
            }
        }
    }

    @Published var isInitialized = false

    @Published var hasCorporationAccess = false
    @Published var hasAllianceAccess = false
    @Published var courierMode = false {
        didSet {
            // 保存设置到 UserDefaults
            UserDefaults.standard.set(courierMode, forKey: "courierMode_\(characterId)")
            // 当切换模式时，重新分组但不立即更新 UI
            Task {
                // 先处理数据
                let groups = await processContractGroups(cachedContractsForSelectedType)
                // 一次性更新 UI
                await MainActor.run {
                    self.contractGroups = groups
                }
            }
        }
    }

    private var loadingTask: Task<Void, Never>?
    private var personalContractsInitialized = false
    private var corporationContractsInitialized = false
    private var allianceContractsInitialized = false
    private var cachedPersonalContracts: [ContractInfo] = []
    private var cachedCorporationContracts: [ContractInfo] = []
    private var cachedAllianceContracts: [ContractInfo] = []

    /// 当前选中类型的缓存合同（用于读取）
    private var cachedContractsForSelectedType: [ContractInfo] {
        switch selectedContractType {
        case .personal:
            cachedPersonalContracts
        case .corporation:
            cachedCorporationContracts
        case .alliance:
            cachedAllianceContracts
        }
    }

    /// 当前选中类型是否已初始化加载
    private var isSelectedTypeInitialized: Bool {
        switch selectedContractType {
        case .personal:
            personalContractsInitialized
        case .corporation:
            corporationContractsInitialized
        case .alliance:
            allianceContractsInitialized
        }
    }

    /// 更新当前选中类型的缓存合同
    private func updateCachedContracts(_ contracts: [ContractInfo]) {
        switch selectedContractType {
        case .personal:
            cachedPersonalContracts = contracts
            personalContractsInitialized = true
        case .corporation:
            cachedCorporationContracts = contracts
            corporationContractsInitialized = true
        case .alliance:
            cachedAllianceContracts = contracts
            allianceContractsInitialized = true
        }
    }

    let characterId: Int
    let character: EVECharacterInfo
    let databaseManager: DatabaseManager
    private lazy var locationLoader: LocationInfoLoader = .init(
        databaseManager: databaseManager, characterId: Int64(characterId)
    )

    /// 添加一个标志来跟踪是否正在进行强制刷新
    private var isForceRefreshing = false

    private var calendar: Calendar {
        FormatUtil.appCalendar
    }

    /// 添加地点名称缓存
    private var locationCache: [Int64: String] = [:]
    /// 添加地点名称加载状态追踪
    private var locationLoadingTasks: Set<Int64> = []

    init(characterId: Int, character: EVECharacterInfo) {
        self.characterId = characterId
        self.character = character
        databaseManager = DatabaseManager()
        // 初始化时检查军团和联盟访问权限
        Task {
            await checkCorporationAccess()
            await checkAllianceAccess()
        }

        // 从 UserDefaults 读取快递模式设置
        if let courierModeSetting = UserDefaults.standard.value(
            forKey: "courierMode_\(characterId)"
        ) as? Bool {
            courierMode = courierModeSetting
        }

        // 从 UserDefaults 读取分组方式设置
        if let groupingModeValue = UserDefaults.standard.value(
            forKey: "groupingMode_\(characterId)"
        ) as? Int,
            let savedGroupingMode = GroupingMode(rawValue: groupingModeValue)
        {
            groupingMode = savedGroupingMode
        }

        // 构造时启动数据加载（原先由视图 init 触发，移入以避免视图重复构造引发重复加载）
        Task {
            await loadContractsData()
            isInitialized = true
        }
    }

    /// 检查是否有军团合同访问权限
    private func checkCorporationAccess() async {
        // 直接从全局缓存获取军团ID
        if character.corporationId != nil {
            hasCorporationAccess = true
        } else {
            hasCorporationAccess = false
            if selectedContractType == .corporation {
                selectedContractType = .personal
            }
        }
    }

    /// 检查是否有联盟合同访问权限
    private func checkAllianceAccess() async {
        // 直接从全局缓存获取联盟ID
        if character.allianceId != nil {
            hasAllianceAccess = true
        } else {
            hasAllianceAccess = false
            if selectedContractType == .alliance {
                selectedContractType = .personal
            }
        }
    }

    private func updateContractGroups(with contracts: [ContractInfo]) async {
        let groups = await processContractGroups(contracts)
        await MainActor.run {
            self.contractGroups = groups
        }
    }

    func loadContractsData(forceRefresh: Bool = false) async {
        // 如果已经在加载中且不是强制刷新，则直接返回
        if isLoading, !forceRefresh {
            return
        }

        // 如果是强制刷新，设置标志
        if forceRefresh {
            isForceRefreshing = true
        }

        // 如果已经加载过且不是强制刷新，直接使用缓存
        if !forceRefresh, isSelectedTypeInitialized {
            await updateContractGroups(with: cachedContractsForSelectedType)
            return
        }

        // 在开始加载前一次性更新 UI 状态
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            currentLoadingPage = nil
            // 只有在非强制刷新（非下拉刷新）时才清空列表
            // 下拉刷新时保留旧数据，直到新数据加载完成
            if !forceRefresh {
                contractGroups = []
            }
        }

        do {
            let contracts: [ContractInfo]

            // 使用 Task.detached 在后台线程加载数据
            let loadedContracts = try await Task.detached(priority: .userInitiated) {
                switch await self.selectedContractType {
                case .personal:
                    // 获取个人合同
                    return try await CharacterContractsAPI.shared.fetchContracts(
                        characterId: self.characterId,
                        forceRefresh: forceRefresh,
                        progressCallback: { page in
                            Task { @MainActor in
                                self.currentLoadingPage = page
                            }
                        }
                    )
                case .corporation:
                    // 获取军团合同
                    return try await CorporationContractsAPI.shared.fetchContracts(
                        characterId: self.characterId,
                        forceRefresh: forceRefresh,
                        progressCallback: { page in
                            Task { @MainActor in
                                self.currentLoadingPage = page
                            }
                        }
                    )
                case .alliance:
                    // 获取联盟合同
                    guard let corporationId = await self.character.corporationId,
                          let allianceId = await self.character.allianceId
                    else {
                        throw NetworkError.authenticationError("无法获取军团ID或联盟ID")
                    }
                    return try await AllianceContractsAPI.shared.fetchContracts(
                        characterId: self.characterId,
                        corporationId: corporationId,
                        allianceId: allianceId,
                        forceRefresh: forceRefresh,
                        progressCallback: { page in
                            Task { @MainActor in
                                self.currentLoadingPage = page
                            }
                        }
                    )
                }
            }.value

            // 检查任务是否被取消
            if Task.isCancelled {
                await MainActor.run {
                    isLoading = false
                    currentLoadingPage = nil
                    isForceRefreshing = false
                }
                return
            }

            contracts = loadedContracts

            // 更新缓存
            updateCachedContracts(contracts)

            // 先处理数据，再一次性更新 UI
            let processedGroups = await processContractGroups(contracts)

            // 一次性更新所有 UI 状态
            await MainActor.run {
                self.contractGroups = processedGroups
                isLoading = false
                currentLoadingPage = nil
                isForceRefreshing = false
                isInitialized = true
            }

        } catch {
            if !(error is CancellationError) {
                await MainActor.run {
                    // 仅在无数据时设置错误信息（避免刷新失败时覆盖已有数据的显示）
                    if self.contractGroups.isEmpty {
                        self.errorMessage = error.localizedDescription
                    }
                    Logger.error("加载\(self.selectedContractType.localizedName)合同数据失败: \(error)")
                    self.isLoading = false
                    self.currentLoadingPage = nil
                    self.isForceRefreshing = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.currentLoadingPage = nil
                    self.isForceRefreshing = false
                }
            }
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    /// 修改获取地点名称的方法
    private func getLocationName(_ locationId: Int64) async -> String {
        if let cached = locationCache[locationId] {
            return cached
        }

        // 如果已经在加载中，等待加载完成
        if locationLoadingTasks.contains(locationId) {
            // 最多等待3秒
            for _ in 0 ..< 30 {
                if let cached = locationCache[locationId] {
                    return cached
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 等待100ms
            }
            // 如果等待超时，返回未知
            return NSLocalizedString("Unknown", comment: "")
        }

        // 标记为正在加载
        locationLoadingTasks.insert(locationId)

        let locationInfos = await locationLoader.loadLocationInfo(locationIds: Set([locationId]))
        if let locationInfo = locationInfos[locationId] {
            let name = locationInfo.solarSystemName
            locationCache[locationId] = name
            locationLoadingTasks.remove(locationId)
            return name
        }
        locationLoadingTasks.remove(locationId)
        return NSLocalizedString("Unknown", comment: "")
    }

    /// 修改按路线分组合同的方法
    private func groupContractsByRoute(_ contracts: [ContractInfo]) async -> [ContractGroup] {
        // 按路线分组
        var groupedContracts: [String: [ContractInfo]] = [:]
        var routeNames: [String: (start: String, end: String)] = [:]

        // 第一步：收集所有合同并获取位置名称
        for contract in contracts {
            let startId = contract.start_location_id
            let endId = contract.end_location_id
            let routeKey = "\(startId)-\(endId)"

            if groupedContracts[routeKey] == nil {
                groupedContracts[routeKey] = []

                // 异步获取位置名称
                let startName = await getLocationName(startId)
                let endName = await getLocationName(endId)
                routeNames[routeKey] = (start: startName, end: endName)
            }
            groupedContracts[routeKey]?.append(contract)
        }

        // 第二步：创建分组
        var result: [ContractGroup] = []
        for (routeKey, contracts) in groupedContracts {
            let sortedContracts = contracts.sorted { $0.reward > $1.reward }
            if let first = sortedContracts.first,
               let routeName = routeNames[routeKey]
            {
                result.append(
                    ContractGroup(
                        date: first.date_issued,
                        contracts: sortedContracts,
                        startLocation: routeName.start,
                        endLocation: routeName.end
                    )
                )
            }
        }

        // 第三步：按照奖励排序
        return result.sorted { $0.contracts[0].reward > $1.contracts[0].reward }
    }

    /// 新增方法：处理合同数据并返回分组，但不更新 UI
    private func processContractGroups(_ contracts: [ContractInfo]) async -> [ContractGroup] {
        if courierMode {
            // 快递模式
            return await groupContractsByRoute(contracts)
        } else {
            // 根据分组方式选择不同的分组逻辑
            switch groupingMode {
            case .byIssueDate:
                return groupContractsByIssueDate(contracts)
            case .byCompletionDate:
                return groupContractsByCompletionDate(contracts)
            }
        }
    }

    /// 按发起时间分组
    private func groupContractsByIssueDate(_ contracts: [ContractInfo]) -> [ContractGroup] {
        var groupedContracts: [Date: [ContractInfo]] = [:]
        for contract in contracts {
            let date = calendar.startOfDay(for: contract.date_issued)
            if groupedContracts[date] == nil {
                groupedContracts[date] = []
            }
            groupedContracts[date]?.append(contract)
        }

        // 创建分组并排序
        return groupedContracts.map { date, contracts in
            ContractGroup(
                date: date,
                contracts: contracts.sorted { $0.date_issued > $1.date_issued }
            )
        }.sorted { $0.date > $1.date }
    }

    /// 按完成时间分组
    private func groupContractsByCompletionDate(_ contracts: [ContractInfo]) -> [ContractGroup] {
        var result: [ContractGroup] = []

        // 第一组：未完成的合同（outstanding 和 in_progress）
        let incompleteContracts = contracts.filter { contract in
            contract.status == "outstanding" || contract.status == "in_progress"
        }.sorted { $0.contract_id > $1.contract_id }

        if !incompleteContracts.isEmpty {
            // 使用一个特殊的日期表示"未完成"分组
            result.append(ContractGroup(
                date: Date.distantFuture,
                contracts: incompleteContracts
            ))
        }

        // 其他已完成的合同按完成时间分组
        let completedContracts = contracts.filter { contract in
            contract.status != "outstanding" && contract.status != "in_progress"
        }

        var groupedContracts: [Date: [ContractInfo]] = [:]
        for contract in completedContracts {
            // 使用完成时间，如果没有完成时间则使用发起时间
            let date: Date
            if let completedDate = contract.date_completed {
                date = calendar.startOfDay(for: completedDate)
            } else {
                // 如果没有完成时间，使用发起时间
                date = calendar.startOfDay(for: contract.date_issued)
            }

            if groupedContracts[date] == nil {
                groupedContracts[date] = []
            }
            groupedContracts[date]?.append(contract)
        }

        // 创建已完成合同的分组并排序
        let completedGroups = groupedContracts.map { date, contracts in
            ContractGroup(
                date: date,
                contracts: contracts.sorted { $0.contract_id > $1.contract_id }
            )
        }.sorted { $0.date > $1.date }

        result.append(contentsOf: completedGroups)

        return result
    }
}
