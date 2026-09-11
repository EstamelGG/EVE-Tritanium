import SwiftUI

/// 军团钱包流水条目模型
struct CorpWalletJournalEntry: Codable, Identifiable {
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
struct CorpWalletJournalGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [CorpWalletJournalEntry]
}

/// 加载进度枚举
public enum WalletLoadingProgress {
    case loading(page: Int) // 正在加载特定页面
    case completed // 加载完成
}

@MainActor
final class CorpWalletJournalViewModel: ObservableObject {
    @Published private(set) var journalGroups: [CorpWalletJournalGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var totalIncome: Double = 0.0
    @Published private(set) var totalExpense: Double = 0.0
    @Published var loadingProgress: WalletLoadingProgress?
    @Published var timeRange: TimeRange = .last30Days
    @Published var showFilter = false
    @Published var selectedRefTypes: Set<String> = []
    @Published var selectedTransactionTypes: Set<TransactionType> = []
    @Published private(set) var totalEntries: Int = 0
    @Published private(set) var isPartialData: Bool = false

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

    var filteredJournalGroups: [CorpWalletJournalGroup] {
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
            return CorpWalletJournalGroup(date: group.date, entries: filteredEntries)
        }.filter { !$0.entries.isEmpty }
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

    /// 获取交易类型的本地化名称
    func getLocalizedRefType(_ refType: String) -> String {
        return LocalizationManager.shared.processEntryTypeName(
            for: refType.lowercased(),
            esiText: refType,
            language: LocalizationManager.currentLanguageCode
        )
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
    private let division: Int

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current // 使用本地时区
        return calendar
    }()

    init(characterId: Int, division: Int) {
        self.characterId = characterId
        self.division = division
        // 不在这里自动加载，由视图的 .task 或显式调用 loadJournalData() 来控制加载时机
    }

    /// 计算总收支
    private func calculateTotals(from entries: [CorpWalletJournalEntry]) {
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
        // 防重入：加载中直接忽略后来者（含刷新请求）
        guard !isLoading else { return }
        // 幂等：已有数据且非强制刷新时跳过
        guard forceRefresh || journalGroups.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            loadingProgress = nil
        }

        do {
            guard
                let jsonString = try await CorpWalletAPI.shared.getCorpWalletJournal(
                    characterId: characterId,
                    division: division,
                    forceRefresh: forceRefresh,
                    progressCallback: { progress in
                        Task { @MainActor in
                            self.loadingProgress = progress
                        }
                    }
                )
            else {
                throw NetworkError.invalidResponse
            }

            guard let jsonData = jsonString.data(using: .utf8),
                  let entries = try? JSONDecoder().decode(
                      [CorpWalletJournalEntry].self, from: jsonData
                  )
            else {
                throw NetworkError.invalidResponse
            }

            // 检查数据量
            totalEntries = entries.count

            // 检查是否只显示部分数据
            if totalEntries >= 9500 {
                // 获取最久远的记录日期
                if let oldestEntry = entries.min(by: { $0.date < $1.date }),
                   let oldestDate = dateFormatter.date(from: oldestEntry.date)
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

            // 按日期分组
            var groupedEntries: [Date: [CorpWalletJournalEntry]] = [:]
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

            let groups = groupedEntries.map { date, entries -> CorpWalletJournalGroup in
                CorpWalletJournalGroup(date: date, entries: entries.sorted { $0.id > $1.id })
            }.sorted { $0.date > $1.date }

            // 首次成功加载时自动全选过滤项（赋值前 journalGroups 为空即首载）
            let isFirstLoad = journalGroups.isEmpty
            journalGroups = groups

            if isFirstLoad {
                let availableTypes = availableRefTypes
                if selectedRefTypes.isEmpty, !availableTypes.isEmpty {
                    selectedRefTypes = Set(availableTypes)
                }
                if selectedTransactionTypes.isEmpty {
                    selectedTransactionTypes = [.income, .expense]
                }
            }
        } catch {
            if error is CancellationError {
                // 取消不作为错误展示
            } else {
                Logger.error("加载军团钱包流水失败: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 特定日期的军团钱包流水详情视图
struct CorpWalletJournalDayDetailView: View {
    let group: CorpWalletJournalGroup
    @State private var displayedEntries: [CorpWalletJournalEntry] = []
    @State private var showingCount = 100

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    var body: some View {
        List {
            ForEach(displayedEntries, id: \.id) { entry in
                CorpWalletJournalEntryRow(entry: entry)
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

struct CorpWalletJournalView: View {
    @ObservedObject var viewModel: CorpWalletJournalViewModel

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    var filterView: some View {
        NavigationView {
            List {
                Section(
                    header: HStack {
                        Text(NSLocalizedString("Wallet_Transaction_Type", comment: ""))
                        Spacer()
                        Button(action: {
                            let allTypes: Set<CorpWalletJournalViewModel.TransactionType> = [.income, .expense]
                            if viewModel.selectedTransactionTypes.count == allTypes.count {
                                viewModel.selectedTransactionTypes = []
                            } else {
                                viewModel.selectedTransactionTypes = allTypes
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: ""))
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
                            Text(CorpWalletJournalViewModel.TransactionType.income.localizedString)
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
                            Text(CorpWalletJournalViewModel.TransactionType.expense.localizedString)
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
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: ""))
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
                    footer: Text(NSLocalizedString("Wallet_Journal_Sorted_By_Count", comment: ""))
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
                                Text(viewModel.getLocalizedRefType(refType))
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
                        viewModel.showFilter = false
                    }
                }
            }
        }
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

    var body: some View {
        List {
            // 加载进度部分
            if viewModel.isLoading || viewModel.loadingProgress != nil {
                Section {
                    HStack {
                        Spacer()
                        if let progress = viewModel.loadingProgress {
                            let text: String =
                                switch progress {
                                case let .loading(page):
                                    String(
                                        format: NSLocalizedString(
                                            "Wallet_Loading_Fetching", comment: ""
                                        ), page
                                    )
                                case .completed:
                                    NSLocalizedString("Wallet_Loading_Complete", comment: "")
                                }

                            Text(text)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if viewModel.isLoading {
                WalletJournalSkeleton()
            } else if let errorMessage = viewModel.errorMessage,
                      viewModel.journalGroups.isEmpty
            {
                // 与军团钱包页一致的错误展示（含重试按钮）
                ErrorStateSection(message: errorMessage) {
                    Task {
                        await viewModel.loadJournalData(forceRefresh: true)
                    }
                }
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
                            NavigationLink(
                                destination: CorpWalletJournalDayDetailView(group: group)
                            ) {
                                HStack {
                                    // 左侧：日期和交易数垂直排列
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(FormatUtil.formatDateToLocalDate(group.date))
                                            .font(.system(size: 16))

                                        Text(
                                            "\(group.entries.count) \(NSLocalizedString("transactions", comment: ""))"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    // 右侧：净收益
                                    let dayNetIncome = group.entries.reduce(0.0) { $0 + $1.amount }
                                    Text(
                                        "\(dayNetIncome >= 0 ? "+" : "")\(FormatUtil.formatISK(dayNetIncome))"
                                    )
                                    .font(.caption)
                                    .foregroundColor(
                                        dayNetIncome > 0
                                            ? .green : dayNetIncome < 0 ? .red : .secondary
                                    )
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
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
                        viewModel.showFilter = true
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showFilter) {
            filterView
        }
    }
}

/// 钱包流水条目行视图
struct CorpWalletJournalEntryRow: View {
    let entry: CorpWalletJournalEntry

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
            // 交易类型和金额
            HStack {
                Text(formatRefType(entry.ref_type))
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text("\(FormatUtil.format(entry.amount)) ISK")
                    .foregroundColor(entry.amount >= 0 ? .green : .red)
                    .font(.system(.caption, design: .monospaced))
            }

            // 交易细节
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

            // 余额
            Text(
                String(
                    format: NSLocalizedString("Balance", comment: ""),
                    FormatUtil.format(entry.balance)
                )
            )
            .font(.caption)
            .foregroundColor(.gray)

            // 时间
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
