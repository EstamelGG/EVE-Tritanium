import Foundation
import SwiftUI

struct CorpMoonMiningView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpMoonMiningViewModel

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CorpMoonMiningViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if let error = viewModel.error,
                      !viewModel.isLoading && viewModel.moonExtractions.isEmpty
            {
                // 显示错误信息
                ErrorStateSection(message: error.localizedDescription) {
                    Task {
                        do {
                            try await viewModel.fetchMoonExtractions(forceRefresh: true)
                        } catch {
                            Logger.error("重试加载月矿提取信息失败: \(error)")
                        }
                    }
                }
            } else if viewModel.moonExtractions.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else if viewModel.filteredExtractions.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } description: {
                    Text(NSLocalizedString("Main_Corporation_Moon_Mining_No_Data_For_Selected_Month", comment: "所选月份暂无数据"))
                }
            } else {
                Section(
                    header: Text(viewModel.selectedMonthHeader)
                ) {
                    ForEach(viewModel.filteredExtractions, id: \.moon_id) { extraction in
                        MoonExtractionRow(
                            extraction: extraction,
                            moonName: viewModel.moonNames[Int(extraction.moon_id)]
                                ?? NSLocalizedString(
                                    "Main_Corporation_Moon_Mining_Unknown_Moon", comment: ""
                                )
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_Moon_Mining", comment: ""))
        .refreshable {
            do {
                try await viewModel.fetchMoonExtractions(forceRefresh: true)
            } catch {
                if !(error is CancellationError) {
                    Logger.error("刷新月矿提取信息失败: \(error)")
                }
            }
        }
        .toolbar {
            // 只有当获取到数据时才显示筛选按钮
            if !viewModel.moonExtractions.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // 月份筛选选项
                        ForEach(viewModel.availableMonths) { month in
                            Button(action: {
                                viewModel.selectedMonth = month
                            }) {
                                HStack {
                                    Text(month.displayName)
                                    if viewModel.selectedMonth.id == month.id {
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
        }
    }
}

struct MoonExtractionRow: View {
    let extraction: MoonExtractionInfo
    let moonName: String

    private var daysUntilArrival: String {
        guard let arrivalDate = FormatUtil.parseUTCDate(extraction.chunk_arrival_time) else {
            return ""
        }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: now, to: arrivalDate)

        if let days = components.day {
            if days == 0 {
                return NSLocalizedString("Main_Corporation_Moon_Mining_Today", comment: "")
            } else if days > 0 {
                return String(
                    format: NSLocalizedString(
                        "Main_Corporation_Moon_Mining_Days_Later", comment: ""
                    ), days
                )
            }
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            // 月球图标
            Image("moon")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 44, height: 44)
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 44, height: 44)
                )
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                // 月球名称和倒计时
                HStack(spacing: 4) {
                    Text(moonName)
                        .font(.headline)
                    Text(daysUntilArrival)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // 矿石抵达时间
                Text(
                    NSLocalizedString("Main_Corporation_Moon_Mining_Chunk_Arrival", comment: "")
                        + extraction.chunk_arrival_time.toLocalTime()
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                // 自然碎裂时间
                Text(
                    NSLocalizedString("Main_Corporation_Moon_Mining_Natural_Decay", comment: "")
                        + extraction.natural_decay_time.toLocalTime()
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// ViewModel
@MainActor
class CorpMoonMiningViewModel: ObservableObject {
    @Published var moonExtractions: [MoonExtractionInfo] = []
    @Published var moonNames: [Int: String] = [:]
    @Published private(set) var isLoading = false
    @Published var error: Error?
    @Published var selectedMonth: MonthFilter = .all
    private let characterId: Int

    /// 月份筛选枚举
    enum MonthFilter: Identifiable, CaseIterable, Equatable {
        case all
        case month(Date)

        var id: String {
            switch self {
            case .all:
                return "all"
            case let .month(date):
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM"
                return formatter.string(from: date)
            }
        }

        var displayName: String {
            switch self {
            case .all:
                return NSLocalizedString("Main_Corporation_Moon_Mining_Filter_All", comment: "全部")
            case let .month(date):
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy年MM月"
                return formatter.string(from: date)
            }
        }

        static var allCases: [MonthFilter] {
            return [.all]
        }
    }

    /// 获取可用的月份列表（不包含"全部"选项）
    var availableMonths: [MonthFilter] {
        let calendar = Calendar.current
        var months: [MonthFilter] = []

        // 获取所有数据中的唯一月份
        var monthSet = Set<String>()
        for extraction in moonExtractions {
            guard let arrivalDate = FormatUtil.parseUTCDate(extraction.chunk_arrival_time) else {
                continue
            }
            let components = calendar.dateComponents([.year, .month], from: arrivalDate)
            if let year = components.year, let month = components.month {
                let monthKey = "\(year)-\(month)"
                if !monthSet.contains(monthKey) {
                    monthSet.insert(monthKey)
                    if let monthDate = calendar.date(from: DateComponents(year: year, month: month)) {
                        months.append(.month(monthDate))
                    }
                }
            }
        }

        // 按日期排序
        return months.sorted { first, second in
            switch (first, second) {
            case let (.month(date1), .month(date2)):
                return date1 < date2
            default:
                return false
            }
        }
    }

    /// 根据选中的月份过滤数据
    var filteredExtractions: [MoonExtractionInfo] {
        guard case let .month(selectedDate) = selectedMonth else {
            // 如果没有选中月份，返回空数组
            return []
        }

        let calendar = Calendar.current
        let selectedComponents = calendar.dateComponents([.year, .month], from: selectedDate)

        return moonExtractions.filter { extraction in
            guard let arrivalDate = FormatUtil.parseUTCDate(extraction.chunk_arrival_time) else {
                return false
            }
            let arrivalComponents = calendar.dateComponents([.year, .month], from: arrivalDate)
            return arrivalComponents.year == selectedComponents.year &&
                arrivalComponents.month == selectedComponents.month
        }
    }

    /// 当前选中月份的header文本
    var selectedMonthHeader: String {
        guard case let .month(selectedDate) = selectedMonth else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月"
        return formatter.string(from: selectedDate)
    }

    init(characterId: Int) {
        self.characterId = characterId
        // 在初始化时立即开始加载数据
        Task {
            do {
                try await fetchMoonExtractions()
            } catch {
                // 记录错误，由视图展示错误页（带重试）
                Logger.error("初始化加载月矿提取信息失败: \(error)")
                self.error = error
            }
        }
    }

    func fetchMoonExtractions(forceRefresh: Bool = false) async throws {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let extractions = try await CorpMoonExtractionAPI.shared.fetchMoonExtractions(
                characterId: characterId,
                forceRefresh: forceRefresh
            )

            // 排序月矿数据
            moonExtractions = extractions.sorted { first, second in
                first.chunk_arrival_time < second.chunk_arrival_time
            }

            // 如果有数据，批量获取月球名称
            if !moonExtractions.isEmpty {
                moonNames = DatabaseManager.shared.getCelestialNames(
                    itemIDs: moonExtractions.map { Int($0.moon_id) }
                )

                // 自动选择第一个月份
                let calendar = Calendar.current
                var monthSet = Set<String>()
                var firstMonth: MonthFilter?

                for extraction in moonExtractions {
                    guard let arrivalDate = FormatUtil.parseUTCDate(extraction.chunk_arrival_time) else {
                        continue
                    }
                    let components = calendar.dateComponents([.year, .month], from: arrivalDate)
                    if let year = components.year, let month = components.month {
                        let monthKey = "\(year)-\(month)"
                        if !monthSet.contains(monthKey) {
                            monthSet.insert(monthKey)
                            if firstMonth == nil, let monthDate = calendar.date(from: DateComponents(year: year, month: month)) {
                                firstMonth = .month(monthDate)
                            }
                        }
                    }
                }

                if let first = firstMonth, selectedMonth == .all {
                    selectedMonth = first
                }
            } else {
                moonNames.removeAll()
            }
        } catch {
            Logger.error("加载月矿提取信息失败: \(error)")
            self.error = error
            throw error
        }
    }
}

/// 使用FormatUtil进行日期转换
extension String {
    func toLocalTime() -> String {
        return FormatUtil.formatUTCToLocalTimeWithWeekday(self)
    }
}
