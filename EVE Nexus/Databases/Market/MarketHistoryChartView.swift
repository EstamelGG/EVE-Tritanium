import Charts
import SwiftUI
import UIKit

/// A width-based row size stays stable when scrolling changes the viewport or navigation bar.
struct MarketHistoryChartLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        let proposedWidth = proposal.width ?? 360
        let width = proposedWidth.isFinite ? max(0, proposedWidth) : 360
        return CGSize(width: width, height: min(max(width * 0.55, 160), 300))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// 市场历史图表视图
struct MarketHistoryChartView: View, Equatable {
    let chartData: MarketHistoryChartData

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chartData === rhs.chartData
    }

    @AppStorage("selectedLanguage") private var selectedLanguage = "en"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// 短时间范围显示月/日，较长范围只显示月份。
    private func formatDateLabel(_ dateString: String) -> String {
        let components = dateString.split(separator: "-")
        guard components.count >= 2, let month = Int(components[1]), (1 ... 12).contains(month) else {
            return ""
        }
        if chartData.timeRange == .oneMonth, components.count == 3, let day = Int(components[2]) {
            return "\(month)/\(day)"
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

    private func dateLabelAnchor(for date: String) -> UnitPoint {
        guard chartData.xAxisDates.count > 1 else {
            // A lone month tick can still sit at the start of a multi-day series.
            return chartData.dates.count > 1 ? .topLeading : .top
        }
        if date == chartData.xAxisDates.first {
            return .topLeading
        }
        if date == chartData.xAxisDates.last {
            return .topTrailing
        }
        return .top
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
        // Measure once per chart update, rather than once for every overlay label.
        let priceAxisLabelWidth = self.priceAxisLabelWidth
        let volumeAxisLabelWidth = self.volumeAxisLabelWidth
        return Chart {
            ForEach(chartData.plottedHistory, id: \.date) { item in
                AreaMark(
                    x: .value("Date", chartData.datePositions[item.date] ?? 0),
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

            ForEach(chartData.plottedHistory, id: \.date) { item in
                // 成交量从数量轴的零点开始，与右侧刻度共用相同的比例。
                // 每根柱占一个数据间隔的 80%，宽度随横轴窗口同步缩放。
                let position = chartData.datePositions[item.date] ?? 0
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

            ForEach(chartData.plottedHistory, id: \.date) { item in
                // 价格线
                LineMark(
                    x: .value("Date", chartData.datePositions[item.date] ?? 0),
                    y: .value("Price", chartData.axisScale.normalizedPrice(item.average))
                )
                .foregroundStyle(priceColor)
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: chartData.xDomain)
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
            // Explicit date ticks keep density stable for each selected time range.
            AxisMarks(values: chartData.xAxisDates.compactMap { chartData.datePositions[$0] }) { value in
                if let position = value.as(Double.self),
                   chartData.plottedHistory.indices.contains(Int(position))
                {
                    let dateStr = chartData.plottedHistory[Int(position)].date
                    // Align the outer labels inward so full dates stay inside the plot bounds.
                    AxisValueLabel(
                        anchor: dateLabelAnchor(for: dateStr),
                        collisionResolution: .greedy,
                        orientation: .horizontal
                    ) {
                        Text(formatDateLabel(dateStr))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    AxisGridLine()
                }
            }
        }
        .padding(.leading, priceAxisLabelWidth + axisLabelSpacing)
        .padding(.trailing, volumeAxisLabelWidth + axisLabelSpacing)
        // The row supplies the total height; the chart fills the space below the legend.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
