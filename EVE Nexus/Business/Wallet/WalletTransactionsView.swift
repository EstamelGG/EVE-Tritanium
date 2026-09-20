import SwiftUI

/// 交易记录筛选类型
enum TransactionFilter: String, CaseIterable {
    case all
    case sell // 卖出（is_buy == false）
    case buy // 买入（is_buy == true）

    var label: String {
        switch self {
        case .all:
            return NSLocalizedString("Main_Market_Transactions_Filter_All", comment: "")
        case .sell:
            return NSLocalizedString("Main_Market_Transactions_Sell", comment: "")
        case .buy:
            return NSLocalizedString("Main_Market_Transactions_Buy", comment: "")
        }
    }
}

/// 交易记录条目模型
struct WalletTransactionEntry: Codable, Identifiable {
    let client_id: Int
    let date: String
    let is_buy: Bool
    let is_personal: Bool
    let journal_ref_id: Int64
    let location_id: Int64
    let quantity: Int
    let transaction_id: Int64
    let type_id: Int
    let unit_price: Double

    var id: Int64 {
        transaction_id
    }
}

/// 合并后的交易记录条目
struct MergedTransactionEntry: Identifiable {
    let id = UUID()
    let type_id: Int
    let is_buy: Bool
    let location_id: Int64
    let date: String
    let totalQuantity: Int
    let averagePrice: Double
    let totalAmount: Double
    let originalEntries: [WalletTransactionEntry]

    init(entries: [WalletTransactionEntry]) {
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
struct WalletTransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [WalletTransactionEntry]
    var mergedEntries: [MergedTransactionEntry] = []
}

/// 交易记录物品信息模型
struct TransactionItemInfo {
    let names: LocalizedText
    let iconFileName: String

    var name: String {
        names.resolved()
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query)
    }

    static let unknown = TransactionItemInfo(
        names: LocalizedText(
            de: "Unknown Item", en: "Unknown Item", es: "Unknown Item", fr: "Unknown Item",
            ja: "Unknown Item", ko: "Unknown Item", ru: "Unknown Item", zh: "未知物品"
        ),
        iconFileName: IconManager.defaultItemIcon
    )
}

@MainActor
final class WalletTransactionsViewModel: ObservableObject {
    @Published private(set) var transactionGroups: [WalletTransactionGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var searchText = "" // 添加搜索文本状态
    @Published var showSettings = false // 添加设置显示状态
    @Published var transactionFilter: TransactionFilter = .all // 交易类型筛选
    @Published var mergeSimilarTransactions: Bool {
        didSet {
            UserDefaultsManager.shared.mergeSimilarTransactions = mergeSimilarTransactions
        }
    }

    private var initialLoadDone = false

    let characterId: Int
    let databaseManager: DatabaseManager
    private var itemInfoCache: [Int: TransactionItemInfo] = [:]
    private var locationInfoCache: [Int64: LocationInfoDetail] = [:]
    private var loadingTask: Task<Void, Never>?

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current // 使用本地时区
        return calendar
    }()

    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
        mergeSimilarTransactions = UserDefaultsManager.shared.mergeSimilarTransactions

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadTransactionData()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    func getItemInfo(for typeId: Int) -> TransactionItemInfo {
        // 先检查缓存
        if let cachedInfo = itemInfoCache[typeId] {
            return cachedInfo
        }

        // 如果缓存中没有，返回默认值（这种情况应该很少发生，因为我们已经预加载了所有物品信息）
        Logger.warning("物品信息未在缓存中找到: \(typeId)")
        return .unknown
    }

    /// 一次性加载所有物品信息
    private func loadAllItemInfo(from entries: [WalletTransactionEntry]) {
        let typeIds = Set(entries.map { $0.type_id })
        if typeIds.isEmpty {
            return
        }

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
    private func mergeSimilarTransactions(_ entries: [WalletTransactionEntry])
        -> [MergedTransactionEntry]
    {
        var mergedDict: [String: [WalletTransactionEntry]] = [:]

        for entry in entries {
            // 创建唯一键：时间（精确到分钟）+ 物品ID + 买卖类型 + 地点ID
            let dateComponents = FormatUtil.parseUTCDate(entry.date) ?? Date()
            let calendar = Calendar.current
            let minuteComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dateComponents
            )
            let minuteDate = calendar.date(from: minuteComponents) ?? dateComponents

            let minuteString = FormatUtil.formatDateToLocalTime(minuteDate)
            let key = "\(minuteString)_\(entry.type_id)_\(entry.is_buy)_\(entry.location_id)"

            mergedDict[key, default: []].append(entry)
        }

        return mergedDict.values.map { MergedTransactionEntry(entries: $0) }
            .sorted {
                // 按原始交易记录中最大的transaction_id排序（最新的在前）
                let maxId1 = $0.originalEntries.map { $0.transaction_id }.max() ?? 0
                let maxId2 = $1.originalEntries.map { $0.transaction_id }.max() ?? 0
                return maxId1 > maxId2
            }
    }

    func loadTransactionData(forceRefresh: Bool = false) async {
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
                    let jsonString = try await CharacterWalletAPI.shared.getWalletTransactions(
                        characterId: characterId, forceRefresh: forceRefresh
                    )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled {
                    return
                }

                guard let jsonData = jsonString.data(using: .utf8),
                      let entries = try? JSONDecoder().decode(
                          [WalletTransactionEntry].self, from: jsonData
                      )
                else {
                    throw NetworkError.invalidResponse
                }

                if Task.isCancelled {
                    return
                }

                // 收集所有位置ID
                let locationIds = Set(entries.map { $0.location_id })

                // 使用 LocationInfoLoader 加载位置信息
                let locationLoader = LocationInfoLoader(
                    databaseManager: databaseManager, characterId: Int64(characterId)
                )
                locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)

                if Task.isCancelled {
                    return
                }

                // 一次性加载所有物品信息
                loadAllItemInfo(from: entries)

                if Task.isCancelled {
                    return
                }

                var groupedEntries: [Date: [WalletTransactionEntry]] = [:]
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

                if Task.isCancelled {
                    return
                }

                let groups = groupedEntries.map { date, entries -> WalletTransactionGroup in
                    let sortedEntries = entries.sorted { $0.transaction_id > $1.transaction_id }
                    let mergedEntries = mergeSimilarTransactions(sortedEntries)
                    return WalletTransactionGroup(
                        date: date,
                        entries: sortedEntries,
                        mergedEntries: mergedEntries
                    )
                }.sorted { $0.date > $1.date }

                await MainActor.run {
                    self.transactionGroups = groups
                    self.isLoading = false
                    self.initialLoadDone = true
                }

            } catch {
                Logger.error("加载交易记录失败: \(error.localizedDescription)")
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

    /// 添加过滤后的交易记录计算属性
    var filteredTransactionGroups: [WalletTransactionGroup] {
        transactionGroups.compactMap { group in
            // 按交易类型筛选
            let typeFilteredEntries: [WalletTransactionEntry]
            let typeFilteredMerged: [MergedTransactionEntry]

            switch transactionFilter {
            case .all:
                typeFilteredEntries = group.entries
                typeFilteredMerged = group.mergedEntries
            case .buy:
                typeFilteredEntries = group.entries.filter { $0.is_buy }
                typeFilteredMerged = group.mergedEntries.filter { $0.is_buy }
            case .sell:
                typeFilteredEntries = group.entries.filter { !$0.is_buy }
                typeFilteredMerged = group.mergedEntries.filter { !$0.is_buy }
            }

            // 按搜索文本筛选
            let finalEntries: [WalletTransactionEntry]
            let finalMerged: [MergedTransactionEntry]

            if searchText.isEmpty {
                finalEntries = typeFilteredEntries
                finalMerged = typeFilteredMerged
            } else if mergeSimilarTransactions {
                finalEntries = typeFilteredEntries
                finalMerged = typeFilteredMerged.filter {
                    getItemInfo(for: $0.type_id).matches(searchText)
                }
            } else {
                finalEntries = typeFilteredEntries.filter {
                    getItemInfo(for: $0.type_id).matches(searchText)
                }
                finalMerged = typeFilteredMerged
            }

            let hasContent = mergeSimilarTransactions ? !finalMerged.isEmpty : !finalEntries.isEmpty
            guard hasContent else { return nil }

            return WalletTransactionGroup(
                date: group.date,
                entries: finalEntries,
                mergedEntries: finalMerged
            )
        }
    }
}

/// 设置视图
struct WalletTransactionSettingsView: View {
    @ObservedObject var viewModel: WalletTransactionsViewModel
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
struct WalletTransactionDayDetailView: View {
    let group: WalletTransactionGroup
    let viewModel: WalletTransactionsViewModel
    let currentCharacter: EVECharacterInfo?

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    var body: some View {
        List {
            if viewModel.mergeSimilarTransactions {
                ForEach(group.mergedEntries) { entry in
                    MergedTransactionEntryRow(entry: entry, viewModel: viewModel, currentCharacter: currentCharacter)
                }
            } else {
                ForEach(group.entries) { entry in
                    WalletTransactionEntryRow(entry: entry, viewModel: viewModel, currentCharacter: currentCharacter)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(FormatUtil.formatDateToLocalDate(group.date))
    }
}

struct WalletTransactionsView: View {
    @StateObject private var viewModel: WalletTransactionsViewModel
    @State private var currentCharacter: EVECharacterInfo?

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    init(characterId: Int, databaseManager: DatabaseManager) {
        _viewModel = StateObject(
            wrappedValue: WalletTransactionsViewModel(
                characterId: characterId, databaseManager: databaseManager
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TransactionListView(
                viewModel: viewModel,
                currentCharacter: currentCharacter
            )
        }
        .navigationTitle(NSLocalizedString("Main_Market_Transactions", comment: ""))
        .searchable(
            text: $viewModel.searchText,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search_Item", comment: ""))
        )
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.showSettings) {
            WalletTransactionSettingsView(viewModel: viewModel)
        }
        .task {
            let characterId = viewModel.characterId
            if let auth = EVELogin.shared.getCharacterByID(characterId) {
                currentCharacter = auth.character
            }
        }
    }
}

/// 交易记录列表视图
private struct TransactionListView: View {
    @ObservedObject var viewModel: WalletTransactionsViewModel
    let currentCharacter: EVECharacterInfo?

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if viewModel.transactionGroups.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                Section {
                    ForEach(viewModel.filteredTransactionGroups) { group in
                        NavigationLink(
                            destination: WalletTransactionDayDetailView(
                                group: group, viewModel: viewModel, currentCharacter: currentCharacter
                            )
                        ) {
                            HStack {
                                // 左侧：日期和交易信息垂直排列
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(FormatUtil.formatDateToLocalDate(group.date))
                                        .font(.system(size: 16))

                                    if viewModel.mergeSimilarTransactions {
                                        let buyCount = group.mergedEntries.filter { $0.is_buy }
                                            .count
                                        let sellCount = group.mergedEntries.filter { !$0.is_buy }
                                            .count

                                        Text(
                                            "\(NSLocalizedString("Main_Market_Transactions_Buy", comment: ""))：\(buyCount)，\(NSLocalizedString("Main_Market_Transactions_Sell", comment: ""))：\(sellCount)"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    } else {
                                        let buyCount = group.entries.filter { $0.is_buy }.count
                                        let sellCount = group.entries.filter { !$0.is_buy }.count

                                        Text(
                                            "\(NSLocalizedString("Main_Market_Transactions_Buy", comment: ""))：\(buyCount)，\(NSLocalizedString("Main_Market_Transactions_Sell", comment: ""))：\(sellCount)"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
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
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadTransactionData(forceRefresh: true)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(TransactionFilter.allCases, id: \.self) { filter in
                            Button {
                                viewModel.transactionFilter = filter
                            } label: {
                                HStack {
                                    Text(filter.label)
                                    if viewModel.transactionFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(
                            systemName: viewModel.transactionFilter == .all
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }

                    Button(action: {
                        viewModel.showSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }
}

/// 合并交易记录行视图
struct MergedTransactionEntryRow: View {
    let entry: MergedTransactionEntry
    let viewModel: WalletTransactionsViewModel
    let currentCharacter: EVECharacterInfo?
    @State private var itemInfo: TransactionItemInfo?
    @State private var itemIcon: Image?
    @State private var showClientList = false

    // 使用FormatUtil进行日期处理，无需自定义格式化器

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

                    VStack(alignment: .leading) {
                        Text(
                            "\(itemInfo?.name ?? NSLocalizedString("Main_Market_Transactions_Loading", comment: "")) × \(entry.totalQuantity)"
                        )
                        .font(.body)
                        Text("\(FormatUtil.format(entry.totalAmount)) ISK")
                            .foregroundColor(entry.is_buy ? .red : .green)
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                // 交易地点
                if let locationView = viewModel.getLocationView(for: entry.location_id) {
                    locationView
                        .lineLimit(1)
                }

                // 交易详细信息
                VStack(alignment: .leading, spacing: 4) {
                    // 交易时间
                    HStack {
                        // 交易类型和数量
                        Text(
                            "\(entry.is_buy ? NSLocalizedString("Main_Market_Transactions_Buy", comment: "") : NSLocalizedString("Main_Market_Transactions_Sell", comment: "")) - \(entry.totalQuantity) × \(FormatUtil.format(entry.averagePrice)) ISK"
                        )
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        Spacer()
                        Text(FormatUtil.formatUTCToLocalTimeOnly(entry.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                        let key = "\(entry.client_id)_\(entry.is_personal)"
                        if !seen.contains(key) {
                            seen.insert(key)
                            result.append((entry.client_id, entry.is_personal))
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
            TransactionClientListSheet(
                entry: entry,
                currentCharacter: currentCharacter
            )
        }
        .task {
            // 加载物品信息
            itemInfo = viewModel.getItemInfo(for: entry.type_id)
            // 加载图标
            if let itemInfo = itemInfo {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}

/// 交易对象列表 Sheet
struct TransactionClientListSheet: View {
    let entry: MergedTransactionEntry
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
            let key = "\(entry.client_id)_\(entry.is_personal)"
            seen.insert(key)
        }
        return seen.count
    }

    private func loadClientInfos() async {
        // 收集所有不同的 client_id 和 is_personal 组合
        var seen = Set<String>()
        var uniqueClients: [(clientId: Int, isPersonal: Bool)] = []
        for entry in entry.originalEntries {
            let key = "\(entry.client_id)_\(entry.is_personal)"
            if !seen.contains(key) {
                seen.insert(key)
                uniqueClients.append((entry.client_id, entry.is_personal))
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

struct WalletTransactionEntryRow: View {
    let entry: WalletTransactionEntry
    let viewModel: WalletTransactionsViewModel
    let currentCharacter: EVECharacterInfo?
    @State private var itemInfo: TransactionItemInfo?
    @State private var itemIcon: Image?

    // 使用FormatUtil进行日期处理，无需自定义格式化器

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

                    VStack(alignment: .leading) {
                        Text(
                            "\(itemInfo?.name ?? NSLocalizedString("Main_Market_Transactions_Loading", comment: "")) × \(entry.quantity)"
                        )
                        .font(.body)
                        Text("\(FormatUtil.format(entry.unit_price * Double(entry.quantity))) ISK")
                            .foregroundColor(entry.is_buy ? .red : .green)
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                // 交易地点
                if let locationView = viewModel.getLocationView(for: entry.location_id) {
                    locationView
                        .lineLimit(1)
                }

                // 交易详细信息
                VStack(alignment: .leading, spacing: 4) {
                    // 交易时间
                    HStack {
                        // 交易类型和数量
                        Text(
                            "\(entry.is_buy ? NSLocalizedString("Main_Market_Transactions_Buy", comment: "") : NSLocalizedString("Main_Market_Transactions_Sell", comment: "")) - \(entry.quantity) × \(FormatUtil.format(entry.unit_price)) ISK"
                        )
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        Spacer()
                        Text(FormatUtil.formatUTCToLocalTimeOnly(entry.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .contextMenu {
            if currentCharacter != nil {
                NavigationLink {
                    navigationDestination(for: entry.client_id, isPersonal: entry.is_personal)
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
            // 加载物品信息
            itemInfo = viewModel.getItemInfo(for: entry.type_id)
            // 加载图标
            if let itemInfo = itemInfo {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}
