import SwiftUI

@MainActor
final class CorporationIssuedContractsViewModel: ObservableObject {
    @Published var contractGroups: [ContractGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentLoadingPage: Int?

    /// 分组方式枚举（复用PersonalContractsViewModel的枚举）
    typealias GroupingMode = PersonalContractsViewModel.GroupingMode

    @Published var groupingMode: GroupingMode = .byIssueDate {
        didSet {
            UserDefaults.standard.set(groupingMode.rawValue, forKey: "corpIssuedGroupingMode_\(characterId)")
            Task {
                let groups = await processContractGroups(cachedContracts)
                await MainActor.run {
                    self.contractGroups = groups
                }
            }
        }
    }

    @Published var isInitialized = false

    private var cachedContracts: [ContractInfo] = []
    private var contractsInitialized = false
    let characterId: Int
    let character: EVECharacterInfo
    let databaseManager: DatabaseManager

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    init(characterId: Int, character: EVECharacterInfo) {
        self.characterId = characterId
        self.character = character
        databaseManager = DatabaseManager()

        if let groupingModeValue = UserDefaults.standard.value(
            forKey: "corpIssuedGroupingMode_\(characterId)"
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

    func loadContractsData(forceRefresh: Bool = false) async {
        // 如果已经在加载中且不是强制刷新，则直接返回
        if isLoading, !forceRefresh {
            return
        }

        // 如果已经加载过且不是强制刷新，且缓存不为空，直接使用缓存
        // 如果缓存为空，即使已初始化，也需要重新加载（可能是数据库缓存被清空）
        if !forceRefresh, contractsInitialized, !cachedContracts.isEmpty {
            await updateContractGroups(with: cachedContracts)
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
            currentLoadingPage = nil
            if !forceRefresh {
                contractGroups = []
            }
        }

        do {
            let contracts: [ContractInfo]
            let loadedContracts = try await Task.detached(priority: .userInitiated) {
                try await CorporationContractsAPI.shared.fetchMyCorpContracts(
                    characterId: self.characterId,
                    forceRefresh: forceRefresh,
                    progressCallback: { page in
                        Task { @MainActor in
                            self.currentLoadingPage = page
                        }
                    }
                )
            }.value
            contracts = loadedContracts

            // 更新缓存
            await MainActor.run {
                self.cachedContracts = contracts
                self.contractsInitialized = true
            }

            // 先处理数据，再一次性更新 UI
            let processedGroups = await processContractGroups(contracts)

            // 一次性更新所有 UI 状态
            await MainActor.run {
                self.contractGroups = processedGroups
                isLoading = false
                currentLoadingPage = nil
                isInitialized = true
            }
        } catch {
            // 记录错误，由视图展示错误页（带重试）
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                Logger.error("加载军团发起的合同失败: \(error)")
                self.isLoading = false
                self.currentLoadingPage = nil
            }
        }
    }

    private func updateContractGroups(with contracts: [ContractInfo]) async {
        let groups = await processContractGroups(contracts)
        await MainActor.run {
            self.contractGroups = groups
        }
    }

    /// 复用PersonalContractsViewModel的分组逻辑
    private func processContractGroups(_ contracts: [ContractInfo]) async -> [ContractGroup] {
        let groups: [ContractGroup]
        switch groupingMode {
        case .byIssueDate:
            groups = groupContractsByIssueDate(contracts)
        case .byCompletionDate:
            groups = groupContractsByCompletionDate(contracts)
        }
        return groups
    }

    /// 按发起时间分组（复用PersonalContractsViewModel的逻辑）
    private func groupContractsByIssueDate(_ contracts: [ContractInfo]) -> [ContractGroup] {
        var groupedContracts: [Date: [ContractInfo]] = [:]
        for contract in contracts {
            let date = calendar.startOfDay(for: contract.date_issued)
            if groupedContracts[date] == nil {
                groupedContracts[date] = []
            }
            groupedContracts[date]?.append(contract)
        }

        return groupedContracts.map { date, contracts in
            ContractGroup(
                date: date,
                contracts: contracts.sorted { $0.date_issued > $1.date_issued }
            )
        }.sorted { $0.date > $1.date }
    }

    /// 按完成时间分组（复用PersonalContractsViewModel的逻辑）
    private func groupContractsByCompletionDate(_ contracts: [ContractInfo]) -> [ContractGroup] {
        var result: [ContractGroup] = []

        let incompleteContracts = contracts.filter { contract in
            contract.status == "outstanding" || contract.status == "in_progress"
        }.sorted { $0.contract_id > $1.contract_id }

        if !incompleteContracts.isEmpty {
            result.append(ContractGroup(
                date: Date.distantFuture,
                contracts: incompleteContracts
            ))
        }

        let completedContracts = contracts.filter { contract in
            contract.status != "outstanding" && contract.status != "in_progress"
        }

        var groupedContracts: [Date: [ContractInfo]] = [:]
        for contract in completedContracts {
            let date: Date
            if let completedDate = contract.date_completed {
                date = calendar.startOfDay(for: completedDate)
            } else {
                date = calendar.startOfDay(for: contract.date_issued)
            }

            if groupedContracts[date] == nil {
                groupedContracts[date] = []
            }
            groupedContracts[date]?.append(contract)
        }

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

struct CorporationIssuedContractsView: View {
    @StateObject private var viewModel: CorporationIssuedContractsViewModel
    @State private var showSettings = false

    // 过滤设置（复用PersonalContractsView的逻辑）
    @AppStorage("") private var selectedContractTypes: Set<String> = []
    @AppStorage("") private var selectedContractStatuses: Set<String> = []
    @AppStorage("") private var maxContracts: Int = 300

    // 价格筛选
    @State private var minPrice: String = ""
    @State private var maxPrice: String = ""
    @State private var showPriceFilter = false

    // 定义所有可能的合同类型和状态
    private let allContractTypes = ["courier", "item_exchange", "auction"]
    private let allContractStatuses = [
        "outstanding", "in_progress", "finished", "cancelled", "rejected", "failed", "deleted",
        "reversed",
    ]

    init(character: EVECharacterInfo) {
        // 构造表达式内联在 autoclosure 中，避免父视图每次重渲染都新建 ViewModel；
        // 数据加载已在 ViewModel init 中启动
        _viewModel = StateObject(wrappedValue: CorporationIssuedContractsViewModel(
            characterId: character.CharacterID,
            character: character
        ))

        let typesKey = "corpIssuedSelectedContractTypes_\(character.CharacterID)"
        let statusesKey = "corpIssuedSelectedContractStatuses_\(character.CharacterID)"
        let hasTypesCache = UserDefaults.standard.object(forKey: typesKey) != nil
        let hasStatusesCache = UserDefaults.standard.object(forKey: statusesKey) != nil

        let defaultTypes: Set<String> =
            hasTypesCache ? [] : Set(["courier", "item_exchange", "auction"])
        let defaultStatuses: Set<String> =
            hasStatusesCache
                ? []
                : Set([
                    "outstanding", "in_progress", "finished", "cancelled", "rejected", "failed",
                    "deleted", "reversed",
                ])

        _selectedContractTypes = AppStorage(wrappedValue: defaultTypes, typesKey)
        _selectedContractStatuses = AppStorage(wrappedValue: defaultStatuses, statusesKey)
        _maxContracts = AppStorage(wrappedValue: 300, "corpIssuedMaxContracts_\(character.CharacterID)")
    }

    /// 过滤逻辑（完全复用PersonalContractsView的逻辑）
    private var filteredContractGroups: [ContractGroup] {
        let filteredGroups = viewModel.contractGroups.compactMap { group -> ContractGroup? in
            let filteredContracts = group.contracts.filter { contract in
                let typeMatches =
                    !selectedContractTypes.isEmpty
                        && selectedContractTypes.contains(contract.type)

                let normalizedStatus: String
                switch contract.status {
                case "finished", "finished_issuer", "finished_contractor":
                    normalizedStatus = "finished"
                default:
                    normalizedStatus = contract.status
                }
                let statusMatches =
                    !selectedContractStatuses.isEmpty
                        && selectedContractStatuses.contains(normalizedStatus)

                let priceMatches = checkPriceFilter(for: contract)

                return typeMatches && statusMatches && priceMatches
            }

            return filteredContracts.isEmpty
                ? nil
                : ContractGroup(
                    date: group.date,
                    contracts: filteredContracts,
                    startLocation: group.startLocation,
                    endLocation: group.endLocation
                )
        }.sorted { $0.date > $1.date }

        var totalContracts = 0
        var limitedGroups: [ContractGroup] = []
        for group in filteredGroups {
            let remainingSlots = maxContracts - totalContracts
            if remainingSlots <= 0 {
                break
            }

            if totalContracts + group.contracts.count <= maxContracts {
                limitedGroups.append(group)
                totalContracts += group.contracts.count
            } else {
                let limitedContracts = Array(group.contracts.prefix(remainingSlots))
                limitedGroups.append(
                    ContractGroup(
                        date: group.date,
                        contracts: limitedContracts,
                        startLocation: group.startLocation,
                        endLocation: group.endLocation
                    )
                )
                break
            }
        }

        return limitedGroups
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if viewModel.isLoading || viewModel.currentLoadingPage != nil {
                    Section {
                        HStack {
                            Spacer()
                            if let currentPage = viewModel.currentLoadingPage {
                                let text = String(
                                    format: NSLocalizedString(
                                        "Contract_Loading_Fetching", comment: "正在获取第 %d 页数据"
                                    ), currentPage
                                )

                                Text(text)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                // 显示错误信息
                if let error = viewModel.errorMessage,
                   !viewModel.isLoading && viewModel.contractGroups.isEmpty
                {
                    ErrorStateSection(message: error) {
                        Task {
                            await viewModel.loadContractsData(forceRefresh: true)
                        }
                    }
                } else if filteredContractGroups.isEmpty && !viewModel.isLoading {
                    NoDataSection(
                        icon: "line.3.horizontal.decrease.circle",
                        text: NSLocalizedString("Misc_No_Matched_Data", comment: "")
                    )
                } else if !viewModel.isLoading || viewModel.isInitialized {
                    ForEach(filteredContractGroups) { group in
                        Section {
                            ForEach(group.contracts) { contract in
                                CorporationIssuedContractRow(
                                    contract: contract,
                                    databaseManager: viewModel.databaseManager,
                                    groupingMode: viewModel.groupingMode
                                )
                                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            }
                        } header: {
                            if viewModel.groupingMode == .byCompletionDate && group.date == Date.distantFuture {
                                Text(NSLocalizedString("Contract_Group_Incomplete", comment: ""))
                            } else if viewModel.groupingMode == .byIssueDate {
                                Text(NSLocalizedString("Contract_Group_Issued_On", comment: "") + " " + FormatUtil.formatDateToLocalDate(group.date))
                            } else {
                                Text(NSLocalizedString("Contract_Group_Completed_On", comment: "") + " " + FormatUtil.formatDateToLocalDate(group.date))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await MainActor.run {
                    viewModel.currentLoadingPage = nil
                }
                await viewModel.loadContractsData(forceRefresh: true)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    // 价格筛选UI（复用PersonalContractsView的设计，移除picker）
                    VStack(spacing: 0) {
                        // 分隔线
                        Divider()
                            .padding(.horizontal)

                        // 价格筛选Section
                        VStack(spacing: 12) {
                            // 标题行 - 整行可点击
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showPriceFilter.toggle()
                                }
                            }) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "dollarsign.circle")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 16))
                                        Text(
                                            NSLocalizedString(
                                                "Contract_Price_Filter", comment: ""
                                            )
                                        )
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    }

                                    Spacer()

                                    HStack(spacing: 12) {
                                        // 清除按钮（如果有筛选条件）
                                        if !minPrice.isEmpty || !maxPrice.isEmpty {
                                            Button(action: {
                                                minPrice = ""
                                                maxPrice = ""
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.caption)
                                                    Text(
                                                        NSLocalizedString(
                                                            "Contract_Price_Clear",
                                                            comment: ""
                                                        )
                                                    )
                                                    .font(.caption)
                                                }
                                                .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        // 展开/收起图标
                                        Image(
                                            systemName: showPriceFilter
                                                ? "chevron.up" : "chevron.down"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .contentShape(Rectangle()) // 让整行都可点击
                            }
                            .buttonStyle(.plain)

                            // 输入框区域（展开时显示）
                            if showPriceFilter {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 4) {
                                            Label(
                                                NSLocalizedString(
                                                    "Contract_Price_Min", comment: ""
                                                ),
                                                systemImage: "arrow.down.circle"
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                            if !minPrice.isEmpty,
                                               let value = Double(minPrice), value > 0
                                            {
                                                Text("(\(FormatUtil.formatForUI(value)))")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                        }

                                        TextField("0", text: $minPrice)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.body)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 4) {
                                            Label(
                                                NSLocalizedString(
                                                    "Contract_Price_Max", comment: ""
                                                ),
                                                systemImage: "arrow.up.circle"
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                            if !maxPrice.isEmpty,
                                               let value = Double(maxPrice), value > 0
                                            {
                                                Text("(\(FormatUtil.formatForUI(value)))")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                        }

                                        TextField("∞", text: $maxPrice)
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.body)
                                    }
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(
                                            with: .move(edge: .top)
                                        ),
                                        removal: .opacity.combined(with: .move(edge: .top))
                                    )
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // 计算总合同数和过滤后的合同数
                    let totalCount = viewModel.contractGroups.reduce(0) { count, group in
                        count + group.contracts.count
                    }

                    let filteredCount = viewModel.contractGroups.reduce(0) { count, group in
                        count
                            + group.contracts.filter { contract in
                                // 如果没有选中任何类型，则不显示任何合同
                                let typeMatches =
                                    !selectedContractTypes.isEmpty
                                        && selectedContractTypes.contains(contract.type)
                                // 将所有finished相关状态统一为"finished"
                                let normalizedStatus: String
                                switch contract.status {
                                case "finished", "finished_issuer", "finished_contractor":
                                    normalizedStatus = "finished"
                                default:
                                    normalizedStatus = contract.status
                                }
                                // 如果没有选中任何状态，则不显示任何合同
                                let statusMatches =
                                    !selectedContractStatuses.isEmpty
                                        && selectedContractStatuses.contains(normalizedStatus)
                                // 价格筛选
                                let priceMatches = checkPriceFilter(for: contract)
                                return typeMatches && statusMatches && priceMatches
                            }.count
                    }

                    if filteredCount > maxContracts {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Contract_Filtered_Limited", comment: ""
                                ), totalCount,
                                filteredCount, maxContracts
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    } else if filteredCount < totalCount {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Contract_Filtered_Count", comment: ""
                                ), totalCount,
                                filteredCount
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    } else {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Contract_Total_Count", comment: ""
                                ), totalCount
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section {
                        Picker(
                            NSLocalizedString("Contract_Max_Display", comment: ""),
                            selection: $maxContracts
                        ) {
                            Text(NSLocalizedString("Contract_Display_50", comment: "")).tag(50)
                            Text(NSLocalizedString("Contract_Display_100", comment: "")).tag(100)
                            Text(NSLocalizedString("Contract_Display_300", comment: "")).tag(300)
                            Text(NSLocalizedString("Contract_Display_500", comment: "")).tag(500)
                            Text(NSLocalizedString("Contract_Display_Unlimited", comment: "")).tag(
                                Int.max
                            )
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text(NSLocalizedString("Contract_Display_Limit", comment: ""))
                    } footer: {
                        Text(NSLocalizedString("Contract_Display_Limit_Warning", comment: ""))
                    }

                    // 合同类型过滤
                    Section {
                        ForEach(allContractTypes, id: \.self) { contractType in
                            Button(action: {
                                if selectedContractTypes.contains(contractType) {
                                    selectedContractTypes.remove(contractType)
                                } else {
                                    selectedContractTypes.insert(contractType)
                                }
                            }) {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Contract_Type_\(contractType)", comment: ""
                                        )
                                    )
                                    .foregroundColor(.primary)
                                    Spacer()
                                    if selectedContractTypes.contains(contractType) {
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
                            Text(NSLocalizedString("Contract_Type_Filter", comment: ""))
                            Spacer()
                            Button(action: {
                                if selectedContractTypes.count == allContractTypes.count {
                                    selectedContractTypes = []
                                } else {
                                    selectedContractTypes = Set(allContractTypes)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Contract_Show_All_Status", comment: ""
                                        )
                                    )
                                    .font(.caption)
                                    if selectedContractTypes.count == allContractTypes.count {
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
                    } footer: {
                        if selectedContractTypes.isEmpty {
                            Text(NSLocalizedString("Contract_Select1", comment: ""))
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }

                    // 合同状态过滤
                    Section {
                        ForEach(allContractStatuses, id: \.self) { contractStatus in
                            Button(action: {
                                if selectedContractStatuses.contains(contractStatus) {
                                    selectedContractStatuses.remove(contractStatus)
                                } else {
                                    selectedContractStatuses.insert(contractStatus)
                                }
                            }) {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Contract_Status_\(contractStatus)", comment: ""
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(getStatusColor(contractStatus))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.2))
                                    )

                                    Spacer()

                                    if selectedContractStatuses.contains(contractStatus) {
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
                            Text(NSLocalizedString("Contract_Status_Filter", comment: ""))
                            Spacer()
                            Button(action: {
                                if selectedContractStatuses.count == allContractStatuses.count {
                                    selectedContractStatuses = []
                                } else {
                                    selectedContractStatuses = Set(allContractStatuses)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Contract_Show_All_Status", comment: ""
                                        )
                                    )
                                    .font(.caption)
                                    if selectedContractStatuses.count
                                        == allContractStatuses.count
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
                    } footer: {
                        if selectedContractStatuses.isEmpty {
                            Text(NSLocalizedString("Contract_Select1", comment: ""))
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                .navigationTitle(NSLocalizedString("Contract_Settings", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("Contract_Done", comment: "")) {
                            showSettings = false
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Contract_Corporation_Issued", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(PersonalContractsViewModel.GroupingMode.allCases, id: \.self) { mode in
                        Button {
                            viewModel.groupingMode = mode
                        } label: {
                            HStack {
                                Label(mode.localizedName, systemImage: mode == .byIssueDate ? "calendar.badge.plus" : "calendar.badge.checkmark")
                                if viewModel.groupingMode == mode {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
    }

    /// 价格筛选检查方法（复用PersonalContractsView的逻辑）
    private func checkPriceFilter(for contract: ContractInfo) -> Bool {
        if minPrice.isEmpty && maxPrice.isEmpty {
            return true
        }

        let contractValue: Double
        switch contract.type {
        case "courier":
            contractValue = contract.reward
        case "item_exchange", "auction":
            contractValue = contract.price
        default:
            contractValue = contract.price
        }

        if !minPrice.isEmpty {
            if let minValue = Double(minPrice), contractValue < minValue {
                return false
            }
        }

        if !maxPrice.isEmpty {
            if let maxValue = Double(maxPrice), contractValue > maxValue {
                return false
            }
        }

        return true
    }

    /// 根据状态返回对应的颜色（复用PersonalContractsView的逻辑）
    private func getStatusColor(_ status: String) -> Color {
        switch status {
        case "deleted":
            return .secondary
        case "rejected", "failed", "reversed":
            return .red
        case "outstanding", "in_progress":
            return .blue
        case "finished", "finished_issuer", "finished_contractor":
            return .green
        default:
            return .primary
        }
    }
}

/// 专门用于公司发起合同的 ContractRow，price 始终显示为绿色正号
struct CorporationIssuedContractRow: View {
    let contract: ContractInfo
    let databaseManager: DatabaseManager
    let groupingMode: PersonalContractsViewModel.GroupingMode
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0

    private func formatContractType(_ type: String) -> String {
        return NSLocalizedString("Contract_Type_\(type)", comment: "")
    }

    private func formatContractStatus(_ status: String) -> String {
        let normalizedStatus: String
        switch status {
        case "finished", "finished_issuer", "finished_contractor":
            normalizedStatus = "finished"
        default:
            normalizedStatus = status
        }
        return NSLocalizedString("Contract_Status_\(normalizedStatus)", comment: "")
    }

    private func getStatusColor(_ status: String) -> Color {
        switch status {
        case "deleted":
            return .secondary
        case "rejected", "failed", "reversed":
            return .red
        case "outstanding", "in_progress":
            return .blue
        case "finished", "finished_issuer", "finished_contractor":
            return .green
        default:
            return .primary
        }
    }

    @ViewBuilder
    private func priceView() -> some View {
        let hasPrice = contract.price > 0
        let hasReward = contract.reward > 0

        // 如果两个字段都有数值，则都显示
        if hasPrice && hasReward {
            HStack(spacing: 8) {
                // 显示 price（根据合同类型决定颜色和符号）
                priceText(
                    value: contract.price,
                    isPrice: true,
                    contractType: contract.type
                )
                // 显示 reward（根据合同类型决定颜色和符号）
                rewardText(
                    value: contract.reward,
                    contractType: contract.type
                )
            }
        } else if !hasPrice && hasReward {
            // 如果 price 为 0 但 reward > 0，显示 reward
            rewardText(
                value: contract.reward,
                contractType: contract.type
            )
        } else if hasPrice {
            // 如果只有 price 有值，按逻辑显示
            priceText(
                value: contract.price,
                isPrice: true,
                contractType: contract.type
            )
        } else {
            // 如果两个都为0，按合同类型显示
            switch contract.type {
            case "item_exchange":
                // 物品交换合同：公司发起，price 是收入（绿色正号）
                Text("+\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.green)
                    .font(.system(.caption, design: .monospaced))
            case "courier":
                // 快递合同：公司发起，reward 是支出（红色负号）
                Text("-\(FormatUtil.format(contract.reward)) ISK")
                    .foregroundColor(.red)
                    .font(.system(.caption, design: .monospaced))
            case "auction":
                // 拍卖合同：公司发起，price 是收入（绿色正号）
                Text("+\(FormatUtil.format(contract.price)) ISK")
                    .foregroundColor(.green)
                    .font(.system(.caption, design: .monospaced))
            default:
                Text("\(FormatUtil.format(0)) ISK")
                    .foregroundColor(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    /// 辅助方法：根据合同类型生成价格文本（从公司发起人视角）
    @ViewBuilder
    private func priceText(
        value: Double, isPrice _: Bool, contractType: String
    ) -> some View {
        switch contractType {
        case "item_exchange":
            // 物品交换合同：公司发起，price 是收入（绿色正号）
            Text("+\(FormatUtil.format(value)) ISK")
                .foregroundColor(.green)
                .font(.system(.caption, design: .monospaced))
        case "auction":
            // 拍卖合同：公司发起，price 是收入（绿色正号）
            Text("+\(FormatUtil.format(value)) ISK")
                .foregroundColor(.green)
                .font(.system(.caption, design: .monospaced))
        default:
            Text("\(FormatUtil.format(value)) ISK")
                .foregroundColor(.secondary)
                .font(.system(.caption, design: .monospaced))
        }
    }

    /// 辅助方法：根据合同类型生成奖励文本（从公司发起人视角）
    @ViewBuilder
    private func rewardText(
        value: Double, contractType: String
    ) -> some View {
        switch contractType {
        case "courier":
            // 快递合同：公司发起，reward 是支出（红色负号）
            Text("-\(FormatUtil.format(value)) ISK")
                .foregroundColor(.red)
                .font(.system(.caption, design: .monospaced))
        default:
            // 其他合同：reward 显示为绿色正号
            Text("+\(FormatUtil.format(value)) ISK")
                .foregroundColor(.green)
                .font(.system(.caption, design: .monospaced))
        }
    }

    var body: some View {
        NavigationLink {
            ContractDetailView(
                characterId: currentCharacterId,
                contract: contract,
                databaseManager: databaseManager,
                contractType: .corporation
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if DeviceUtils.shouldUseCompactLayout {
                    HStack {
                        Text(formatContractStatus(contract.status))
                            .font(.caption)
                            .foregroundColor(getStatusColor(contract.status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                            )
                        Text(formatContractType(contract.type))
                            .font(.body)
                            .lineLimit(1)
                        Spacer()
                        priceView()
                    }

                    HStack {
                        Text(
                            NSLocalizedString("Contract_Title", comment: "") + ": "
                                + (contract.title.isEmpty
                                    ? "[\(NSLocalizedString("Contract_No_Title", comment: ""))]"
                                    : contract.title)
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                        Spacer()
                    }
                } else {
                    HStack {
                        Text(formatContractType(contract.type))
                            .font(.body)
                            .lineLimit(1)

                        Spacer()

                        Text(formatContractStatus(contract.status))
                            .font(.caption)
                            .foregroundColor(getStatusColor(contract.status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                            )
                    }

                    HStack {
                        Text(
                            NSLocalizedString("Contract_Title", comment: "") + ": "
                                + (contract.title.isEmpty
                                    ? "[\(NSLocalizedString("Contract_No_Title", comment: ""))]"
                                    : contract.title)
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                        Spacer()

                        priceView()
                    }
                }
                HStack {
                    Text(
                        NSLocalizedString("Contract_Volume", comment: "")
                            + ": \(FormatUtil.format(contract.volume)) m³"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    Spacer()

                    if groupingMode == .byIssueDate {
                        if contract.status == "outstanding" {
                            let remainingDays =
                                Calendar.current.dateComponents(
                                    [.day],
                                    from: Date(),
                                    to: contract.date_expired
                                ).day ?? 0

                            if remainingDays > 0 {
                                Text(
                                    "\(FormatUtil.formatDateToLocalTime(contract.date_issued)) (\(String.localizedStringWithFormat(NSLocalizedString("Contract_Days_Remaining", comment: ""), remainingDays)))"
                                )
                                .font(.caption)
                                .foregroundColor(.gray)
                            } else if remainingDays == 0 {
                                Text(
                                    "\(FormatUtil.formatDateToLocalTime(contract.date_issued)) (\(NSLocalizedString("Contract_Expires_Today", comment: "")))"
                                )
                                .font(.caption)
                                .foregroundColor(.orange)
                            } else {
                                Text(
                                    "\(FormatUtil.formatDateToLocalTime(contract.date_issued)) (\(NSLocalizedString("Contract_Expired", comment: "")))"
                                )
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        } else {
                            Text("\(FormatUtil.formatDateToLocalTime(contract.date_issued))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        if contract.status == "outstanding" || contract.status == "in_progress" {
                            if contract.status == "outstanding" {
                                let remainingDays =
                                    Calendar.current.dateComponents(
                                        [.day],
                                        from: Date(),
                                        to: contract.date_expired
                                    ).day ?? 0

                                if remainingDays > 0 {
                                    Text(String.localizedStringWithFormat(NSLocalizedString("Contract_Days_Remaining_Full", comment: ""), remainingDays))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else if remainingDays == 0 {
                                    Text(NSLocalizedString("Contract_Expires_Today", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else {
                                    Text(NSLocalizedString("Contract_Expired", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            } else {
                                Text(NSLocalizedString("Contract_Status_in_progress", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            if let completedDate = contract.date_completed {
                                Text("\(FormatUtil.formatDateToLocalTime(completedDate))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            } else {
                                Text("\(FormatUtil.formatDateToLocalTime(contract.date_issued))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .contextMenu {
                if !contract.title.isEmpty {
                    Button {
                        UIPasteboard.general.string = contract.title
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Contract_Title", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }
                }
            }
        }
    }
}
