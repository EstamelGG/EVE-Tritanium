import SwiftUI

/// 删除二次确认弹窗（通用，统一 alert 样式）
private struct FittingDeleteConfirmationModifier: ViewModifier {
    let message: String
    let isPresented: Binding<Bool>
    let onConfirm: () -> Void
    let onCancel: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(
            NSLocalizedString("Fitting_Delete_Confirm_Title", comment: "确认删除"),
            isPresented: isPresented
        ) {
            Button(
                NSLocalizedString("Fitting_Delete_Confirm", comment: "删除"),
                role: .destructive,
                action: onConfirm
            )
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                onCancel?()
            }
        } message: {
            Text(message)
        }
    }
}

extension View {
    /// 通用删除二次确认（alert 弹窗）
    func fittingDeleteConfirmation(
        message: String,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        modifier(
            FittingDeleteConfirmationModifier(
                message: message,
                isPresented: isPresented,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        )
    }
}
