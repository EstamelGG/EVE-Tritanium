import Foundation

/// Prepared once after history loads. View reconstruction during scrolling only reuses this object.
final class MarketHistoryChartData {
    let dates: [String]
    let axisScale: MarketHistoryAxisScale
    let plottedHistory: [MarketHistory]
    let datePositions: [String: Double]
    let xDomain: ClosedRange<Double>
    let timeRange: PriceHistoryTimeRange
    let xAxisDates: [String]

    /// 初始化时计算月份第一天和图表数据
    init(history: [MarketHistory], fullHistory: [MarketHistory]? = nil, timeRange: PriceHistoryTimeRange = .oneYear) {
        self.timeRange = timeRange
        // 只取最新的360个数据点进行显示
        let sortedHistory = history.sorted { $0.date < $1.date }
        let displayHistory = Array(sortedHistory.suffix(360))

        // 保留完整序列及稳定的横坐标，只缩放可见窗口，避免切换时重建折线。
        let allHistory = Array((fullHistory ?? history).sorted { $0.date < $1.date }.suffix(360))
        plottedHistory = allHistory
        let positions = Dictionary(uniqueKeysWithValues: allHistory.enumerated().map {
            ($0.element.date, Double($0.offset))
        })
        datePositions = positions
        let firstPosition = displayHistory.first.flatMap { positions[$0.date] } ?? 0
        let lastPosition = displayHistory.last.flatMap { positions[$0.date] } ?? firstPosition
        xDomain = (firstPosition - 0.5) ... (lastPosition + 0.5)

        // 计算图表数据
        let dates = displayHistory.map { $0.date }
        let priceValues = displayHistory.map { $0.average }
        let volumeValues = displayHistory.map { Double($0.volume) }

        // 初始化图表数据
        self.dates = dates
        axisScale = MarketHistoryAxisScale(prices: priceValues, volumes: volumeValues)

        switch timeRange {
        case .oneMonth:
            // Show the actual start, midpoint and end, even when trading days are sparse.
            let indices = Set([0, dates.count / 2, dates.count - 1]).sorted()
            xAxisDates = indices.compactMap { dates.indices.contains($0) ? dates[$0] : nil }
        case .threeMonths:
            xAxisDates = Self.calculateFirstDaysOfMonth(in: dates).sorted()
        case .oneYear:
            let monthDates = Self.calculateFirstDaysOfMonth(in: dates).sorted()
            xAxisDates = monthDates.enumerated().compactMap { index, date in
                index.isMultiple(of: 2) ? date : nil
            }
        }
    }

    /// 静态方法计算所有月份的第一个数据点
    private static func calculateFirstDaysOfMonth(in dates: [String]) -> Set<String> {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var result = Set<String>()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        var lastMonth: String? = nil

        // 按日期排序
        let sortedDates = dates.sorted()

        for dateString in sortedDates {
            guard dateFormatter.date(from: dateString) != nil else { continue }
            let currentMonth = String(dateString.prefix(7))

            // Compare year and month together, including sparse history across years.
            if currentMonth != lastMonth {
                result.insert(dateString)
            }

            lastMonth = currentMonth
        }

        return result
    }
}
