import SwiftUI

/// 容量状态枚举
private enum CapacityStatus {
    case normal // 正常（< 90%）
    case nearFull // 接近满（>= 90% 且 < 100%）
    case exceeded // 已满（>= 100%）
}

/// 仓储变化图表视图
struct StorageChangeChartView: View {
    let pinId: Int64
    let selectedMinutes: Int // 当前选中的分钟数（0表示实时，>0表示快照）
    let capacity: Double
    let storageVolumeCache: [Int64: [Int: Double]] // 存储设施体积缓存 [pinId: [分钟数: 体积]]

    // 图表常量
    private let chartHeight: CGFloat = 160
    private let yAxisWidth: CGFloat = 40
    private let gridLines: Int = 6

    @State private var chartCache = StorageChartCache()

    private var cacheInput: StorageChartInput {
        StorageChartInput(pinId: pinId, capacity: capacity, volumes: storageVolumeCache[pinId] ?? [:])
    }

    private var chartData: [StorageChartCache.Sample] {
        chartCache.samples
    }

    private var maxVolume: Double {
        chartCache.maxVolume
    }

    private func formatYAxisLabel(_ value: Double) -> String {
        // 确保显示整十位数
        let roundedValue = round(value)
        if roundedValue >= 1_000_000 {
            // 如果是百万级别，显示为整十万或整百万
            let millions = roundedValue / 1_000_000.0
            if millions.truncatingRemainder(dividingBy: 1.0) == 0 {
                return String(format: "%.0fM", millions)
            } else {
                return String(format: "%.1fM", millions)
            }
        } else if roundedValue >= 1000 {
            // 如果是千级别，显示为整千或整万
            let thousands = roundedValue / 1000.0
            if thousands.truncatingRemainder(dividingBy: 1.0) == 0 {
                return String(format: "%.0fK", thousands)
            } else {
                return String(format: "%.1fK", thousands)
            }
        } else {
            // 小于1000，直接显示整数
            return String(format: "%.0f", roundedValue)
        }
    }

    var body: some View {
        chartContent
            .onChange(of: cacheInput, initial: true) { _, input in
                chartCache.update(input)
            }
    }

    @ViewBuilder
    private var chartContent: some View {
        // 检查数据是否可用
        let pinCache = storageVolumeCache[pinId]
        let hasData = pinCache != nil && !pinCache!.isEmpty

        if chartData.isEmpty && !hasData {
            Text(NSLocalizedString("No_Chart_Data", comment: "无图表数据"))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // 图表区域
                HStack(alignment: .center, spacing: 0) {
                    // Y轴
                    ZStack(alignment: .trailing) {
                        // Y轴标签
                        VStack(spacing: 0) {
                            ForEach(0 ... gridLines, id: \.self) { i in
                                let isFirstOrLast = i == 0 || i == gridLines // 第一个（max点）或最后一个（0点）
                                Text(formatYAxisLabel(maxVolume * Double(gridLines - i) / Double(gridLines)))
                                    .font(.system(size: 9, weight: isFirstOrLast ? .semibold : .regular, design: .monospaced))
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

                            // 折线图和填充区域
                            if !chartData.isEmpty {
                                let chartWidth = geometry.size.width
                                let chartDataCount = chartData.count
                                let pointSpacing = chartDataCount > 1 ? chartWidth / CGFloat(chartDataCount - 1) : 0

                                // 计算当前选中时间点的X坐标（基于分钟数匹配）
                                let currentTimeX: CGFloat? = {
                                    if let index = chartData.firstIndex(where: { $0.hour == selectedMinutes }) {
                                        return CGFloat(index) * pointSpacing
                                    }
                                    return nil
                                }()

                                // 计算每个点的坐标和容量状态
                                let points: [(x: CGFloat, y: CGFloat, status: CapacityStatus)] = chartData.enumerated().map { index, data in
                                    let x = CGFloat(index) * pointSpacing
                                    let y = chartHeight - (CGFloat(data.volume) / CGFloat(maxVolume) * chartHeight)
                                    let capacityRatio = capacity > 0 ? data.volume / capacity : 0.0
                                    let status: CapacityStatus = {
                                        if capacityRatio >= 1.0 {
                                            return .exceeded // 已满：红色
                                        } else if capacityRatio >= 0.9 {
                                            return .nearFull // 接近满：橘色
                                        } else {
                                            return .normal // 正常：蓝色
                                        }
                                    }()
                                    return (x: x, y: y, status: status)
                                }

                                // 分段绘制填充区域和折线（根据容量状态使用不同颜色）
                                // 找到所有状态改变的位置
                                let segmentRanges: [(start: Int, end: Int, status: CapacityStatus)] = {
                                    var ranges: [(start: Int, end: Int, status: CapacityStatus)] = []
                                    var segmentStart = 0
                                    var currentStatus = points.first?.status ?? .normal

                                    for i in 1 ..< points.count {
                                        if points[i].status != currentStatus {
                                            // 状态改变，保存前一段
                                            ranges.append((start: segmentStart, end: i - 1, status: currentStatus))
                                            segmentStart = i
                                            currentStatus = points[i].status
                                        }
                                    }
                                    // 添加最后一段
                                    if segmentStart < points.count {
                                        ranges.append((start: segmentStart, end: points.count - 1, status: currentStatus))
                                    }
                                    return ranges
                                }()

                                // 先绘制所有段的填充（包括到下一段的连接点，使用前一个点的颜色）
                                ForEach(Array(segmentRanges.enumerated()), id: \.offset) { index, segment in
                                    let segmentPoints = Array(points[segment.start ... segment.end])
                                    let segmentColor: Color = {
                                        switch segment.status {
                                        case .normal:
                                            return PlanetaryFacilityColors.storageChartNormal
                                        case .nearFull:
                                            return PlanetaryFacilityColors.storageChartNearFull
                                        case .exceeded:
                                            return PlanetaryFacilityColors.storageChartExceeded
                                        }
                                    }()

                                    // 绘制填充：从当前段的第一个点到最后一个点，并包含到下一段的连接点（使用当前段的颜色）
                                    Path { path in
                                        if let firstPoint = segmentPoints.first {
                                            path.move(to: CGPoint(x: firstPoint.x, y: firstPoint.y))
                                            // 绘制当前段内的所有点
                                            for point in segmentPoints.dropFirst() {
                                                path.addLine(to: CGPoint(x: point.x, y: point.y))
                                            }
                                            // 如果这不是最后一段，包含到下一段的第一个点（使用当前段的颜色）
                                            let lastPointOnLine: CGPoint
                                            if index < segmentRanges.count - 1 {
                                                let nextSegment = segmentRanges[index + 1]
                                                let nextFirstPoint = points[nextSegment.start]
                                                path.addLine(to: CGPoint(x: nextFirstPoint.x, y: nextFirstPoint.y))
                                                lastPointOnLine = CGPoint(x: nextFirstPoint.x, y: nextFirstPoint.y)
                                            } else {
                                                lastPointOnLine = CGPoint(x: segmentPoints.last!.x, y: segmentPoints.last!.y)
                                            }
                                            // 闭合到底部：从最后一个点垂直到底部，然后水平回到起点，再垂直回到起点
                                            path.addLine(to: CGPoint(x: lastPointOnLine.x, y: chartHeight))
                                            path.addLine(to: CGPoint(x: firstPoint.x, y: chartHeight))
                                            path.closeSubpath()
                                        }
                                    }
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                segmentColor.opacity(0.3),
                                                segmentColor.opacity(0.1),
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                }

                                // 绘制折线：为每一对相邻的点绘制一条线段，使用前一个点的颜色（确保连接点有颜色）
                                ForEach(0 ..< (points.count - 1), id: \.self) { i in
                                    let currentPoint = points[i]
                                    let nextPoint = points[i + 1]

                                    // 使用前一个点的颜色
                                    let lineColor: Color = {
                                        switch currentPoint.status {
                                        case .normal:
                                            return PlanetaryFacilityColors.storageChartNormal
                                        case .nearFull:
                                            return PlanetaryFacilityColors.storageChartNearFull
                                        case .exceeded:
                                            return PlanetaryFacilityColors.storageChartExceeded
                                        }
                                    }()

                                    Path { path in
                                        path.move(to: CGPoint(x: currentPoint.x, y: currentPoint.y))
                                        path.addLine(to: CGPoint(x: nextPoint.x, y: nextPoint.y))
                                    }
                                    .stroke(lineColor, lineWidth: 2)
                                }

                                // 绘制当前时间点的垂直线
                                if let currentX = currentTimeX {
                                    Path { path in
                                        path.move(to: CGPoint(x: currentX, y: 0))
                                        path.addLine(to: CGPoint(x: currentX, y: chartHeight))
                                    }
                                    .stroke(PlanetaryFacilityColors.storageChartCurrentTimeLine, lineWidth: 1)
                                }
                            }
                        }
                    }
                    .frame(height: chartHeight)
                    .background(Color(UIColor.systemBackground))
                    .border(Color.gray.opacity(0.2), width: 1)
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
