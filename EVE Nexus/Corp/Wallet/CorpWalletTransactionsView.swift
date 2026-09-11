import SwiftUI

/// 添加WalletTab枚举
enum WalletTab {
    case journal
    case transactions
}

/// 军团交易记录条目模型
struct CorpWalletTransactionEntry: Codable, Identifiable {
    let client_id: Int
    let date: String
    let is_buy: Bool
    let is_personal: Bool? // 某些交易记录可能没有此字段
    let journal_ref_id: Int64
    let location_id: Int64
    let quantity: Int
    let transaction_id: Int64
    let type_id: Int
    let unit_price: Double

    var id: Int64 {
        transaction_id
    }

    /// 提供默认值，如果字段缺失则默认为 false（非个人）
    var isPersonal: Bool {
        return is_personal ?? false
    }
}

/// 合并后的军团交易记录条目
struct CorpMergedTransactionEntry: Identifiable {
    let id = UUID()
    let type_id: Int
    let is_buy: Bool
    let location_id: Int64
    let date: String
    let totalQuantity: Int
    let averagePrice: Double
    let totalAmount: Double
    let originalEntries: [CorpWalletTransactionEntry]

    init(entries: [CorpWalletTransactionEntry]) {
        guard let firstEntry = entries.first else {
            fatalError("Cannot create merged entry from empty array")
        }

        // 按transaction_id排序，最新的在前
        let sortedEntries = entries.sorted { $0.transaction_id > $1.transaction_id }

        type_id = firstEntry.type_id
        is_buy = firstEntry.is_buy
        location_id = firstEntry.location_id
        date = sortedEntries.first!.date // 使用最新的日期
        totalQuantity = entries.reduce(0) { $0 + $1.quantity }
        totalAmount = entries.reduce(0.0) { $0 + ($1.unit_price * Double($1.quantity)) }
        averagePrice = totalAmount / Double(totalQuantity)
        originalEntries = sortedEntries
    }
}

/// 按日期分组的交易记录
struct CorpWalletTransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [CorpWalletTransactionEntry]
    var mergedEntries: [CorpMergedTransactionEntry] = []
}

@MainActor
final class CorpWalletTransactionsViewModel: ObservableObject {
    @Published private(set) var transactionGroups: [CorpWalletTransactionGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = "" // 添加搜索文本状态
    @Published var showSettings = false // 添加设置显示状态
    @Published var mergeSimilarTransactions: Bool {
        didSet {
            UserDefaultsManager.shared.mergeSimilarTransactions = mergeSimilarTransactions
        }
    }

    let characterId: Int
    private let division: Int
    let databaseManager: DatabaseManager
    var itemInfoCache: [Int: TransactionItemInfo] = [:]
    private var locationInfoCache: [Int64: LocationInfoDetail] = [:]

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

    init(characterId: Int, division: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.division = division
        self.databaseManager = databaseManager
        mergeSimilarTransactions = UserDefaultsManager.shared.mergeSimilarTransactions
        // 不在这里自动加载，由视图的 .task 或显式调用 loadTransactionData() 来控制加载时机
    }

    /// 批量加载所有物品信息
    private func loadAllItemInfo(for typeIds: [Int]) {
        if typeIds.isEmpty { return }

        for typeId in typeIds {
            if let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty {
                itemInfoCache[typeId] = TransactionItemInfo(
                    names: info.names,
                    iconFileName: info.iconFilename
                )
            } else {
                itemInfoCache[typeId] = .unknown
            }
        }
    }

    func getLocationView(for locationId: Int64) -> LocationInfoView? {
        // 如果缓存中已有，直接返回
        if let info = locationInfoCache[locationId] {
            return LocationInfoView(
                stationName: info.stationName,
                solarSystemName: info.solarSystemName,
                security: info.security,
                font: .caption,
                textColor: .secondary
            )
        }
        return nil
    }

    func getLocationName(for locationId: Int64) -> String? {
        return locationInfoCache[locationId]?.stationName
    }

    func getLocationEnglishName(for locationId: Int64) -> String? {
        return locationInfoCache[locationId]?.stationEnglishName
    }

    /// 合并相似交易记录
    private func mergeSimilarTransactions(_ entries: [CorpWalletTransactionEntry])
        -> [CorpMergedTransactionEntry]
    {
        var mergedDict: [String: [CorpWalletTransactionEntry]] = [:]

        for entry in entries {
            // 创建唯一键：时间（精确到分钟）+ 物品ID + 买卖类型 + 地点ID
            let dateComponents = dateFormatter.date(from: entry.date) ?? Date()
            let calendar = Calendar.current
            let minuteComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dateComponents
            )
            let minuteDate = calendar.date(from: minuteComponents) ?? dateComponents

            let minuteString = dateFormatter.string(from: minuteDate)
            let key = "\(minuteString)_\(entry.type_id)_\(entry.is_buy)_\(entry.location_id)"

            mergedDict[key, default: []].append(entry)
        }

        return mergedDict.values.map { CorpMergedTransactionEntry(entries: $0) }
            .sorted {
                // 按原始交易记录中最大的transaction_id排序（最新的在前）
                let maxId1 = $0.originalEntries.map { $0.transaction_id }.max() ?? 0
                let maxId2 = $1.originalEntries.map { $0.transaction_id }.max() ?? 0
                return maxId1 > maxId2
            }
    }

    func loadTransactionData(forceRefresh: Bool = false) async {
        // 防重入：加载中直接忽略后来者（含刷新请求）
        guard !isLoading else { return }
        // 幂等：已有数据且非强制刷新时跳过
        guard forceRefresh || transactionGroups.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let jsonString = try await CorpWalletAPI.shared.getCorpWalletTransactions(
                characterId: characterId, division: division, forceRefresh: forceRefresh
            )

            guard let jsonString = jsonString else {
                Logger.error("加载军团交易记录失败: API 返回 nil (characterId: \(characterId), division: \(division))")
                throw NetworkError.invalidResponse
            }

            guard let jsonData = jsonString.data(using: .utf8) else {
                Logger.error("加载军团交易记录失败: 无法将 JSON 字符串转换为 Data (长度: \(jsonString.count))")
                throw NetworkError.invalidResponse
            }

            let entries: [CorpWalletTransactionEntry]
            do {
                entries = try JSONDecoder().decode([CorpWalletTransactionEntry].self, from: jsonData)
            } catch let decodeError {
                let preview = String(jsonString.prefix(5000))
                Logger.error("加载军团交易记录失败: JSON 解码失败 - \(decodeError.localizedDescription)")
                Logger.error("JSON 预览 (前5000字符): \(preview)")
                throw decodeError
            }

            // 收集所有位置ID
            let locationIds = Set(entries.map { $0.location_id })

            // 收集所有物品ID并一次性加载所有物品信息
            let typeIds = Array(Set(entries.map { $0.type_id }))
            loadAllItemInfo(for: typeIds)

            // 使用 LocationInfoLoader 加载位置信息
            let locationLoader = LocationInfoLoader(
                databaseManager: databaseManager, characterId: Int64(characterId)
            )
            locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)

            var groupedEntries: [Date: [CorpWalletTransactionEntry]] = [:]
            for entry in entries {
                guard let date = dateFormatter.date(from: entry.date) else {
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

            let groups = groupedEntries.map { date, entries -> CorpWalletTransactionGroup in
                let sortedEntries = entries.sorted { $0.transaction_id > $1.transaction_id }
                let mergedEntries = mergeSimilarTransactions(sortedEntries)
                return CorpWalletTransactionGroup(
                    date: date,
                    entries: sortedEntries,
                    mergedEntries: mergedEntries
                )
            }.sorted { $0.date > $1.date }

            transactionGroups = groups
        } catch {
            if error is CancellationError {
                // 取消不作为错误展示
            } else {
                Logger.error("加载军团交易记录失败: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 修改过滤后的交易记录计算属性,返回按日期分组的过滤结果
    var filteredTransactionGroups: [CorpWalletTransactionGroup] {
        if searchText.isEmpty {
            return transactionGroups
        }

        return transactionGroups.map { group in
            if mergeSimilarTransactions {
                let filteredMergedEntries = group.mergedEntries.filter { entry in
                    itemInfoCache[entry.type_id]?.matches(searchText) == true
                }
                return CorpWalletTransactionGroup(
                    date: group.date,
                    entries: group.entries,
                    mergedEntries: filteredMergedEntries
                )
            } else {
                let filteredEntries = group.entries.filter { entry in
                    itemInfoCache[entry.type_id]?.matches(searchText) == true
                }
                return CorpWalletTransactionGroup(
                    date: group.date,
                    entries: filteredEntries,
                    mergedEntries: group.mergedEntries
                )
            }
        }.filter { mergeSimilarTransactions ? !$0.mergedEntries.isEmpty : !$0.entries.isEmpty }
    }
}

/// 军团交易记录设置视图
struct CorpWalletTransactionSettingsView: View {
    @ObservedObject var viewModel: CorpWalletTransactionsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $viewModel.mergeSimilarTransactions) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Wallet_Transaction_Merge_Similar", comment: ""))
                                .font(.body)
                            Text(
                                NSLocalizedString(
                                    "Wallet_Transaction_Merge_Similar_Description", comment: ""
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Wallet_Transaction_Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Wallet_Transaction_Settings_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 特定日期的交易记录详情视图
struct CorpWalletTransactionDayDetailView: View {
    let group: CorpWalletTransactionGroup
    let viewModel: CorpWalletTransactionsViewModel
    let currentCharacter: EVECharacterInfo?

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        List {
            if viewModel.mergeSimilarTransactions {
                ForEach(group.mergedEntries) { entry in
                    CorpMergedTransactionEntryRow(entry: entry, viewModel: viewModel, currentCharacter: currentCharacter)
                }
            } else {
                ForEach(group.entries) { entry in
                    CorpWalletTransactionEntryRow(entry: entry, viewModel: viewModel, currentCharacter: currentCharacter)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(displayDateFormatter.string(from: group.date))
    }
}

struct CorpWalletTransactionsView: View {
    @ObservedObject var viewModel: CorpWalletTransactionsViewModel
    @Binding var selectedTab: WalletTab
    @State private var currentCharacter: EVECharacterInfo?

    var body: some View {
        VStack(spacing: 0) {
            transactionList
        }
        .opacity(selectedTab == .transactions ? 1 : 0) // 控制整个视图的显示/隐藏
        .sheet(isPresented: $viewModel.showSettings) {
            CorpWalletTransactionSettingsView(viewModel: viewModel)
        }
        .task {
            let characterId = viewModel.characterId
            if let auth = EVELogin.shared.getCharacterByID(characterId) {
                currentCharacter = auth.character
            }
        }
    }

    /// 交易记录列表；仅「交易记录」标签页挂系统搜索框
    @ViewBuilder
    private var transactionList: some View {
        if selectedTab == .transactions {
            baseList
                .searchable(
                    text: $viewModel.searchText,
                    prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
                )
        } else {
            baseList
        }
    }

    private var baseList: some View {
        List {
            if viewModel.isLoading {
                ForEach(0 ..< 8, id: \.self) { _ in
                    ListSkeletonRow.walletJournal
                }
            } else if let errorMessage = viewModel.errorMessage,
                      viewModel.transactionGroups.isEmpty
            {
                // 与军团钱包页一致的错误展示（含重试按钮）
                ErrorStateSection(message: errorMessage) {
                    Task {
                        await viewModel.loadTransactionData(forceRefresh: true)
                    }
                }
            } else if viewModel.transactionGroups.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                Section {
                    if viewModel.filteredTransactionGroups.isEmpty {
                        NoDataSection()
                    } else {
                        ForEach(viewModel.filteredTransactionGroups) { group in
                            NavigationLink(
                                destination: CorpWalletTransactionDayDetailView(
                                    group: group,
                                    viewModel: viewModel,
                                    currentCharacter: currentCharacter
                                )
                            ) {
                                HStack {
                                    // 左侧：日期和交易信息垂直排列
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(FormatUtil.formatDateToLocalDate(group.date))
                                            .font(.system(size: 16))

                                        let (buyCount, sellCount) =
                                            if viewModel.mergeSimilarTransactions {
                                                (
                                                    group.mergedEntries.filter { $0.is_buy }.count,
                                                    group.mergedEntries.filter { !$0.is_buy }.count
                                                )
                                            } else {
                                                (
                                                    group.entries.filter { $0.is_buy }.count,
                                                    group.entries.filter { !$0.is_buy }.count
                                                )
                                            }
                                        Text(
                                            "\(NSLocalizedString("Main_Market_Transactions_Buy", comment: "")): \(buyCount), \(NSLocalizedString("Main_Market_Transactions_Sell", comment: "")): \(sellCount)"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    // 右侧：净收益
                                    if viewModel.mergeSimilarTransactions {
                                        let sellIncome = group.mergedEntries.filter { !$0.is_buy }
                                            .reduce(0.0) { $0 + $1.totalAmount }
                                        let buyExpense = group.mergedEntries.filter { $0.is_buy }
                                            .reduce(0.0) { $0 + $1.totalAmount }
                                        let netProfit = sellIncome - buyExpense

                                        Text(
                                            "\(netProfit >= 0 ? "+" : "")\(FormatUtil.formatISK(netProfit))"
                                        )
                                        .font(.caption)
                                        .foregroundColor(
                                            netProfit > 0 ? .green : netProfit < 0 ? .red : .secondary
                                        )
                                    } else {
                                        let sellIncome = group.entries.filter { !$0.is_buy }.reduce(0.0)
                                            { $0 + ($1.unit_price * Double($1.quantity)) }
                                        let buyExpense = group.entries.filter { $0.is_buy }.reduce(0.0)
                                            { $0 + ($1.unit_price * Double($1.quantity)) }
                                        let netProfit = sellIncome - buyExpense

                                        Text(
                                            "\(netProfit >= 0 ? "+" : "")\(FormatUtil.formatISK(netProfit))"
                                        )
                                        .font(.caption)
                                        .foregroundColor(
                                            netProfit > 0 ? .green : netProfit < 0 ? .red : .secondary
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadTransactionData(forceRefresh: true)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.showSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
    }
}

struct CorpWalletTransactionEntryRow: View {
    let entry: CorpWalletTransactionEntry
    let viewModel: CorpWalletTransactionsViewModel
    let currentCharacter: EVECharacterInfo?
    @State private var itemIcon: Image?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 导航到详情页面的辅助方法
    @ViewBuilder
    private func navigationDestination(for clientId: Int, isPersonal: Bool) -> some View {
        if let character = currentCharacter {
            if isPersonal {
                CharacterDetailView(characterId: clientId, character: character)
            } else {
                CorporationDetailView(corporationId: clientId, character: character)
            }
        }
    }

    var body: some View {
        NavigationLink {
            MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: entry.type_id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // 物品信息行
                HStack(spacing: 12) {
                    // 物品图标
                    if let icon = itemIcon {
                        icon
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            viewModel.itemInfoCache[entry.type_id]?.name
                                ?? NSLocalizedString(
                                    "Main_Market_Transactions_Loading", comment: ""
                                )
                        )
                        .font(.body)
                        Text("\(FormatUtil.format(entry.unit_price * Double(entry.quantity))) ISK")
                            .foregroundColor(entry.is_buy ? .red : .green)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                // 位置信息
                if let locationView = viewModel.getLocationView(for: entry.location_id) {
                    locationView
                        .lineLimit(1)
                }

                // 时间信息
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        // 交易类型和数量
                        Text(
                            "\(entry.is_buy ? NSLocalizedString("Main_Market_Transactions_Buy", comment: "") : NSLocalizedString("Main_Market_Transactions_Sell", comment: "")) - \(entry.quantity) × \(FormatUtil.format(entry.unit_price)) ISK"
                        )
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        Spacer()
                        if let date = dateFormatter.date(from: entry.date) {
                            Text(
                                "\(timeFormatter.string(from: date))"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            if currentCharacter != nil {
                NavigationLink {
                    navigationDestination(for: entry.client_id, isPersonal: entry.isPersonal)
                } label: {
                    Label(
                        entry.is_buy
                            ? NSLocalizedString("Wallet_Transaction_View_Seller_Info", comment: "")
                            : NSLocalizedString("Wallet_Transaction_View_Buyer_Info", comment: ""),
                        systemImage: "person.circle"
                    )
                }
            }

            // 复制交易地点
            if let locationName = viewModel.getLocationName(for: entry.location_id) {
                Button {
                    UIPasteboard.general.string = locationName
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Location", comment: ""),
                        systemImage: "doc.on.doc"
                    )
                }

                // 显示名与英文名不同时，追加复制英文名
                if let enName = viewModel.getLocationEnglishName(for: entry.location_id),
                   enName != locationName
                {
                    Button {
                        UIPasteboard.general.string = enName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Trans", comment: ""),
                            systemImage: "translate"
                        )
                    }
                }
            }
        }
        .task {
            // 直接从缓存中获取物品信息并加载图标
            if let itemInfo = viewModel.itemInfoCache[entry.type_id] {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}

/// 合并军团交易记录行视图
struct CorpMergedTransactionEntryRow: View {
    let entry: CorpMergedTransactionEntry
    let viewModel: CorpWalletTransactionsViewModel
    let currentCharacter: EVECharacterInfo?
    @State private var itemIcon: Image?
    @State private var showClientList = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 导航到详情页面的辅助方法
    @ViewBuilder
    private func navigationDestination(for clientId: Int, isPersonal: Bool) -> some View {
        if let character = currentCharacter {
            if isPersonal {
                CharacterDetailView(characterId: clientId, character: character)
            } else {
                CorporationDetailView(corporationId: clientId, character: character)
            }
        }
    }

    var body: some View {
        NavigationLink {
            MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: entry.type_id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // 物品信息行
                HStack(spacing: 12) {
                    // 物品图标
                    if let icon = itemIcon {
                        icon
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            viewModel.itemInfoCache[entry.type_id]?.name
                                ?? NSLocalizedString(
                                    "Main_Market_Transactions_Loading", comment: ""
                                )
                        )
                        .font(.body)
                        Text("\(FormatUtil.format(entry.totalAmount)) ISK")
                            .foregroundColor(entry.is_buy ? .red : .green)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                // 位置信息
                if let locationView = viewModel.getLocationView(for: entry.location_id) {
                    locationView
                        .lineLimit(1)
                }

                // 时间信息
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        // 交易类型和数量
                        Text(
                            "\(entry.is_buy ? NSLocalizedString("Main_Market_Transactions_Buy", comment: "") : NSLocalizedString("Main_Market_Transactions_Sell", comment: "")) - \(entry.totalQuantity) × \(FormatUtil.format(entry.averagePrice)) ISK"
                        )
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        Spacer()
                        if let date = dateFormatter.date(from: entry.date) {
                            Text(
                                "\(timeFormatter.string(from: date))"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            // 查看买家/卖家信息
            if currentCharacter != nil {
                // 收集所有不同的交易对象
                let uniqueClients: [(clientId: Int, isPersonal: Bool)] = {
                    var seen = Set<String>()
                    var result: [(Int, Bool)] = []
                    for entry in entry.originalEntries {
                        let key = "\(entry.client_id)_\(entry.isPersonal)"
                        if !seen.contains(key) {
                            seen.insert(key)
                            result.append((entry.client_id, entry.isPersonal))
                        }
                    }
                    return result
                }()

                if uniqueClients.count == 1, let client = uniqueClients.first {
                    // 只有一个交易对象，直接跳转
                    NavigationLink {
                        navigationDestination(for: client.0, isPersonal: client.1)
                    } label: {
                        Label(
                            entry.is_buy
                                ? NSLocalizedString("Wallet_Transaction_View_Seller_Info", comment: "")
                                : NSLocalizedString("Wallet_Transaction_View_Buyer_Info", comment: ""),
                            systemImage: "person.circle"
                        )
                    }
                } else if uniqueClients.count > 1 {
                    // 多个交易对象，显示列表
                    Button {
                        showClientList = true
                    } label: {
                        Label(
                            entry.is_buy
                                ? NSLocalizedString("Wallet_Transaction_View_Seller_Info", comment: "")
                                : NSLocalizedString("Wallet_Transaction_View_Buyer_Info", comment: ""),
                            systemImage: "person.2"
                        )
                    }
                }
            }

            // 复制交易地点
            if let locationName = viewModel.getLocationName(for: entry.location_id) {
                Button {
                    UIPasteboard.general.string = locationName
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Location", comment: ""),
                        systemImage: "doc.on.doc"
                    )
                }

                // 显示名与英文名不同时，追加复制英文名
                if let enName = viewModel.getLocationEnglishName(for: entry.location_id),
                   enName != locationName
                {
                    Button {
                        UIPasteboard.general.string = enName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Trans", comment: ""),
                            systemImage: "translate"
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showClientList) {
            CorpTransactionClientListSheet(
                entry: entry,
                currentCharacter: currentCharacter
            )
        }
        .task {
            // 加载图标
            if let itemInfo = viewModel.itemInfoCache[entry.type_id] {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}

/// 军团交易对象列表 Sheet
struct CorpTransactionClientListSheet: View {
    let entry: CorpMergedTransactionEntry
    let currentCharacter: EVECharacterInfo?
    @Environment(\.dismiss) private var dismiss
    @State private var clientInfos: [(clientId: Int, isPersonal: Bool, name: String, category: String, portrait: UIImage?)] = []
    @State private var isLoading = true

    /// 导航到详情页面的辅助方法
    @ViewBuilder
    private func navigationDestination(for clientId: Int, isPersonal: Bool) -> some View {
        if let character = currentCharacter {
            if isPersonal {
                CharacterDetailView(characterId: clientId, character: character)
            } else {
                CorporationDetailView(corporationId: clientId, character: character)
            }
        }
    }

    /// 根据类型返回默认图标
    private func getDefaultIcon(for category: String) -> Image {
        switch category {
        case "character":
            return Image(systemName: "person.circle")
        case "corporation":
            return Image(systemName: "building.2.crop.circle")
        default:
            return Image(systemName: "questionmark.circle")
        }
    }

    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    // 显示占位行
                    ForEach(0 ..< getPlaceholderCount(), id: \.self) { _ in
                        HStack(spacing: 12) {
                            // 占位头像
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)

                            // 加载指示器
                            ProgressView()

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                } else {
                    // 显示实际数据
                    ForEach(clientInfos, id: \.clientId) { client in
                        NavigationLink {
                            navigationDestination(for: client.clientId, isPersonal: client.isPersonal)
                        } label: {
                            HStack(spacing: 12) {
                                // 头像
                                if let portrait = client.portrait {
                                    Image(uiImage: portrait)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    getDefaultIcon(for: client.category)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .foregroundColor(.secondary)
                                }

                                // 名称
                                Text(client.name)
                                    .font(.body)

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(
                entry.is_buy
                    ? NSLocalizedString("Wallet_Transaction_View_Seller_Info", comment: "")
                    : NSLocalizedString("Wallet_Transaction_View_Buyer_Info", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Wallet_Transaction_Settings_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadClientInfos()
        }
    }

    /// 获取占位行数量
    private func getPlaceholderCount() -> Int {
        var seen = Set<String>()
        for entry in entry.originalEntries {
            let key = "\(entry.client_id)_\(entry.isPersonal)"
            seen.insert(key)
        }
        return seen.count
    }

    private func loadClientInfos() async {
        // 收集所有不同的 client_id 和 is_personal 组合
        var seen = Set<String>()
        var uniqueClients: [(clientId: Int, isPersonal: Bool)] = []
        for entry in entry.originalEntries {
            let key = "\(entry.client_id)_\(entry.isPersonal)"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueClients.append((entry.client_id, entry.isPersonal))
            }
        }

        // 按 client_id 排序
        uniqueClients.sort { $0.clientId < $1.clientId }

        // 获取所有 ID 的名称和类型信息
        let ids = Set(uniqueClients.map { $0.clientId })

        do {
            let namesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(ids: Array(ids))

            // 加载所有客户端信息（包括头像）
            var loadedInfos: [(Int, Bool, String, String, UIImage?)] = []

            for client in uniqueClients {
                if let nameInfo = namesWithCategories[client.clientId] {
                    let portrait = await loadPortrait(id: client.clientId, category: nameInfo.category)
                    loadedInfos.append((
                        client.clientId,
                        client.isPersonal,
                        nameInfo.name,
                        nameInfo.category,
                        portrait
                    ))
                } else {
                    loadedInfos.append((
                        client.clientId,
                        client.isPersonal,
                        "Unknown",
                        "",
                        nil
                    ))
                }
            }

            await MainActor.run {
                clientInfos = loadedInfos
                isLoading = false
            }
        } catch {
            Logger.error("加载交易对象信息失败: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }

    /// 根据类型加载头像
    private func loadPortrait(id: Int, category: String) async -> UIImage? {
        switch category {
        case "character":
            return try? await CharacterAPI.shared.fetchCharacterPortrait(characterId: id, catchImage: false)
        case "corporation":
            return try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: id)
        default:
            return nil
        }
    }
}
