import SwiftUI

/// 按权重展示各段，统一使用 4 点高度、2 点间隙及圆角。
struct SegmentedProgressBar: View {
    struct Segment {
        let value: Double
        let color: Color
        var showsShimmer: Bool = false
    }

    let segments: [Segment]
    var height: CGFloat = 4
    var cornerRadius: CGFloat = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var visibleSegments: [Segment] {
        segments.filter { $0.value.isFinite && $0.value > 0 }
    }

    var body: some View {
        GeometryReader { geometry in
            let visible = visibleSegments
            let width = max(0, geometry.size.width)
            let gapCount = max(0, visible.count - 1)
            let gap = gapCount > 0 ? min(2, width / CGFloat(gapCount)) : 0
            let widths = segmentWidths(visible, available: max(0, width - gap * CGFloat(gapCount)))

            HStack(spacing: gap) {
                ForEach(visible.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(visible[index].color)
                        .frame(width: widths[index])
                        .overlay {
                            if visible[index].showsShimmer, widths[index] >= 16,
                               !reduceMotion, scenePhase == .active
                            {
                                ProgressShimmer(width: widths[index])
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
        }
        .frame(height: height)
    }

    /// 小段至少保留 2 点；其余宽度按比例分配，总宽度不超出容器。
    private func segmentWidths(_ segments: [Segment], available: CGFloat) -> [CGFloat] {
        guard !segments.isEmpty else { return [] }
        let minimum = min(2, available / CGFloat(segments.count))
        let largest = segments.map(\.value).max() ?? 1
        let weights = segments.map { $0.value / largest }
        var widths = Array(repeating: CGFloat.zero, count: segments.count)
        var remaining = Array(segments.indices)
        var remainingWidth = available

        while !remaining.isEmpty {
            let total = remaining.reduce(0) { $0 + weights[$1] }
            let small = remaining.filter {
                remainingWidth * CGFloat(weights[$0] / total) < minimum
            }
            if small.isEmpty {
                for index in remaining {
                    widths[index] = remainingWidth * CGFloat(weights[index] / total)
                }
                break
            }
            for index in small {
                widths[index] = minimum
                remainingWidth = max(0, remainingWidth - minimum)
            }
            remaining.removeAll { small.contains($0) }
        }
        return widths
    }
}

/// 仅在可见且允许动画时创建时间线，不递归调度延时任务。
private struct ProgressShimmer: View {
    let width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 4)
            let phase = min(cycle / 2.8, 1)
            let lightWidth = min(40, max(16, width * 0.2))
            LinearGradient(
                colors: [.white.opacity(0), .white.opacity(0.25), .white.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: lightWidth)
            .offset(x: -lightWidth + (width + lightWidth) * phase)
            .frame(width: width, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
