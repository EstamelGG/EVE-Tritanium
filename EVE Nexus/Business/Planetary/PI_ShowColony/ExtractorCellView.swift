import Foundation
import SwiftUI

// MARK: - 图表视图

struct ExtractorYieldChartView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let yields: [(cycle: Int, yield: Int)]
    let currentCycle: Int
    let maxYield: Int
    let totalCycles: Int
    let cycleTime: Int
    let installTime: String
    let expiryTime: String
    let isLive: Bool
    let currentTime: Date

    // 图表常量
    private let chartHeight: CGFloat = 160
    private let yAxisWidth: CGFloat = 40
    private let gridLines: Int = 5

    init(extractor: PlanetaryExtractor, installTime: String, expiryTime: String?, currentTime: Date, isLive: Bool = true) {
        self.isLive = isLive
        guard let qtyPerCycle = extractor.qtyPerCycle,
              let cycleTime = extractor.cycleTime,
              let expiryTime = expiryTime
        else {
            yields = []
            currentCycle = 0
            maxYield = 0
            totalCycles = 0
            cycleTime = 0
            self.installTime = ""
            self.expiryTime = ""
            self.currentTime = currentTime
            return
        }

        let calculator = ExtractorYieldCalculator(
            quantityPerCycle: qtyPerCycle, cycleTime: cycleTime
        )
        currentCycle = ExtractorYieldCalculator.getCurrentCycle(
            installTime: installTime, expiryTime: expiryTime, cycleTime: cycleTime, currentTime: currentTime
        )
        totalCycles = ExtractorYieldCalculator.calculateTotalCycles(
            installTime: installTime, expiryTime: expiryTime, cycleTime: cycleTime
        )
        self.cycleTime = cycleTime
        self.installTime = installTime
        self.expiryTime = expiryTime
        self.currentTime = currentTime

        // 计算所有周期的数据
        let curve = calculator.curve(startCycle: 0, endCycle: totalCycles)
        yields = curve.yields
        maxYield = Int(Double(curve.maximumYield) * 1.1)
    }

    private func formatYAxisLabel(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return "\(value)"
    }

    private func formatElapsedTime(installTime: String) -> String {
        guard let installDate = ExtractorYieldCalculator.parsedDate(installTime) else {
            return FormatUtil.formatClockDuration(0)
        }

        // 检查是否所有周期都已结束
        if currentCycle == -1 {
            return FormatUtil.formatClockDuration(0)
        }

        let elapsedTime = currentTime.timeIntervalSince(installDate)
        let cycleElapsed = elapsedTime.truncatingRemainder(dividingBy: Double(cycleTime))
        return FormatUtil.formatClockDuration(cycleElapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 图表区域
            HStack(alignment: .center, spacing: 0) {
                // Y轴
                ZStack(alignment: .trailing) {
                    // Y轴标签
                    VStack(spacing: 0) {
                        ForEach(0 ... gridLines, id: \.self) { i in
                            Text(formatYAxisLabel(maxYield * (gridLines - i) / gridLines))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary)
                                .frame(height: chartHeight / CGFloat(gridLines))
                        }
                    }
                }
                .frame(width: yAxisWidth)

                // 图表主体
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // 背景和边框
                        Rectangle()
                            .fill(Color(UIColor.systemBackground))
                            .border(Color.gray.opacity(0.2), width: 1)

                        // 网格线
                        VStack(spacing: 0) {
                            ForEach(0 ... gridLines, id: \.self) { i in
                                if i < gridLines {
                                    Spacer()
                                }
                                Divider()
                                    .background(Color.gray.opacity(0.2))
                            }
                        }

                        // 垂直网格线
                        HStack(spacing: 0) {
                            ForEach(0 ... 4, id: \.self) { i in
                                if i > 0 {
                                    Divider()
                                        .background(Color.gray.opacity(0.2))
                                }
                                if i < 4 {
                                    Spacer()
                                }
                            }
                        }

                        // 柱状图
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(yields, id: \.cycle) { yield in
                                Rectangle()
                                    .fill(
                                        currentCycle != -1 && yield.cycle == currentCycle + 1
                                            ? PlanetaryFacilityColors.extractorChartCurrentCycle : PlanetaryFacilityColors.extractorChartOtherCycle
                                    )
                                    .frame(
                                        width: (geometry.size.width - CGFloat(yields.count - 1))
                                            / CGFloat(yields.count),
                                        height: CGFloat(yield.yield) / CGFloat(maxYield)
                                            * chartHeight
                                    )
                            }
                        }
                    }
                }
                .frame(height: chartHeight)
                .background(Color(UIColor.systemBackground))
                .border(Color.gray.opacity(0.2), width: 1)
            }
            .padding(.horizontal, 16)

            // 统计信息
            ExtractorStatsView(
                yields: yields,
                currentCycle: currentCycle,
                cycleTime: cycleTime,
                installTime: installTime,
                expiryTime: expiryTime,
                currentTime: currentTime,
                isLive: isLive,
                formatElapsedTime: formatElapsedTime
            )
        }
        .padding(.bottom, 8)
        .padding(.horizontal, -16)
    }
}

// MARK: - 统计信息视图

struct ExtractorStatsView: View {
    @Environment(\.locale) private var displayLocale
    @Environment(\.timeZone) private var displayTimeZone
    let yields: [(cycle: Int, yield: Int)]
    let currentCycle: Int
    let cycleTime: Int
    let installTime: String
    let expiryTime: String
    let currentTime: Date
    var isLive: Bool = true
    let formatElapsedTime: (String) -> String

    var body: some View {
        HStack {
            // 标题列
            VStack(alignment: .trailing) {
                Text(NSLocalizedString("Total_Yield", comment: ""))
                Text(NSLocalizedString("Current_Cycle_Yield", comment: ""))
                Text(NSLocalizedString("Current_Cycle_Elapsed", comment: ""))
                Text(NSLocalizedString("Cycle_Time", comment: ""))
                Text(NSLocalizedString("Time_Remaining", comment: ""))
            }
            .foregroundColor(.primary)
            .font(.footnote)

            // 数值列
            VStack(alignment: .leading) {
                Text("\(yields.map { $0.yield }.reduce(0, +))")
                    .foregroundColor(.secondary)
                if let currentYield = yields.first(where: { $0.cycle == currentCycle + 1 }) {
                    Text("\(currentYield.yield)")
                        .foregroundColor(.teal)
                } else {
                    Text("0")
                        .foregroundColor(.teal)
                }
                let elapsedText = formatElapsedTime(installTime)
                Text(elapsedText)
                    .modifier(NumericTimeTransition(text: elapsedText, countsDown: false, isEnabled: isLive))
                    .foregroundColor(.secondary)
                Text(FormatUtil.formatClockDuration(TimeInterval(cycleTime)))
                    .foregroundColor(.secondary)
                if let expiryDate = ExtractorYieldCalculator.parsedDate(expiryTime) {
                    let timeRemaining = expiryDate.timeIntervalSince(currentTime)
                    let remainingText = FormatUtil.formatClockDuration(max(0, timeRemaining))
                    Text(remainingText)
                        .modifier(NumericTimeTransition(text: remainingText, countsDown: true, isEnabled: isLive && timeRemaining > 0))
                        .foregroundColor(timeRemaining > 24 * 3600 ? .secondary : .red)
                } else {
                    Text(FormatUtil.formatClockDuration(0))
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(.footnote, design: .monospaced))
        }
        .padding(.horizontal, 48)
    }
}
