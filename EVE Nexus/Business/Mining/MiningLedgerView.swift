import Charts
import SwiftUI
import UIKit

/// 进度更新 Actor（用于线程安全地更新进度）
actor MiningProgressActor {
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

/// 按月份分组的挖矿记录
struct MiningMonthGroup: Identifiable {
    let id = UUID()
    let yearMonth: Date
    var entries: [MiningItemSummary]
}

/// 每种矿石的汇总信息
struct MiningItemSummary: Identifiable {
    let id: Int // type_id
    let name: String
    let iconFileName: String
    var totalQuantity: Int
}

/// 扩展挖矿记录以包含角色归属信息
struct MiningLedgerEntryWithOwner {
    let entry: CharacterMiningAPI.MiningLedgerEntry
    let ownerId: Int // 该挖矿记录归属的角色ID
}

/// 按日期汇总的挖矿数据
struct DailyMiningSummary: Identifiable {
    let id = UUID()
    let date: Date
    let totalVolume: Double // 总体积（m³）
    let oreTypes: Int // 矿石种类数
    let characterCount: Int // 参与人物数
    let entries: [MiningItemSummary] // 该天的矿石明细
    let rawEntries: [MiningLedgerEntryWithOwner] // 原始挖矿记录（用于图表分析）
}

@MainActor
final class MiningLedgerViewModel: ObservableObject {
    @Published private(set) var monthGroups: [MiningMonthGroup] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var loadingProgress: (current: Int, total: Int)? = nil // 加载进度 (已加载/总数)
    private var initialLoadDone = false

    /// 多人物聚合相关
    @Published var multiCharacterMode = false {
        didSet {
            UserDefaults.standard.set(multiCharacterMode, forKey: "multiCharacterMode_mining")
            if initialLoadDone {
                Task {
                    await loadMiningData(forceRefresh: true)
                }
            }
        }
    }

    @Published var selectedCharacterIds: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_mining"
            )
            if initialLoadDone, multiCharacterMode {
                Task {
                    await loadMiningData(forceRefresh: true)
                }
            }
        }
    }

    @Published var availableCharacters: [(id: Int, name: String)] = []

    private let characterId: Int
    let databaseManager: DatabaseManager
    private var itemInfoCache: [Int: (name: String, iconFileName: String)] = [:]
    private var itemVolumeCache: [Int: Double] = [:] // 物品体积缓存
    private var loadingTask: Task<Void, Never>?
    private var entriesWithOwner: [MiningLedgerEntryWithOwner] = [] // 包含所有者信息的挖矿记录

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current // 使用本地时区
        return calendar
    }()

    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager

        // 从 UserDefaults 读取多人物聚合设置
        multiCharacterMode = UserDefaults.standard.bool(forKey: "multiCharacterMode_mining")
        let savedCharacterIds =
            UserDefaults.standard.array(forKey: "selectedCharacterIds_mining") as? [Int] ?? []
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
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_mining"
            )
        }

        // 如果没有选中的角色，默认选择当前角色
        if selectedCharacterIds.isEmpty {
            selectedCharacterIds.insert(characterId)
        }

        // 构造时启动数据加载（原先由视图 init 触发，移入以避免视图重复构造引发重复加载）
        Task {
            await loadMiningData()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    /// 批量获取物品信息的方法
    func preloadItemInfo(for typeIds: Set<Int>) {
        guard !typeIds.isEmpty else { return }

        // 过滤掉已经缓存的物品ID
        let idsToLoad = typeIds.filter { !itemInfoCache.keys.contains($0) }

        if idsToLoad.isEmpty {
            Logger.debug("所有物品信息已在缓存中，无需重新加载")
            return
        }

        Logger.debug("开始批量加载\(idsToLoad.count)个物品信息")

        var loadedCount = 0
        for typeId in idsToLoad {
            guard let info = ItemInfoMap.typeInfo(for: typeId), !info.name.isEmpty else { continue }
            itemInfoCache[typeId] = (name: info.name, iconFileName: info.iconFilename)
            itemVolumeCache[typeId] = info.volume
            loadedCount += 1
        }
        Logger.success("成功加载了\(loadedCount)个物品信息")

        // 检查是否有未找到的物品ID，为它们设置默认值
        for typeId in idsToLoad {
            if itemInfoCache[typeId] == nil {
                let unknownName = String(
                    format: NSLocalizedString("Mining_Unknown_Ore", comment: ""), typeId
                )
                itemInfoCache[typeId] = (
                    name: unknownName, iconFileName: IconManager.defaultItemIcon
                )
            }
        }

        Logger.debug("物品信息缓存现在包含\(itemInfoCache.count)个条目")
    }

    func loadMiningData(forceRefresh: Bool = false) async {
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
                // 获取挖矿记录数据
                let allEntries = try await fetchMiningData(forceRefresh: forceRefresh)

                if Task.isCancelled {
                    return
                }

                Logger.debug("获取到挖矿记录：\(allEntries.count)条")

                // 提取所有唯一的物品ID
                let uniqueTypeIds = Set(allEntries.map { $0.entry.type_id })

                // 一次性预加载所有物品信息
                preloadItemInfo(for: uniqueTypeIds)

                // 按月份和矿石类型分组
                var groupedByMonth: [Date: [Int: Int]] = [:] // [月份: [type_id: 总数量]]

                for entryWithOwner in allEntries {
                    let entry = entryWithOwner.entry
                    guard let date = FormatUtil.parseUTCDate(entry.date) else {
                        Logger.error("日期格式错误：\(entry.date)")
                        continue
                    }

                    let components = calendar.dateComponents([.year, .month], from: date)
                    guard let monthDate = calendar.date(from: components) else {
                        Logger.error("无法创建月份日期")
                        continue
                    }

                    if groupedByMonth[monthDate] == nil {
                        groupedByMonth[monthDate] = [:]
                    }

                    groupedByMonth[monthDate]?[entry.type_id, default: 0] += entry.quantity
                }

                if Task.isCancelled {
                    return
                }

                Logger.debug("分组后的月份数：\(groupedByMonth.count)")

                // 转换为视图模型
                let groups = groupedByMonth.map { date, itemQuantities -> MiningMonthGroup in
                    let summaries = itemQuantities.map { typeId, quantity -> MiningItemSummary in
                        // 直接从缓存中获取物品信息，因为我们已经预加载了所有物品
                        let info =
                            itemInfoCache[typeId] ?? (
                                name: String(
                                    format: NSLocalizedString("Mining_Unknown_Ore", comment: ""),
                                    typeId
                                ),
                                iconFileName: IconManager.defaultItemIcon
                            )
                        return MiningItemSummary(
                            id: typeId,
                            name: info.name,
                            iconFileName: info.iconFileName,
                            totalQuantity: quantity
                        )
                    }.sorted { $0.totalQuantity > $1.totalQuantity }

                    return MiningMonthGroup(yearMonth: date, entries: summaries)
                }.sorted { $0.yearMonth > $1.yearMonth }

                if Task.isCancelled {
                    return
                }

                Logger.debug("最终生成的月份组数：\(groups.count)")

                await MainActor.run {
                    self.monthGroups = groups
                    Logger.debug("UI更新完成，monthGroups数量：\(self.monthGroups.count)")
                    self.isLoading = false
                    self.loadingProgress = nil
                    self.initialLoadDone = true
                }

            } catch {
                Logger.error("加载挖矿记录失败：\(error.localizedDescription)")
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

    /// 封装获取数据逻辑，处理多人物模式
    private func fetchMiningData(forceRefresh: Bool = false) async throws -> [MiningLedgerEntryWithOwner] {
        var allEntries: [MiningLedgerEntryWithOwner] = []

        if multiCharacterMode, selectedCharacterIds.count > 1 {
            // 多人物模式：并发获取所有选中人物的挖矿记录
            let totalCharacters = selectedCharacterIds.count

            // 初始化加载进度
            await MainActor.run {
                self.loadingProgress = (current: 0, total: totalCharacters)
            }

            // 使用 Actor 来线程安全地更新进度
            let progressActor = MiningProgressActor(total: totalCharacters) { current, total in
                Task { @MainActor in
                    self.loadingProgress = (current: current, total: total)
                }
            }

            await withTaskGroup(of: (Int, Result<[CharacterMiningAPI.MiningLedgerEntry], Error>).self) { group in
                for characterId in selectedCharacterIds {
                    group.addTask {
                        do {
                            let entries = try await CharacterMiningAPI.shared.getMiningLedger(
                                characterId: characterId,
                                forceRefresh: forceRefresh
                            )
                            return (characterId, .success(entries))
                        } catch {
                            Logger.error("获取角色\(characterId)挖矿记录失败: \(error)")
                            return (characterId, .failure(error))
                        }
                    }
                }

                // 收集结果
                for await (characterId, result) in group {
                    switch result {
                    case let .success(entries):
                        // 为每个记录添加所有者信息
                        for entry in entries {
                            allEntries.append(
                                MiningLedgerEntryWithOwner(entry: entry, ownerId: characterId)
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

            let entries = try await CharacterMiningAPI.shared.getMiningLedger(
                characterId: targetCharacterId,
                forceRefresh: forceRefresh
            )

            // 单人模式也创建所有者信息
            for entry in entries {
                allEntries.append(
                    MiningLedgerEntryWithOwner(entry: entry, ownerId: targetCharacterId)
                )
            }
        }

        // 更新缓存
        entriesWithOwner = allEntries

        return allEntries
    }

    /// 按日期聚合挖矿数据
    func aggregateDailyData() -> [DailyMiningSummary] {
        guard !entriesWithOwner.isEmpty else { return [] }

        // 按日期分组
        var groupedByDate: [Date: [MiningLedgerEntryWithOwner]] = [:]

        for entryWithOwner in entriesWithOwner {
            guard let date = FormatUtil.parseUTCDate(entryWithOwner.entry.date) else {
                continue
            }

            // 获取日期部分（去掉时间）
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let dayDate = calendar.date(from: components) else {
                continue
            }

            if groupedByDate[dayDate] == nil {
                groupedByDate[dayDate] = []
            }
            groupedByDate[dayDate]?.append(entryWithOwner)
        }

        // 对每个日期进行聚合
        var dailySummaries: [DailyMiningSummary] = []

        for (date, entries) in groupedByDate {
            // 按 type_id 合并数量
            var oreQuantities: [Int: Int] = [:] // [type_id: 总数量]
            var characterIds: Set<Int> = []

            for entryWithOwner in entries {
                oreQuantities[entryWithOwner.entry.type_id, default: 0] += entryWithOwner.entry.quantity
                characterIds.insert(entryWithOwner.ownerId)
            }

            // 转换为 MiningItemSummary 并排序
            let summaries = oreQuantities.map { typeId, quantity -> MiningItemSummary in
                let info =
                    itemInfoCache[typeId] ?? (
                        name: String(
                            format: NSLocalizedString("Mining_Unknown_Ore", comment: ""),
                            typeId
                        ),
                        iconFileName: IconManager.defaultItemIcon
                    )
                return MiningItemSummary(
                    id: typeId,
                    name: info.name,
                    iconFileName: info.iconFileName,
                    totalQuantity: quantity
                )
            }.sorted { first, second in
                // 按数量降序，数量相同按 type_id 升序
                if first.totalQuantity != second.totalQuantity {
                    return first.totalQuantity > second.totalQuantity
                }
                return first.id < second.id
            }

            // 计算总体积（数量 × 单位体积）
            let totalVolume = summaries.reduce(0.0) { total, summary in
                let volume = itemVolumeCache[summary.id] ?? 0.0
                return total + (Double(summary.totalQuantity) * volume)
            }

            let oreTypes = summaries.count
            let characterCount = characterIds.count

            dailySummaries.append(
                DailyMiningSummary(
                    date: date,
                    totalVolume: totalVolume,
                    oreTypes: oreTypes,
                    characterCount: characterCount,
                    entries: summaries,
                    rawEntries: entries
                )
            )
        }

        // 按日期倒序排序（最新的在前）
        return dailySummaries.sorted { $0.date > $1.date }
    }
}

struct MiningLedgerView: View {
    @StateObject private var viewModel: MiningLedgerViewModel
    @State private var showSettingsSheet = false

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    // 使用FormatUtil进行日期处理，无需自定义格式化器

    init(characterId: Int, databaseManager: DatabaseManager) {
        // 构造表达式内联在 autoclosure 中，避免父视图每次重渲染都新建 ViewModel；
        // 数据加载已在 ViewModel init 中启动
        _viewModel = StateObject(wrappedValue: MiningLedgerViewModel(
            characterId: characterId, databaseManager: databaseManager
        ))
    }

    /// 判断日期是否在近7天内
    private func isDateInLast7Days(_ date: Date) -> Bool {
        let now = Date()
        // 获取今天的开始时间（去掉时分秒）
        let todayStart = calendar.startOfDay(for: now)
        // 获取7天前的开始时间
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: todayStart) else {
            return false
        }
        // 获取日期的开始时间
        let dateStart = calendar.startOfDay(for: date)
        // 判断日期是否在7天前到今天之间（包含今天）
        return dateStart >= sevenDaysAgo && dateStart <= todayStart
    }

    var body: some View {
        let dailySummaries = viewModel.aggregateDailyData()

        List {
            if viewModel.isLoading {
                VStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)

                    // 显示加载进度（如果有多人物模式且正在加载）
                    if let progress = viewModel.loadingProgress, progress.total > 1 {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Mining_Loading_Progress", comment: "已加载人物 %d/%d"), progress.current, progress.total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if dailySummaries.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                // 分离近7天和其他数据
                let last7DaysSummaries = dailySummaries.filter { isDateInLast7Days($0.date) }
                let otherSummaries = dailySummaries.filter { !isDateInLast7Days($0.date) }

                // 近7天 Section
                if !last7DaysSummaries.isEmpty {
                    Section(header: Text(NSLocalizedString("Mining_Detail_Last_7_Days", comment: "近7天"))) {
                        ForEach(last7DaysSummaries) { summary in
                            NavigationLink(destination: DailyMiningDetailView(
                                summary: summary,
                                databaseManager: viewModel.databaseManager
                            )) {
                                DailyMiningSummaryRow(summary: summary)
                            }
                            .listRowInsets(
                                EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
                            )
                        }
                    }
                }

                // 其他 Section
                if !otherSummaries.isEmpty {
                    Section(header: Text(NSLocalizedString("Mining_Detail_Other", comment: "其他"))) {
                        ForEach(otherSummaries) { summary in
                            NavigationLink(destination: DailyMiningDetailView(
                                summary: summary,
                                databaseManager: viewModel.databaseManager
                            )) {
                                DailyMiningSummaryRow(summary: summary)
                            }
                            .listRowInsets(
                                EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadMiningData(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Main_Mining_Ledger", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
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
            MiningSettingsSheet(viewModel: viewModel)
        }
    }
}

struct MiningSettingsSheet: View {
    @ObservedObject var viewModel: MiningLedgerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $viewModel.multiCharacterMode) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Mining_Settings_Multi_Character", comment: "多人物聚合"
                                )
                            )
                            Text(
                                NSLocalizedString(
                                    "Mining_Settings_Multi_Character_Description",
                                    comment: "聚合显示多个角色的挖矿记录数据"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            .navigationTitle(NSLocalizedString("Mining_Settings_Title", comment: "设置"))
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

/// 每日汇总行视图
struct DailyMiningSummaryRow: View {
    let summary: DailyMiningSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 日期
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(FormatUtil.formatDateToLocalDate(summary.date))
                    .font(.headline)
                Spacer()
            }

            // 统计信息
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Mining_Detail_Total_Volume", comment: "总体积"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(FormatUtil.format(summary.totalVolume)) m³")
                        .font(.subheadline)
                        .fontDesign(.monospaced)
                        .foregroundColor(Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Mining_Detail_Characters", comment: "参与人物"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(summary.characterCount)")
                        .font(.subheadline)
                        .fontDesign(.monospaced)
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Mining_Detail_Ore_Types", comment: "矿石种类"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(summary.oreTypes)")
                        .font(.subheadline)
                        .fontDesign(.monospaced)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 排序方式枚举
enum MiningChartSortType: String, CaseIterable {
    case volume = "Volume"
    case quantity = "Quantity"
    case price = "Price"

    var localizedName: String {
        switch self {
        case .volume:
            return NSLocalizedString("Mining_Chart_Sort_Volume", comment: "按体积")
        case .quantity:
            return NSLocalizedString("Mining_Chart_Sort_Quantity", comment: "按数量")
        case .price:
            return NSLocalizedString("Mining_Chart_Sort_Price", comment: "按估价")
        }
    }
}

/// 每日详情视图
struct DailyMiningDetailView: View {
    let summary: DailyMiningSummary
    let databaseManager: DatabaseManager
    @State private var itemVolumes: [Int: Double] = [:]
    @State private var solarSystemNames: [Int: String] = [:]
    @State private var solarSystemSecurities: [Int: Double] = [:]
    @State private var marketPrices: [Int: MarketPriceData] = [:]
    @State private var oreColors: [Int: Color] = [:] // 矿石颜色（从数据库加载）
    @State private var oreColorsLoaded = false // 矿石颜色是否已加载完成
    @State private var sortType: MiningChartSortType = .volume
    @AppStorage("selectedDatabaseLanguage") private var selectedDatabaseLanguage: String = "en"

    var body: some View {
        List {
            // 统计信息卡片
            Section(header: Text(NSLocalizedString("Mining_Detail_Overview", comment: "总览"))) {
                HStack(alignment: .center, spacing: 0) {
                    // 左侧栏：总体积
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Mining_Detail_Total_Volume", comment: "总体积"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(FormatUtil.format(summary.totalVolume)) m³")
                            .font(.title3)
                            .fontDesign(.monospaced)
                            .foregroundColor(Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255))
                    }

                    Spacer(minLength: 0)

                    // 右侧内容（右对齐）
                    VStack(alignment: .trailing, spacing: 8) {
                        // 上边：矿石种类（右对齐）
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Mining_Detail_Ore_Types", comment: "矿石种类"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(summary.oreTypes)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(.green)
                        }

                        // 下边：参与人物（右对齐，如果有多个）
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Mining_Detail_Characters", comment: "参与人物"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(summary.characterCount)")
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(.blue)
                        }
                    }
                    .overlay(alignment: .leading) {
                        // 竖线分割，跟随右侧内容的左边
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .offset(x: -12) // 向左偏移12，与spacing一致
                    }
                }
                .padding(.vertical, 4)
            }

            // 各星系挖矿量图表
            if !summary.rawEntries.isEmpty {
                let systemCount = min(getSystemCount(), MAX_CHART_DATA_POINTS) // 最多显示N个
                Section(header: Text(NSLocalizedString("Mining_Detail_By_System", comment: "各星系挖矿量"))) {
                    MiningSystemVolumeChartView(
                        entries: summary.rawEntries,
                        itemVolumes: itemVolumes,
                        solarSystemNames: solarSystemNames,
                        solarSystemSecurities: solarSystemSecurities,
                        dataCount: systemCount,
                        sortType: sortType,
                        marketPrices: marketPrices
                    )
                    .frame(height: calculateChartHeight(dataCount: systemCount))
                    .padding(.vertical, 8)
                }
            }

            // 各人物挖矿量图表（即使只有一个人物也显示）
            if summary.characterCount >= 1, !summary.rawEntries.isEmpty {
                let characterCount = min(summary.characterCount, MAX_CHART_DATA_POINTS) // 最多显示N个
                Section(header: Text(NSLocalizedString("Mining_Detail_By_Character", comment: "各人物挖矿量"))) {
                    MiningCharacterVolumeChartView(
                        entries: summary.rawEntries,
                        itemVolumes: itemVolumes,
                        dataCount: characterCount,
                        sortType: sortType,
                        marketPrices: marketPrices
                    )
                    .frame(height: calculateChartHeight(dataCount: characterCount))
                    .padding(.vertical, 8)
                }
            }

            // 各矿石类型挖矿量图表（等待颜色加载完成后再显示）
            if !summary.entries.isEmpty && oreColorsLoaded {
                let oreTypeCount = min(summary.entries.count, MAX_CHART_DATA_POINTS) // 最多显示N个
                Section(header: Text(NSLocalizedString("Mining_Detail_By_Ore_Type", comment: "各矿石类型挖矿量"))) {
                    MiningOreTypeVolumeChartView(
                        entries: summary.entries,
                        itemVolumes: itemVolumes,
                        dataCount: oreTypeCount,
                        sortType: sortType,
                        marketPrices: marketPrices,
                        databaseColors: oreColors
                    )
                    .frame(height: calculateChartHeight(dataCount: oreTypeCount))
                    .padding(.vertical, 8)
                }
            }

            // 矿石明细
            Section(header: oreListHeader, footer: estimatePriceFooter) {
                ForEach(summary.entries) { entry in
                    DailyMiningItemRow(
                        entry: entry,
                        databaseManager: databaseManager,
                        volume: itemVolumes[entry.id]
                    )
                    .listRowInsets(
                        EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(FormatUtil.formatDateToLocalDate(summary.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(MiningChartSortType.allCases, id: \.self) { type in
                        Button(action: {
                            sortType = type
                        }) {
                            HStack {
                                Text(type.localizedName)
                                if sortType == type {
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
        .task {
            // 加载矿石体积信息、星系名称、矿石颜色和市场价格
            await loadItemVolumes()
            await loadSolarSystemNames()
            await loadOreColors()
            await loadMarketPrices()
        }
    }

    /// 计算图表高度（基于固定的类别间距）
    /// 每个类别占用固定空间（包括柱子和间距），确保视觉体验一致
    private func calculateChartHeight(dataCount: Int) -> CGFloat {
        let categorySpacing: CGFloat = 40 // 每个类别占用的固定空间（包括柱子和间距）
        // 严格按数据数量计算，确保每个柱子的宽度和间距都固定
        return CGFloat(dataCount) * categorySpacing
    }

    /// 获取星系数量
    private func getSystemCount() -> Int {
        let systemIds = Set(summary.rawEntries.map { $0.entry.solar_system_id })
        return systemIds.count
    }

    /// 加载矿石体积信息
    private func loadItemVolumes() async {
        let typeIds = summary.entries.map { $0.id }
        guard !typeIds.isEmpty else { return }

        var volumes: [Int: Double] = [:]
        for typeId in typeIds {
            if let volume = ItemInfoMap.typeInfo(for: typeId)?.volume {
                volumes[typeId] = volume
            }
        }
        itemVolumes = volumes
    }

    /// 加载星系名称和安全等级（内存索引）
    private func loadSolarSystemNames() async {
        let systemIds = Set(summary.rawEntries.map { $0.entry.solar_system_id })
        guard !systemIds.isEmpty else { return }

        var names: [Int: String] = [:]
        var securities: [Int: Double] = [:]

        for systemId in systemIds {
            if let systemName = SDEMemoryStore.solarSystemName(for: systemId) {
                names[systemId] = systemName
            }
            if let info = SDEMemoryStore.universeSystems[systemId] {
                securities[systemId] = info.security
            }
        }

        solarSystemNames = names
        solarSystemSecurities = securities
    }

    /// 矿石列表 Header（带复制按钮）
    private var oreListHeader: some View {
        HStack {
            Text(NSLocalizedString("Mining_Detail_Ore_List", comment: "矿石明细"))
            Spacer()
            HStack(spacing: 8) {
                Button(action: {
                    copyOreList(useEnglish: false)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                        Text(NSLocalizedString("Mining_Detail_Copy", comment: "复制"))
                            .font(.caption)
                    }
                }
                if selectedDatabaseLanguage != "en" {
                    Button(action: {
                        copyOreList(useEnglish: true)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                            Text(NSLocalizedString("Mining_Detail_Copy_EN", comment: "复制(en)"))
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    /// 复制矿石列表
    private func copyOreList(useEnglish: Bool) {
        var textLines: [String] = []

        for entry in summary.entries {
            let name: String
            if useEnglish {
                // 查询英文名称
                name = getEnglishName(for: entry.id) ?? entry.name
            } else {
                name = entry.name
            }

            let quantity = FormatUtil.format(Double(entry.totalQuantity))
            textLines.append("\(name)\t\(quantity)")
        }

        let text = textLines.joined(separator: "\n")
        UIPasteboard.general.string = text
    }

    /// 获取英文名称
    private func getEnglishName(for typeId: Int) -> String? {
        guard let enName = ItemInfoMap.typeInfo(for: typeId)?.enName, !enName.isEmpty else {
            return nil
        }
        return enName
    }

    /// 估价 Footer
    private var estimatePriceFooter: some View {
        HStack {
            Text(NSLocalizedString("Mining_Detail_Estimate_Price", comment: "估价"))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if marketPrices.isEmpty {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                let totalPrice = calculateTotalEstimatePrice()
                if totalPrice > 0 {
                    Text(FormatUtil.formatISK(totalPrice))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(NSLocalizedString("Ore_Refinery_Result_No_Price", comment: "暂无价格信息"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 加载矿石颜色（从 SDEMemoryStore.oreColors）
    private func loadOreColors() async {
        let typeIds = summary.entries.map { $0.id }
        guard !typeIds.isEmpty else {
            await MainActor.run {
                oreColorsLoaded = true
            }
            return
        }

        var colors: [Int: Color] = [:]
        Logger.debug("开始查询矿石颜色，typeIds: \(typeIds)")

        for typeId in typeIds {
            if let hexColor = SDEMemoryStore.oreColor(for: typeId) {
                Logger.debug("找到颜色: typeId=\(typeId), hexColor=\(hexColor)")
                colors[typeId] = Color(hex: hexColor)
            }
        }

        Logger.debug("最终加载了 \(colors.count) 个矿石颜色")

        await MainActor.run {
            oreColors = colors
            oreColorsLoaded = true
        }
    }

    /// 加载市场价格
    private func loadMarketPrices() async {
        let typeIds = summary.entries.map { $0.id }
        guard !typeIds.isEmpty else { return }

        let prices = await MarketPriceUtil.getMarketPrices(typeIds: typeIds)
        await MainActor.run {
            marketPrices = prices
        }
    }

    /// 计算总估价
    private func calculateTotalEstimatePrice() -> Double {
        var total: Double = 0

        for entry in summary.entries {
            if let priceData = marketPrices[entry.id] {
                // 使用 averagePrice 进行估价
                total += priceData.averagePrice * Double(entry.totalQuantity)
            }
        }

        return total
    }
}

/// 每日详情页面的矿石行视图（显示数量和体积）
struct DailyMiningItemRow: View {
    let entry: MiningItemSummary
    let databaseManager: DatabaseManager
    let volume: Double? // 单位体积（m³）
    @State private var itemIcon: Image?

    /// 计算总体积
    private var totalVolume: Double? {
        guard let volume = volume else { return nil }
        return Double(entry.totalQuantity) * volume
    }

    var body: some View {
        NavigationLink {
            MarketItemDetailView(databaseManager: databaseManager, itemID: entry.id)
        } label: {
            HStack(spacing: 12) {
                // 矿石图标
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
                    Text(entry.name)
                        .font(.body)
                    HStack(spacing: 4) {
                        Text("× \(FormatUtil.format(Double(entry.totalQuantity)))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                        if let totalVolume = totalVolume {
                            Text("(\(FormatUtil.format(totalVolume)) m³)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 2)
        }
        .task {
            // 加载图标
            itemIcon = IconManager.shared.loadImage(for: entry.iconFileName)
        }
    }
}
