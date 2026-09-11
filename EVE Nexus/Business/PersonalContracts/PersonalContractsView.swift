import SwiftUI

/// 根据合同状态返回对应的颜色
func contractStatusColor(_ status: String) -> Color {
    switch status {
    case "deleted":
        return .secondary
    case "rejected", "failed", "reversed":
        return .red
    case "outstanding", "in_progress":
        return .blue // 进行中和待处理状态显示为蓝色
    case "finished", "finished_issuer", "finished_contractor":
        return .green // 所有完成状态显示为绿色
    default:
        return .primary // 其他状态使用主色调
    }
}

/// 扩展Set以支持AppStorage
extension Set: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(Set<Element>.self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}

/// 按日期分组的合同
struct ContractGroup: Identifiable {
    let id = UUID()
    let date: Date
    var contracts: [ContractInfo]
    let startLocation: String?
    let endLocation: String?

    init(
        date: Date, contracts: [ContractInfo], startLocation: String? = nil,
        endLocation: String? = nil
    ) {
        self.date = date
        self.contracts = contracts
        self.startLocation = startLocation
        self.endLocation = endLocation
    }
}

struct PersonalContractsView: View {
    @StateObject private var viewModel: PersonalContractsViewModel
    @State private var showSettings = false

    // 新的过滤设置，使用Set来存储选中的类型和状态
    // 首次使用时默认全选，后续使用缓存值
    @AppStorage("") private var selectedContractTypes: Set<String> = []
    @AppStorage("") private var selectedContractStatuses: Set<String> = []
    @AppStorage("") private var maxContracts: Int = 300
    @AppStorage("") private var courierMode: Bool = false

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

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    init(character: EVECharacterInfo) {
        // 构造表达式内联在 autoclosure 中，避免父视图每次重渲染都新建 ViewModel；
        // 数据加载已在 ViewModel init 中启动
        _viewModel = StateObject(wrappedValue: PersonalContractsViewModel(
            characterId: character.CharacterID, character: character
        ))

        // 检查是否是首次使用（没有缓存）
        let typesKey = "selectedContractTypes_\(character.CharacterID)"
        let statusesKey = "selectedContractStatuses_\(character.CharacterID)"
        let hasTypesCache = UserDefaults.standard.object(forKey: typesKey) != nil
        let hasStatusesCache = UserDefaults.standard.object(forKey: statusesKey) != nil

        // 如果是首次使用，默认全选；否则使用缓存值
        let defaultTypes: Set<String> =
            hasTypesCache ? [] : Set(["courier", "item_exchange", "auction"])
        let defaultStatuses: Set<String> =
            hasStatusesCache
                ? []
                : Set([
                    "outstanding", "in_progress", "finished", "cancelled", "rejected", "failed",
                    "deleted", "reversed",
                ])

        // 初始化@AppStorage的key
        _selectedContractTypes = AppStorage(wrappedValue: defaultTypes, typesKey)
        _selectedContractStatuses = AppStorage(wrappedValue: defaultStatuses, statusesKey)
        _maxContracts = AppStorage(wrappedValue: 300, "maxContracts_\(character.CharacterID)")
        _courierMode = AppStorage(wrappedValue: false, "courierMode_\(character.CharacterID)")
    }

    /// 修改过滤逻辑
    private var filteredContractGroups: [ContractGroup] {
        if courierMode {
            // 快递模式：只显示未完成的快递合同
            let filteredGroups = viewModel.contractGroups.compactMap { group -> ContractGroup? in
                let filteredContracts = group.contracts.filter { contract in
                    contract.type == "courier" && contract.status == "outstanding"
                }.sorted { $0.reward > $1.reward } // 按照奖励金额从高到低排序

                return filteredContracts.isEmpty
                    ? nil
                    : ContractGroup(
                        date: group.date,
                        contracts: filteredContracts,
                        startLocation: group.startLocation,
                        endLocation: group.endLocation
                    )
            }
            // 按照组内第一个合同（最高奖励）的奖励金额排序
            return filteredGroups.sorted {
                $0.contracts[0].reward > $1.contracts[0].reward
            }
        } else {
            // 使用新的过滤逻辑
            let filteredGroups = viewModel.contractGroups.compactMap { group -> ContractGroup? in
                // 过滤每个组内的合同
                let filteredContracts = group.contracts.filter { contract in
                    // 根据选中的类型和状态过滤合同
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
                }

                // 如果过滤后该组没有合同，返回nil（这样compactMap会自动移除这个组）
                return filteredContracts.isEmpty
                    ? nil
                    : ContractGroup(
                        date: group.date,
                        contracts: filteredContracts,
                        startLocation: group.startLocation,
                        endLocation: group.endLocation
                    )
            }.sorted { $0.date > $1.date }

            // 计算所有合同的总数
            var totalContracts = 0
            var limitedGroups: [ContractGroup] = []
            // 遍历排序后的组，直到达到maxContracts个合同的限制
            for group in filteredGroups {
                let remainingSlots = maxContracts - totalContracts
                if remainingSlots <= 0 {
                    break
                }

                if totalContracts + group.contracts.count <= maxContracts {
                    // 如果添加整个组不会超过限制，直接添加
                    limitedGroups.append(group)
                    totalContracts += group.contracts.count
                } else {
                    // 如果添加整个组会超过限制，只添加部分合同
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
    }

    // MARK: - 状态判断

    /// 列表为空 + 正在加载：显示加载 overlay
    private var showsLoadingOverlay: Bool {
        filteredContractGroups.isEmpty && viewModel.isLoading
    }

    /// 列表为空 + 有错误 + 未在加载：显示错误 overlay
    private var showsErrorOverlay: Bool {
        filteredContractGroups.isEmpty
            && viewModel.errorMessage != nil
            && !viewModel.isLoading
    }

    /// 空状态文案：区分"无数据"和"无匹配筛选"
    private var emptyStateMessage: String {
        if !viewModel.contractGroups.isEmpty {
            // 有数据但被筛选过滤
            return NSLocalizedString("Misc_No_Matched_Data", comment: "")
        }
        // 完全无数据，按合同类型显示针对性提示
        switch viewModel.selectedContractType {
        case .personal:
            return NSLocalizedString("Contract_Empty_Personal", comment: "")
        case .corporation:
            return NSLocalizedString("Contract_Empty_Corporation", comment: "")
        case .alliance:
            return NSLocalizedString("Contract_Empty_Alliance", comment: "")
        }
    }

    // MARK: - Overlay 视图

    /// 加载状态 overlay：居中卡片式 loading，带文本描述和分页进度
    private var loadingOverlayView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)

            VStack(spacing: 6) {
                Text(
                    String(
                        format: NSLocalizedString("Contract_Loading_Type", comment: ""),
                        viewModel.selectedContractType.localizedName
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                if let currentPage = viewModel.currentLoadingPage {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Contract_Loading_Fetching", comment: ""
                            ), currentPage
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: NSLocalizedString("Contract_Loading_Type", comment: ""),
                viewModel.selectedContractType.localizedName
            )
        )
    }

    /// 错误状态 overlay：错误图标 + 描述 + 重试按钮
    private var errorOverlayView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.orange)

            VStack(spacing: 6) {
                Text(NSLocalizedString("Contract_Load_Error_Title", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Button {
                Task {
                    await viewModel.loadContractsData(forceRefresh: true)
                }
            } label: {
                Text(NSLocalizedString("ESI_Status_Retry", comment: ""))
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // 主列表：始终渲染，保证 .refreshable 在所有状态下都可用
                List {
                    // 顶部加载指示器（仅在有数据时显示，用于下拉刷新场景）
                    if !filteredContractGroups.isEmpty
                        && (viewModel.isLoading || viewModel.currentLoadingPage != nil)
                    {
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

                    ForEach(filteredContractGroups) { group in
                        Section {
                            ForEach(group.contracts) { contract in
                                ContractRow(
                                    contract: contract,
                                    contractType: viewModel.selectedContractType,
                                    databaseManager: viewModel.databaseManager,
                                    groupingMode: viewModel.groupingMode
                                )
                            }
                        } header: {
                            if courierMode {
                                if let start = group.startLocation, let end = group.endLocation {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Contract_Route_Format", comment: ""
                                            ), start, end
                                        )
                                    )
                                }
                            } else {
                                // 根据分组方式显示不同的标题
                                if viewModel.groupingMode == .byCompletionDate && group.date == Date.distantFuture {
                                    // 未完成分组
                                    Text(NSLocalizedString("Contract_Group_Incomplete", comment: ""))
                                } else if viewModel.groupingMode == .byIssueDate {
                                    // 按发起时间分组
                                    Text(NSLocalizedString("Contract_Group_Issued_On", comment: "") + " " + FormatUtil.formatDateToLocalDate(group.date))
                                } else {
                                    // 按完成时间分组
                                    Text(NSLocalizedString("Contract_Group_Completed_On", comment: "") + " " + FormatUtil.formatDateToLocalDate(group.date))
                                }
                            }
                        }
                    }

                    // 空状态提示（无数据且非加载中且无错误）：作为 List 行显示，不遮挡下拉刷新
                    if filteredContractGroups.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                        Section {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 44))
                                    .foregroundColor(.secondary)
                                Text(emptyStateMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    // 在刷新时重置加载状态
                    await MainActor.run {
                        viewModel.currentLoadingPage = nil
                    }
                    await viewModel.loadContractsData(forceRefresh: true)
                }

                // 状态 overlay：加载中（allowsHitTesting(false) 让下拉刷新穿透）
                if showsLoadingOverlay {
                    loadingOverlayView
                        .transition(.opacity)
                }

                // 状态 overlay：错误（保留交互以支持重试按钮）
                if showsErrorOverlay {
                    errorOverlayView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showsLoadingOverlay)
            .animation(.easeInOut(duration: 0.25), value: showsErrorOverlay)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if viewModel.hasCorporationAccess || viewModel.hasAllianceAccess {
                    VStack(spacing: 4) {
                        Picker("Contract Type", selection: $viewModel.selectedContractType) {
                            Text(NSLocalizedString("Contracts_Personal", comment: ""))
                                .tag(PersonalContractsViewModel.ContractType.personal)
                            if viewModel.hasCorporationAccess {
                                Text(NSLocalizedString("Contracts_Corporation", comment: ""))
                                    .tag(PersonalContractsViewModel.ContractType.corporation)
                            }
                            if viewModel.hasAllianceAccess {
                                Text(NSLocalizedString("Contracts_Alliance", comment: ""))
                                    .tag(PersonalContractsViewModel.ContractType.alliance)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        // 在加载过程中禁用 Picker
                        .disabled(viewModel.isLoading || viewModel.currentLoadingPage != nil)

                        // 价格筛选UI（仅在非快递模式下显示）
                        if !courierMode {
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
                        }

                        // 计算总合同数和过滤后的合同数
                        let totalCount = viewModel.contractGroups.reduce(0) { count, group in
                            count + group.contracts.count
                        }

                        if courierMode {
                            // 计算活跃的快递合同数量
                            let activeCourierCount = viewModel.contractGroups.reduce(0) {
                                count, group in
                                count
                                    + group.contracts.filter { contract in
                                        contract.type == "courier"
                                            && contract.status == "outstanding"
                                    }.count
                            }

                            let countText =
                                activeCourierCount > maxContracts
                                    ? String(
                                        format: NSLocalizedString(
                                            "Contract_Courier_Active_Count_Limited", comment: ""
                                        ),
                                        activeCourierCount, maxContracts
                                    )
                                    : String(
                                        format: NSLocalizedString(
                                            "Contract_Courier_Active_Count", comment: ""
                                        ),
                                        activeCourierCount
                                    )

                            (Text(
                                "(" + NSLocalizedString("Contract_Courier_Mode", comment: "") + ")"
                            ).foregroundColor(.red) + Text(" ")
                                + Text(countText).foregroundColor(.secondary))
                                .font(.caption)
                                .padding(.bottom, 4)
                        } else {
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
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section {
                        Toggle(
                            isOn: Binding(
                                get: { courierMode },
                                set: { newValue in
                                    courierMode = newValue
                                    viewModel.courierMode = newValue
                                }
                            )
                        ) {
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Contract_Courier_Mode", comment: ""))
                                Text(
                                    NSLocalizedString(
                                        "Contract_Courier_Mode_Description", comment: ""
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }

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

                    if !courierMode {
                        // 合同类型过滤
                        Section {
                            // 各个合同类型选项
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
                                        // 如果已全选，则清空
                                        selectedContractTypes = []
                                    } else {
                                        // 否则全选
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
                            // 各个合同状态选项
                            ForEach(allContractStatuses, id: \.self) { contractStatus in
                                Button(action: {
                                    if selectedContractStatuses.contains(contractStatus) {
                                        selectedContractStatuses.remove(contractStatus)
                                    } else {
                                        selectedContractStatuses.insert(contractStatus)
                                    }
                                }) {
                                    HStack {
                                        // 状态标签，类似合同列表中的显示
                                        Text(
                                            NSLocalizedString(
                                                "Contract_Status_\(contractStatus)", comment: ""
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundColor(contractStatusColor(contractStatus))
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
                                        // 如果已全选，则清空
                                        selectedContractStatuses = []
                                    } else {
                                        // 否则全选
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
        .navigationTitle(NSLocalizedString("Main_Contracts", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 分组方式选择器（仅在非快递模式下显示）
            if !courierMode {
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
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        // 修改onChange监听器，添加延迟加载机制
        .onChange(of: viewModel.selectedContractType) { oldValue, newValue in
            Logger.debug("合同类型切换: \(oldValue.localizedName) -> \(newValue.localizedName)")
            // 只有在类型真正变化时才加载数据
            if oldValue != newValue {
                // 使用单一任务加载数据，添加短暂延迟
                Task {
                    // 添加短暂延迟，避免在同一帧内多次更新
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒延迟
                    // 等待数据加载完成
                    await viewModel.loadContractsData(forceRefresh: false)
                }
            }
        }
    }

    /// 价格筛选检查方法
    private func checkPriceFilter(for contract: ContractInfo) -> Bool {
        // 如果没有设置价格筛选，则通过筛选
        if minPrice.isEmpty && maxPrice.isEmpty {
            return true
        }

        // 获取合同的价格值（根据合同类型决定使用price还是reward）
        let contractValue: Double
        switch contract.type {
        case "courier":
            contractValue = contract.reward
        case "item_exchange", "auction":
            contractValue = contract.price
        default:
            contractValue = contract.price
        }

        // 检查最低价格
        if !minPrice.isEmpty {
            if let minValue = Double(minPrice), contractValue < minValue {
                return false
            }
        }

        // 检查最高价格
        if !maxPrice.isEmpty {
            if let maxValue = Double(maxPrice), contractValue > maxValue {
                return false
            }
        }

        return true
    }
}
