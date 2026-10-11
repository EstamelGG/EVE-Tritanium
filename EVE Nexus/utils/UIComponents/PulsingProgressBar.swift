import SwiftUI

/// 分段底条上的轻扫光，条长表示进度，扫光表示正在进行。
struct PulsingProgressBar: View {
    let progress: Double
    let color: Color
    let height: CGFloat
    let cornerRadius: CGFloat
    let showPulse: Bool

    init(
        progress: Double,
        color: Color = .blue,
        height: CGFloat = 4,
        cornerRadius: CGFloat = 2,
        showPulse: Bool = true
    ) {
        self.progress = progress.isFinite ? max(0, min(1, progress)) : 0
        self.color = color
        self.height = height
        self.cornerRadius = cornerRadius
        self.showPulse = showPulse
    }

    var body: some View {
        SegmentedProgressBar(
            segments: [
                .init(value: progress, color: color,
                      showsShimmer: showPulse && progress > 0 && progress < 1),
                .init(value: 1 - progress, color: .secondary.opacity(0.16)),
            ],
            height: height,
            cornerRadius: cornerRadius
        )
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(verbatim: "\(FormatUtil.format(progress * 100, maxFractionDigits: 1))%"))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // 不同进度示例
        VStack(alignment: .leading, spacing: 8) {
            Text("25% - 蓝色")
            PulsingProgressBar(progress: 0.25, color: .blue)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("50% - 绿色")
            PulsingProgressBar(progress: 0.5, color: .green)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("75% - 橙色")
            PulsingProgressBar(progress: 0.75, color: .orange)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("已完成 - 灰色（无脉动）")
            PulsingProgressBar(progress: 1.0, color: .gray)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("自定义高度和圆角")
            PulsingProgressBar(
                progress: 0.6,
                color: .purple,
                height: 8,
                cornerRadius: 4
            )
        }
    }
    .padding()
}
