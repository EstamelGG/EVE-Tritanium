import SwiftUI

struct MarketHistorySparkline: View {
    let points: [WidgetMarketPoint]
    let color: Color

    static func change(in points: [WidgetMarketPoint]) -> Double? {
        guard points.count > 1, let first = points.first, let last = points.last,
              first.average > 0 else { return nil }
        return (last.average - first.average) / first.average
    }

    /// Inserts carry-forward hold points across multi-day gaps so missing days render
    /// as a flat horizontal line at the previous trading day's average, matching
    /// `MarketHistoryAPI.interpolateMarketHistory`.
    static func plottedPoints(from points: [WidgetMarketPoint]) -> [WidgetMarketPoint] {
        guard points.count > 1 else { return points }
        let daySeconds: TimeInterval = 86_400
        var result: [WidgetMarketPoint] = [points[0]]
        result.reserveCapacity(points.count * 2)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let gap = current.date.timeIntervalSince(previous.date)
            if gap > daySeconds + 1, previous.average != current.average {
                result.append(
                    WidgetMarketPoint(
                        date: current.date.addingTimeInterval(-daySeconds),
                        average: previous.average
                    )
                )
            }
            result.append(current)
        }
        return result
    }

    var body: some View {
        ZStack {
            MarketHistoryTrend(points: points, fillsArea: true)
                .fill(.linearGradient(
                    colors: [color.opacity(0.30), color.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            MarketHistoryTrend(points: points)
                .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct MarketHistoryTrend: Shape {
    let points: [WidgetMarketPoint]
    var fillsArea = false

    func path(in rect: CGRect) -> Path {
        let plotted = MarketHistorySparkline.plottedPoints(from: points)
        guard let first = plotted.first, let last = plotted.last, plotted.count > 1,
              let low = plotted.map(\.average).min(), let high = plotted.map(\.average).max()
        else { return Path() }
        let plot = rect.insetBy(dx: 1, dy: 2)
        guard plot.width > 0, plot.height > 0 else { return Path() }
        let duration = max(last.date.timeIntervalSince(first.date), 1)
        let range = high - low
        var path = Path()

        for (index, point) in plotted.enumerated() {
            let x = plot.minX + plot.width * point.date.timeIntervalSince(first.date) / duration
            let fraction = range > 0 ? (point.average - low) / range : 0.5
            let position = CGPoint(x: x, y: plot.maxY - fraction * plot.height)
            if index == 0 {
                path.move(to: position)
            } else {
                path.addLine(to: position)
            }
        }

        if fillsArea, let end = path.currentPoint {
            path.addLine(to: CGPoint(x: end.x, y: plot.maxY))
            path.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            path.closeSubpath()
        }

        return path
    }
}
