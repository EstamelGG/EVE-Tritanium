import SwiftUI

/// 钱包流水条目模型
struct WalletJournalEntry: Codable, Identifiable {
    let id: Int64
    let amount: Double
    let balance: Double
    let date: String
    let description: String
    let first_party_id: Int
    let reason: String
    let ref_type: String
    let second_party_id: Int
    let context_id: Int64?
    let context_id_type: String?
}

/// 按日期分组的钱包流水
struct WalletJournalGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [WalletJournalEntry]
}

@MainActor
final class WalletJournalViewModel: ObservableObject {
    @Published private(set) var journalGroups: [WalletJournalGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var totalIncome: Double = 0.0
    @Published private(set) var totalExpense: Double = 0.0
    @Published var timeRange: TimeRange = .last30Days
    @Published var selectedRefTypes: Set<String> = []
    @Published var selectedTransactionTypes: Set<TransactionType> = []
    @Published var showFilterSheet = false
    @Published private(set) var totalEntries: Int = 0
    @Published private(set) var isPartialData: Bool = false
    private var loadingTask: Task<Void, Never>?
    private var initialLoadDone = false

    enum TransactionType {
        case income
        case expense

        var localizedString: String {
            switch self {
            case .income:
                return NSLocalizedString("Wallet_Income", comment: "")
            case .expense:
                return NSLocalizedString("Wallet_Expense", comment: "")
            }
        }
    }

    enum TimeRange: String, CaseIterable {
        case last30Days
        case last7Days
        case last1Day

        var localizedString: String {
            switch self {
            case .last30Days:
                return String.localizedStringWithFormat(NSLocalizedString("Time_Days_Long", comment: ""), 30)
            case .last7Days:
                return String.localizedStringWithFormat(NSLocalizedString("Time_Days_Long", comment: ""), 7)
            case .last1Day:
                return String.localizedStringWithFormat(NSLocalizedString("Time_Days_Long", comment: ""), 1)
            }
        }
    }

    private let characterId: Int

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current // 使用本地时区
        return calendar
    }()

    init(characterId: Int) {
        self.characterId = characterId

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadJournalData()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    /// 计算总收支
    private func calculateTotals(from entries: [WalletJournalEntry]) {
        var income: Double = 0
        var expense: Double = 0

        let calendar = Calendar.current
        let now = Date()
        let startDate: Date

        switch timeRange {
        case .last30Days:
            startDate = calendar.date(byAdding: .day, value: -30, to: now)!
        case .last7Days:
            startDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .last1Day:
            startDate = calendar.date(byAdding: .day, value: -1, to: now)!
        }

        for entry in entries {
            guard let entryDate = FormatUtil.parseUTCDate(entry.date),
                  entryDate >= startDate
            else {
                continue
            }

            if entry.amount > 0 {
                income += entry.amount
            } else {
                expense += abs(entry.amount)
            }
        }

        totalIncome = income
        totalExpense = expense
    }

    /// 只更新总收支
    func updateTotals() {
        let allEntries = journalGroups.flatMap { $0.entries }
        calculateTotals(from: allEntries)
    }

    func loadJournalData(forceRefresh: Bool = false) async {
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
                guard
                    let jsonString = try await CharacterWalletAPI.shared.getWalletJournal(
                        characterId: characterId, forceRefresh: forceRefresh
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                guard let jsonData = jsonString.data(using: .utf8),
                      let entries = try? JSONDecoder().decode(
                          [WalletJournalEntry].self, from: jsonData
                      )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled { return }

                // 检查数据量
                totalEntries = entries.count

                // 检查是否只显示部分数据
                if totalEntries >= 9500 {
                    // 获取最久远的记录日期
                    if let oldestEntry = entries.min(by: { $0.date < $1.date }),
                       let oldestDate = FormatUtil.parseUTCDate(oldestEntry.date)
                    {
                        let calendar = Calendar.current
                        let now = Date()
                        let days =
                            calendar.dateComponents([.day], from: oldestDate, to: now).day ?? 0
                        isPartialData = days < 30
                    }
                }

                // 计算总收支
                calculateTotals(from: entries)

                var groupedEntries: [Date: [WalletJournalEntry]] = [:]
                for entry in entries {
                    guard let date = FormatUtil.parseUTCDate(entry.date) else {
                        Logger.error("Failed to parse date: \(entry.date)")
                        continue
                    }

                    let components = calendar.dateComponents([.year, .month, .day], from: date)
                    guard let dayDate = calendar.date(from: components) else {
                        Logger.error("Failed to create date from components for: \(entry.date)")
                        continue
                    }

                    groupedEntries[dayDate, default: []].append(entry)
                }

                if Task.isCancelled { return }

                let groups = groupedEntries.map { date, entries -> WalletJournalGroup in
                    WalletJournalGroup(date: date, entries: entries.sorted { $0.id > $1.id })
                }.sorted { $0.date > $1.date }

                await MainActor.run {
                    self.journalGroups = groups
                    self.isLoading = false
                    let wasFirstLoad = !self.initialLoadDone
                    self.initialLoadDone = true

                    // 首次加载时，如果过滤器为空，自动选中所有选项
                    if wasFirstLoad {
                        let availableTypes = self.availableRefTypes
                        if self.selectedRefTypes.isEmpty, !availableTypes.isEmpty {
                            self.selectedRefTypes = Set(availableTypes)
                        }
                        if self.selectedTransactionTypes.isEmpty {
                            self.selectedTransactionTypes = [.income, .expense]
                        }
                    }
                }

            } catch {
                Logger.error("加载钱包流水失败: \(error.localizedDescription)")
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

    /// 获取所有可用的 ref_type，按交易次数排序
    var availableRefTypes: [String] {
        let allTypes = journalGroups.flatMap { $0.entries }.map { $0.ref_type }

        // 统计每个 ref_type 的出现次数
        var typeCounts: [String: Int] = [:]
        for refType in allTypes {
            typeCounts[refType, default: 0] += 1
        }

        // 按交易次数从高到低排序，如果次数相同则按字母顺序排序
        let uniqueTypes = Array(Set(allTypes))
        return uniqueTypes.sorted { type1, type2 in
            let count1 = typeCounts[type1] ?? 0
            let count2 = typeCounts[type2] ?? 0
            if count1 != count2 {
                return count1 > count2 // 次数多的在前
            }
            return type1 < type2 // 次数相同时按字母顺序
        }
    }

    /// 获取过滤后的日志组
    var filteredJournalGroups: [WalletJournalGroup] {
        return journalGroups.map { group in
            let filteredEntries = group.entries.filter { entry in
                // 首先检查交易类型（收入/支出）
                if !selectedTransactionTypes.isEmpty {
                    var matches = false
                    // 收入：amount > 0 或 amount == 0（0值交易默认视为收入）
                    if selectedTransactionTypes.contains(.income), entry.amount >= 0 {
                        matches = true
                    }
                    // 支出：amount < 0
                    if selectedTransactionTypes.contains(.expense), entry.amount < 0 {
                        matches = true
                    }
                    if !matches { return false }
                }

                // 然后检查 ref_type
                if !selectedRefTypes.isEmpty {
                    if !selectedRefTypes.contains(entry.ref_type) { return false }
                }

                return true
            }
            return WalletJournalGroup(date: group.date, entries: filteredEntries)
        }.filter { !$0.entries.isEmpty }
    }
}

/// 特定日期的钱包流水详情视图
struct WalletJournalDayDetailView: View {
    let group: WalletJournalGroup
    @State private var displayedEntries: [WalletJournalEntry] = []
    @State private var showingCount = 100

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    var body: some View {
        List {
            ForEach(displayedEntries, id: \.id) { entry in
                WalletJournalEntryRow(entry: entry)
            }

            if showingCount < group.entries.count {
                Button(action: {
                    loadMoreEntries()
                }) {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Load More", comment: ""))
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(FormatUtil.formatDateToLocalDate(group.date))
        .onAppear {
            // 初始加载前100条
            loadMoreEntries()
        }
    }

    private func loadMoreEntries() {
        let nextBatch = min(showingCount + 100, group.entries.count)
        displayedEntries = Array(group.entries.prefix(nextBatch))
        showingCount = nextBatch
    }
}

struct WalletJournalView: View {
    @StateObject private var viewModel: WalletJournalViewModel

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: WalletJournalViewModel(characterId: characterId))
    }

    var summarySection: some View {
        Section(
            header: HStack {
                Text(NSLocalizedString("Summary", comment: ""))
                Spacer()
                Button(action: {
                    switch viewModel.timeRange {
                    case .last30Days:
                        viewModel.timeRange = .last7Days
                    case .last7Days:
                        viewModel.timeRange = .last1Day
                    case .last1Day:
                        viewModel.timeRange = .last30Days
                    }
                    viewModel.updateTotals()
                }) {
                    Text(viewModel.timeRange.localizedString)
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
            }
        ) {
            // 总收入
            HStack {
                Text(NSLocalizedString("Total Income", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                Text(
                    "\(viewModel.totalIncome > 0 ? "+" : "")\(FormatUtil.format(viewModel.totalIncome, false)) ISK"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(viewModel.totalIncome > 0 ? .green : .secondary)
            }

            // 总支出
            HStack {
                Text(NSLocalizedString("Total Expense", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                Text(
                    "\(viewModel.totalExpense > 0 ? "-" : "")\(FormatUtil.format(viewModel.totalExpense, false)) ISK"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(viewModel.totalExpense > 0 ? .red : .secondary)
            }

            // 净收益
            HStack {
                Text(NSLocalizedString("Net Income", comment: ""))
                    .font(.system(size: 14))
                Spacer()
                let netIncome = viewModel.totalIncome - viewModel.totalExpense
                Text("\(FormatUtil.format(netIncome, false)) ISK")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(netIncome > 0 ? .green : netIncome < 0 ? .red : .secondary)
            }
        }
    }

    private func formatRefType(_ refType: String) -> String {
        let lowercaseRefType = refType.lowercased()

        return LocalizationManager.shared.processEntryTypeName(
            for: lowercaseRefType, esiText: refType, language: LocalizationManager.currentLanguageCode
        )
    }

    /// 添加过滤视图组件
    private var filterView: some View {
        NavigationView {
            List {
                Section(
                    header: HStack {
                        Text(NSLocalizedString("Wallet_Transaction_Type", comment: ""))
                        Spacer()
                        Button(action: {
                            let allTypes: Set<WalletJournalViewModel.TransactionType> = [.income, .expense]
                            if viewModel.selectedTransactionTypes.count == allTypes.count {
                                viewModel.selectedTransactionTypes = []
                            } else {
                                viewModel.selectedTransactionTypes = allTypes
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: "全选"))
                                    .font(.caption)
                                if viewModel.selectedTransactionTypes.count == 2 {
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
                ) {
                    Button(action: {
                        if viewModel.selectedTransactionTypes.contains(.income) {
                            viewModel.selectedTransactionTypes.remove(.income)
                        } else {
                            viewModel.selectedTransactionTypes.insert(.income)
                        }
                    }) {
                        HStack {
                            Text(WalletJournalViewModel.TransactionType.income.localizedString)
                                .foregroundColor(.primary)
                            Spacer()
                            if viewModel.selectedTransactionTypes.contains(.income) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        if viewModel.selectedTransactionTypes.contains(.expense) {
                            viewModel.selectedTransactionTypes.remove(.expense)
                        } else {
                            viewModel.selectedTransactionTypes.insert(.expense)
                        }
                    }) {
                        HStack {
                            Text(WalletJournalViewModel.TransactionType.expense.localizedString)
                                .foregroundColor(.primary)
                            Spacer()
                            if viewModel.selectedTransactionTypes.contains(.expense) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Section(
                    header: HStack {
                        Text(NSLocalizedString("Wallet_Transaction_Category", comment: ""))
                        Spacer()
                        Button(action: {
                            let allRefTypes = Set(viewModel.availableRefTypes)
                            if viewModel.selectedRefTypes.count == allRefTypes.count {
                                viewModel.selectedRefTypes = []
                            } else {
                                viewModel.selectedRefTypes = allRefTypes
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: "全选"))
                                    .font(.caption)
                                if viewModel.selectedRefTypes.count == viewModel.availableRefTypes.count,
                                   !viewModel.availableRefTypes.isEmpty
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
                    },
                    footer: Text(NSLocalizedString("Wallet_Journal_Sorted_By_Count", comment: "根据流水条目数排序"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                ) {
                    ForEach(viewModel.availableRefTypes, id: \.self) { refType in
                        Button(action: {
                            if viewModel.selectedRefTypes.contains(refType) {
                                viewModel.selectedRefTypes.remove(refType)
                            } else {
                                viewModel.selectedRefTypes.insert(refType)
                            }
                        }) {
                            HStack {
                                Text(formatRefType(refType))
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedRefTypes.contains(refType) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Misc_Filter", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        viewModel.showFilterSheet = false
                    }
                }
            }
        }
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                WalletJournalSkeleton()
            } else if viewModel.journalGroups.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                summarySection

                if viewModel.filteredJournalGroups.isEmpty {
                    Section {
                        NoDataSection()
                    }
                } else {
                    Section(
                        header: Text(NSLocalizedString("Transaction Dates", comment: ""))
                    ) {
                        ForEach(viewModel.filteredJournalGroups) { group in
                            NavigationLink(destination: WalletJournalDayDetailView(group: group)) {
                                let dayIncome = group.entries
                                    .filter { $0.amount > 0 }
                                    .reduce(0.0) { $0 + $1.amount }
                                let dayExpense = group.entries
                                    .filter { $0.amount < 0 }
                                    .reduce(0.0) { $0 - $1.amount }
                                let dayNetIncome = dayIncome - dayExpense

                                HStack {
                                    // 左侧：日期、交易数和当日净收益垂直排列
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(FormatUtil.formatDateToLocalDate(group.date))
                                            .font(.system(size: 16))

                                        HStack(spacing: 4) {
                                            Text(
                                                "\(group.entries.count) \(NSLocalizedString("transactions", comment: ""))"
                                            )
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                            Text(
                                                "\(dayNetIncome >= 0 ? "+" : "")\(FormatUtil.formatISK(dayNetIncome))"
                                            )
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(
                                                dayNetIncome > 0
                                                    ? .green : dayNetIncome < 0 ? .red : .secondary
                                            )
                                        }
                                    }

                                    Spacer()

                                    // 右侧：第一行支出，第二行收入
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(FormatUtil.formatISK(-dayExpense))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(dayExpense > 0 ? .red : .secondary)

                                        Text(
                                            "\(dayIncome > 0 ? "+" : "")\(FormatUtil.formatISK(dayIncome))"
                                        )
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(dayIncome > 0 ? .green : .secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    if viewModel.isPartialData {
                        Section {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("Wallet_Partial_Data_Notice", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadJournalData(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Wallet_Journal", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if !viewModel.selectedRefTypes.isEmpty || !viewModel.selectedTransactionTypes.isEmpty {
                        Button(action: {
                            viewModel.selectedRefTypes = []
                            viewModel.selectedTransactionTypes = []
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.red)
                        }
                    }

                    Button(action: {
                        viewModel.showFilterSheet = true
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showFilterSheet) {
            filterView
        }
    }
}

/// 钱包流水条目行视图
struct WalletJournalEntryRow: View {
    let entry: WalletJournalEntry

    private func formatRefType(_ refType: String) -> String {
        let lowercaseRefType = refType.lowercased()

        return LocalizationManager.shared.processEntryTypeName(
            for: lowercaseRefType, esiText: refType, language: LocalizationManager.currentLanguageCode
        )
    }

    private func patchDescription(_ description: String) -> String {
        if entry.ref_type.lowercased() == "market_escrow" && entry.amount <= 0 {
            return NSLocalizedString("Wallet_Market_Escrow_Debit", comment: "授权的市场契约金")
        }
        return description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(formatRefType(entry.ref_type))
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text("\(FormatUtil.format(entry.amount)) ISK")
                    .foregroundColor(entry.amount >= 0 ? .green : .red)
                    .font(.system(.caption, design: .monospaced))
            }

            // 使用模板处理后的描述文本
            Text(
                LocalizationManager.shared.processJournalMessage(
                    for: entry.ref_type.lowercased(),
                    esiText: patchDescription(entry.description),
                    language: LocalizationManager.currentLanguageCode
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)

            // Reason 信息
            if !entry.reason.isEmpty {
                Text(String.localizedStringWithFormat(NSLocalizedString("Reason", comment: ""), entry.reason))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(
                String(
                    format: NSLocalizedString("Balance", comment: ""),
                    FormatUtil.format(entry.balance)
                )
            )
            .font(.caption)
            .foregroundColor(.gray)

            Text(FormatUtil.formatUTCToLocalTime(entry.date))
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                let processedDescription = LocalizationManager.shared.processJournalMessage(
                    for: entry.ref_type.lowercased(),
                    esiText: patchDescription(entry.description),
                    language: LocalizationManager.currentLanguageCode
                )
                let sign = entry.amount >= 0 ? "+" : ""
                var detailText = "[\(FormatUtil.formatUTCToLocalTime(entry.date))] \(processedDescription): \(sign)\(FormatUtil.format(entry.amount)) ISK"
                if !entry.reason.isEmpty {
                    detailText += ", \(String.localizedStringWithFormat(NSLocalizedString("Reason", comment: ""), entry.reason))"
                }
                UIPasteboard.general.string = detailText
            } label: {
                Label(
                    NSLocalizedString("Wallet_Copy_Detail", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }
        }
    }
}
