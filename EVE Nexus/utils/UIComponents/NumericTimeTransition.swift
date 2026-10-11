import SwiftUI

/// 与技能点数一致的数字滚动；仅在显示文本变化时触发动画。
struct NumericTimeTransition: ViewModifier {
    let text: String
    let countsDown: Bool
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(
                isEnabled && !reduceMotion ? .numericText(countsDown: countsDown) : .opacity
            )
            .animation(
                isEnabled
                    ? (reduceMotion ? .easeInOut(duration: 0.15)
                        : .spring(response: 0.35, dampingFraction: 0.78))
                    : nil,
                value: text
            )
    }
}
