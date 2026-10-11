import Charts
import SwiftUI
import UIKit

/// 市场历史图表视图
struct MarketHistoryChartView: View {
    let history: [MarketHistory]
    let orders: [MarketOrder]
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Keep axis labels in sync with the currently displayed history.
    private let monthAxisDates: Set<String>
    private let priceColor = Color.blue
    private let volumeColor = Color.gray.opacity(0.8)
    private let axisLabelSpacing: CGFloat = 2

    private var priceAxisLabelWidth: CGFloat {
        axisLabelWidth(for: chartData.axisScale.priceTicks, maxFractionDigits: 3)
    }

    private var volumeAxisLabelWidth: CGFloat {
        axisLabelWidth(for: chartData.axisScale.volumeTicks)
    }

    private func axisLabelWidth(for values: [Double], maxFractionDigits: Int = 1) -> CGFloat {
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        return ceil(values.map {
            (formatAxisValue($0, maxFractionDigits: maxFractionDigits) as NSString)
                .size(withAttributes: [.font: font]).width
        }.max() ?? 0)
    }

    /// 缓存图表相关的计算结果
    private let chartData: ChartData
    private let plottedHistory: [MarketHistory]
    private let datePositions: [String: Double]
    private let xDomain: ClosedRange<Double>

    /// 图表数据结构
    private struct ChartData {
        let dates: [String]
        let axisScale: MarketHistoryAxisScale
    }

    /// 初始化时计算月份第一天和图表数据
    init(history: [MarketHistory], orders: [MarketOrder], fullHistory: [MarketHistory]? = nil) {
        // 只取最新的360个数据点进行显示
        let sortedHistory = history.sorted { $0.date < $1.date }
        let displayHistory = Array(sortedHistory.suffix(360))

        self.history = displayHistory
        self.orders = orders

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
        chartData = ChartData(
            dates: dates,
            axisScale: MarketHistoryAxisScale(prices: priceValues, volumes: volumeValues)
        )

        let monthDates = Self.calculateFirstDaysOfMonth(in: dates).sorted()
        monthAxisDates = Set(monthDates.enumerated().compactMap { index, date in
            monthDates.count > 10 && !index.isMultiple(of: 2) ? nil : date
        })
    }

    /// 格式化日期显示（只显示月份）
    private func formatMonth(_ dateString: String) -> String {
        // Labels contain only the month, never an automatically formatted date or day.
        let components = dateString.split(separator: "-")
        guard components.count >= 2, let month = Int(components[1]), (1 ... 12).contains(month) else {
            return ""
        }
        if selectedLanguage.hasPrefix("zh") {
            return "\(month)月"
        }
        let locale = Locale(identifier: selectedLanguage)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        let label = formatter.shortStandaloneMonthSymbols[month - 1]
        return selectedLanguage.hasPrefix("en") ? label.uppercased(with: locale) : label
    }

    /// 静态方法计算所有月份的第一个数据点
    private static func calculateFirstDaysOfMonth(in dates: [String]) -> Set<String> {
        let dateFormatter = DateFormatter()
        Logger.info("提取横坐标月份点")
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

    private func formatAxisValue(_ value: Double, maxFractionDigits: Int = 1) -> String {
        let units: [(threshold: Double, label: String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1000, "K"),
            (1, ""),
        ]
        let unit = units.first { abs(value) >= $0.threshold } ?? (threshold: 1, label: "")
        return FormatUtil.format(value / unit.threshold, maxFractionDigits: maxFractionDigits) + unit.label
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(priceColor)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(verbatim: "ISK")
                        .foregroundStyle(priceColor)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(volumeColor)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(NSLocalizedString("Main_Market_Transactions_Quantity", comment: "数量"))
                        .foregroundStyle(volumeColor)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            historyChart
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: chartData.dates)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: chartData.axisScale)
        }
        .padding(.top, 8)
    }

    private var historyChart: some View {
        // 使用缓存的图表数据
        Chart {
            ForEach(plottedHistory, id: \.date) { item in
                AreaMark(
                    x: .value("Date", datePositions[item.date] ?? 0),
                    yStart: .value("PriceBaseline", 0.0),
                    yEnd: .value("Price", chartData.axisScale.normalizedPrice(item.average))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [priceColor.opacity(0.14), priceColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(plottedHistory, id: \.date) { item in
                // 成交量从数量轴的零点开始，与右侧刻度共用相同的比例。
                // 每根柱占一个数据间隔的 80%，宽度随横轴窗口同步缩放。
                let position = datePositions[item.date] ?? 0
                RectangleMark(
                    xStart: .value("DateStart", position - 0.4),
                    xEnd: .value("DateEnd", position + 0.4),
                    yStart: .value("VolumeStart", 0.0),
                    yEnd: .value(
                        "VolumeEnd",
                        chartData.axisScale.normalizedVolume(Double(item.volume))
                    )
                )
                .foregroundStyle(volumeColor)
            }

            ForEach(plottedHistory, id: \.date) { item in
                // 价格线
                LineMark(
                    x: .value("Date", datePositions[item.date] ?? 0),
                    y: .value("Price", chartData.axisScale.normalizedPrice(item.average))
                )
                .foregroundStyle(priceColor)
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0.0 ... 1.0)
        .chartYAxis {
            AxisMarks(position: .leading, values: chartData.axisScale.gridPositions) { _ in
                AxisGridLine()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geometry[plotAnchor]
                    // Ordinary SwiftUI labels refresh even when Charts reuses unchanged axis positions.
                    ForEach(Array(chartData.axisScale.gridPositions.enumerated()), id: \.offset) { index, position in
                        if let y = proxy.position(forY: position) {
                            Text(formatAxisValue(chartData.axisScale.priceTicks[index], maxFractionDigits: 3))
                                .foregroundStyle(priceColor)
                                .frame(width: priceAxisLabelWidth, alignment: .trailing)
                                .position(
                                    x: plotFrame.minX - axisLabelSpacing - priceAxisLabelWidth / 2,
                                    y: plotFrame.minY + y
                                )
                            Text(formatAxisValue(chartData.axisScale.volumeTicks[index]))
                                .foregroundStyle(volumeColor)
                                .frame(width: volumeAxisLabelWidth, alignment: .leading)
                                .position(
                                    x: plotFrame.maxX + axisLabelSpacing + volumeAxisLabelWidth / 2,
                                    y: plotFrame.minY + y
                                )
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .transaction { $0.animation = nil }
                }
            }
            .allowsHitTesting(false)
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(.gray.opacity(0.1))
                .clipped()
        }
        .chartXAxis {
            // 显式保留月份标签，连续坐标仅用于平滑缩放。
            AxisMarks(values: monthAxisDates.sorted().compactMap { datePositions[$0] }) { value in
                if let position = value.as(Double.self),
                   plottedHistory.indices.contains(Int(position))
                {
                    let dateStr = plottedHistory[Int(position)].date
                    AxisValueLabel(anchor: .top) {
                        Text(formatMonth(dateStr))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    AxisGridLine()
                }
            }
        }
        .padding(.leading, priceAxisLabelWidth + axisLabelSpacing)
        .padding(.trailing, volumeAxisLabelWidth + axisLabelSpacing)
        .frame(height: 200)
    }
}
