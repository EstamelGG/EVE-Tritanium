import SwiftUI

struct SkillLevelIndicator: View {
    let currentLevel: Int
    let trainingLevel: Int
    let isTraining: Bool
    let queuedLevels: Set<Int> // 队列中的等级集合
    let requiredLevel: Int? // 物品技能要求；未满足部分沿用目标等级的灰色方块

    /// 动画状态
    @State private var isBlinking = false

    init(currentLevel: Int, trainingLevel: Int, isTraining: Bool, queuedLevels: Set<Int> = [], requiredLevel: Int? = nil) {
        self.currentLevel = min(max(currentLevel, 0), 5)
        self.trainingLevel = min(max(trainingLevel, 0), 5)
        self.isTraining = isTraining
        self.queuedLevels = queuedLevels
        self.requiredLevel = requiredLevel.map { min(max($0, 0), 5) }
    }

    // 常量定义
    private let frameWidth: CGFloat = 55.5 // 37 * 1.5
    private let frameHeight: CGFloat = 9 // 6 * 1.5
    private let blockWidth: CGFloat = 9 // 6 * 1.5
    private let blockHeight: CGFloat = 6 // 4 * 1.5
    private let blockSpacing: CGFloat = 1.5 // 1 * 1.5

    // 颜色定义
    private let darkGray = Color.primary.opacity(0.8)
    private let lightGray = Color.secondary.opacity(0.6)
    private let cyanColor = Color.cyan.opacity(0.8) // 队列中的等级使用青色
    private let borderColor = Color.primary.opacity(0.8)

    var body: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .center)) {
            // 外框 - 使用方形边框
            Rectangle()
                .stroke(borderColor, lineWidth: 0.5)
                .frame(width: frameWidth, height: frameHeight)

            // 使用固定偏移来放置方块组
            HStack(spacing: blockSpacing) {
                ForEach(0 ..< 5) { index in
                    // 方块 - 使用方形
                    Rectangle()
                        .frame(width: blockWidth, height: blockHeight)
                        .foregroundColor(blockColor(for: index))
                        .opacity(blockOpacity(for: index))
                }
            }
            .offset(x: blockSpacing + 0.5) // 0.5是边框宽度，加上1.5像素间距
        }
        .onChange(of: isTraining, initial: true) { _, _ in
            if isTraining {
                withAnimation(
                    .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                ) {
                    isBlinking = true
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { isBlinking = false }
            }
        }
    }

    /// 确定方块颜色
    private func blockColor(for index: Int) -> Color {
        let level = index + 1 // index是0-4，对应等级1-5

        // 1. 已完成的等级优先显示黑色（含合并后队列中已完成的）
        if index < currentLevel {
            return darkGray
        }

        // 2. 队列中等待训练的等级使用青色（排除已完成的，因上面已处理）
        if queuedLevels.contains(level) {
            return cyanColor
        }

        // 3. 尚未达到的训练目标 / 物品所需等级
        if index < max(trainingLevel, requiredLevel ?? 0) {
            return lightGray
        }
        return .clear
    }

    /// 确定方块透明度
    private func blockOpacity(for index: Int) -> Double {
        if isTraining && trainingLevel > currentLevel && index == trainingLevel - 1 {
            return isBlinking ? 0.3 : 1.0
        }
        return 1.0
    }
}

#Preview {
    VStack(spacing: 20) {
        // 预览不同状态
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 2, isTraining: false)
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 3, isTraining: false)
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 3, isTraining: true)
        SkillLevelIndicator(currentLevel: 3, trainingLevel: 4, isTraining: true)
        SkillLevelIndicator(currentLevel: 4, trainingLevel: 5, isTraining: true)
        // 预览队列中的等级
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 2, isTraining: false, queuedLevels: [3, 4])
        // 物品所需技能复用同一外框与五格布局
        SkillLevelIndicator(currentLevel: -1, trainingLevel: 0, isTraining: false, requiredLevel: 3)
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 0, isTraining: false, requiredLevel: 4)
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 3, isTraining: true, requiredLevel: 4)
        SkillLevelIndicator(currentLevel: 5, trainingLevel: 0, isTraining: false, requiredLevel: 3)
    }
    .padding()
}
