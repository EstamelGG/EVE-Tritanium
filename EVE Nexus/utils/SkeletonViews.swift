import SwiftUI

// MARK: - 行内骨架条

/// 行内骨架条：几何与加载后的字段一致，数据到位后原位替换，避免视觉抖动
/// （用于列表行内单个字段的加载占位，如势力名称行）
struct EntitySkeletonBar: View {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 4
    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: width, height: height)
            .opacity(isPulsing ? 0.55 : 1)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .accessibilityHidden(true)
    }
}

/// 通用列表骨架屏行：可选左侧图标占位 + 文本条组 + 可选尾部数值条。
/// 用于列表初始加载场景，替代居中的 ProgressView，让用户预感到内容的形状。
struct ListSkeletonRow: View {
    /// 左侧图标尺寸；nil 表示无图标
    var iconSize: CGFloat? = 48
    var iconCornerRadius: CGFloat = 8
    /// 文本条宽度，按行排列（首行较深色，其余较浅色）
    var lineWidths: [CGFloat] = [140, 200]
    /// 尾部数值条宽度；nil 表示无尾部
    var trailingWidth: CGFloat?

    @State private var isPulsing = false

    private let barFill = Color.secondary.opacity(0.2)
    private let barFillLight = Color.secondary.opacity(0.15)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let iconSize {
                RoundedRectangle(cornerRadius: iconCornerRadius)
                    .fill(barFill)
                    .frame(width: iconSize, height: iconSize)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lineWidths.enumerated()), id: \.offset) { index, width in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == 0 ? barFill : barFillLight)
                        .frame(width: width, height: index == 0 ? 12 : 10)
                }
            }

            Spacer(minLength: 0)

            if let trailingWidth {
                RoundedRectangle(cornerRadius: 4)
                    .fill(barFillLight)
                    .frame(width: trailingWidth, height: 12)
            }
        }
        .padding(.vertical, 4)
        .opacity(isPulsing ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .accessibilityHidden(true)
    }
}

// MARK: - 预设样式

extension ListSkeletonRow {
    /// 战斗日志行（BRKillMailCell 轮廓）：48 图标 + 两行文本 + 尾部数值
    static var killMail: ListSkeletonRow {
        ListSkeletonRow(lineWidths: [140, 200], trailingWidth: 72)
    }

    /// 邮件行（头像 + 主题/发件人/时间三行）
    static var mail: ListSkeletonRow {
        ListSkeletonRow(lineWidths: [160, 120, 90])
    }

    /// 钱包日志行（无图标：左侧日期+笔数，右侧金额）
    static var walletJournal: ListSkeletonRow {
        ListSkeletonRow(iconSize: nil, lineWidths: [100, 70], trailingWidth: 80)
    }
}

// MARK: - 组合骨架

/// 钱包日志页骨架：汇总区（标题 + 三行标签/数值）+ 日期条目区，对应页面的两个 section
struct WalletJournalSkeleton: View {
    @State private var isPulsing = false

    private let barFill = Color.secondary.opacity(0.2)
    private let barFillLight = Color.secondary.opacity(0.15)

    var body: some View {
        // 汇总区：标题条 + 时间范围按钮条
        Section(
            header: HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(barFill)
                    .frame(width: 90, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(barFillLight)
                    .frame(width: 60, height: 12)
            }
        ) {
            // 三行「标签 + ISK 数值」（总收入/总支出/净收益）
            ForEach(0 ..< 3, id: \.self) { _ in
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barFill)
                        .frame(width: 70, height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barFillLight)
                        .frame(width: 110, height: 10)
                }
            }
        }
        .opacity(isPulsing ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .accessibilityHidden(true)

        // 日期条目区
        Section(
            header: RoundedRectangle(cornerRadius: 4)
                .fill(barFill)
                .frame(width: 110, height: 16)
        ) {
            ForEach(0 ..< 6, id: \.self) { _ in
                ListSkeletonRow.walletJournal
            }
        }
    }
}

/// 工业页骨架：槽位统计和任务行，与个人、军团工业列表共用。
struct IndustrySkeleton: View {
    var showsOperationRange = true
    var loadingMessages: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private func bar(_ width: CGFloat? = nil, height: CGFloat = 10) -> some View {
        RoundedRectangle(cornerRadius: min(4, height / 2))
            .fill(Color.secondary.opacity(0.18))
            .frame(width: width, height: height)
            .opacity(isPulsing && !reduceMotion ? 0.55 : 1)
            .accessibilityHidden(true)
    }

    var body: some View {
        Group {
            Section {
                ForEach(0 ..< 3, id: \.self) { _ in
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            bar(90, height: 14)
                            if showsOperationRange {
                                bar(130)
                            }
                        }
                        Spacer(minLength: 12)
                        bar(48, height: 14)
                    }
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                }
            } header: {
                bar(90, height: 16)
            } footer: {
                if !loadingMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(loadingMessages.enumerated()), id: \.offset) { _, message in
                            Text(message)
                        }
                    }
                }
            }

            Section {
                ForEach(0 ..< 4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            bar(32, height: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                bar(index.isMultiple(of: 2) ? 150 : 120, height: 14)
                                HStack {
                                    bar(56)
                                    Spacer(minLength: 12)
                                    bar(64)
                                }
                            }
                        }
                        bar(height: 4)
                            .padding(.vertical, 4)
                        HStack {
                            bar(120)
                            Spacer(minLength: 12)
                            bar(64)
                        }
                        HStack {
                            bar(54)
                            Spacer(minLength: 12)
                            bar(130)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                }
            } header: {
                bar(110, height: 16)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear { isPulsing = true }
    }
}

/// 技能首页骨架：目录导航和训练队列，保持真实列表的图标、文本和进度条布局。
struct CharacterSkillsSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private func bar(_ width: CGFloat? = nil, height: CGFloat = 10, cornerRadius: CGFloat = 4) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: width, height: height)
    }

    var body: some View {
        Group {
            Section(NSLocalizedString("Main_Skills_Categories", comment: "")) {
                ForEach(0 ..< 3, id: \.self) { index in
                    HStack(spacing: 8) {
                        bar(36, height: 36, cornerRadius: 6)
                        bar(index == 2 ? 100 : 130, height: 16)
                        Spacer(minLength: 12)
                        bar(8, height: 12)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }

            Section {
                ForEach(0 ..< 4, id: \.self) { index in
                    HStack(spacing: 8) {
                        bar(36, height: 36, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                bar(index.isMultiple(of: 2) ? 120 : 95, height: 14)
                                Spacer(minLength: 8)
                                HStack(spacing: 3) {
                                    ForEach(0 ..< 5, id: \.self) { _ in
                                        bar(6, height: 10, cornerRadius: 1)
                                    }
                                }
                            }
                            HStack {
                                bar(90, height: 9)
                                Spacer(minLength: 8)
                                bar(48, height: 9)
                            }
                            bar(height: 4, cornerRadius: 2)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            } header: {
                bar(150, height: 14)
            }
        }
        .opacity(isPulsing && !reduceMotion ? 0.55 : 1)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear { isPulsing = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
