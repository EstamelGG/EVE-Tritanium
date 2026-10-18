import SwiftUI
import UIKit

/// Route interactive back and sheet-dismiss attempts through the same draft confirmation.
struct FittingExitGuard: UIViewControllerRepresentable {
    let isDirty: Bool
    let onExitAttempt: () -> Void

    func makeUIViewController(context _: Context) -> Controller {
        let controller = Controller()
        controller.isDirty = isDirty
        controller.onExitAttempt = onExitAttempt
        return controller
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.isDirty = isDirty
        controller.onExitAttempt = onExitAttempt
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator _: ()) {
        controller.restoreDelegates()
    }

    final class Controller: UIViewController, UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate {
        var isDirty = false
        var onExitAttempt: (() -> Void)?
        private weak var popGesture: UIGestureRecognizer?
        private weak var previousGestureDelegate: UIGestureRecognizerDelegate?
        private var previousGestureEnabled = false
        private weak var guardedPresentation: UIPresentationController?
        private weak var previousPresentationDelegate: UIAdaptivePresentationControllerDelegate?

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let gesture = navigationController?.interactivePopGestureRecognizer,
               gesture.delegate !== self
            {
                popGesture = gesture
                previousGestureDelegate = gesture.delegate
                previousGestureEnabled = gesture.isEnabled
                gesture.delegate = self
                gesture.isEnabled = (navigationController?.viewControllers.count ?? 0) > 1
            }
            var ancestor: UIViewController? = parent
            while let controller = ancestor {
                if controller.presentingViewController != nil,
                   let presentation = controller.presentationController,
                   presentation.delegate !== self
                {
                    guardedPresentation = presentation
                    previousPresentationDelegate = presentation.delegate
                    presentation.delegate = self
                    break
                }
                ancestor = controller.parent
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            restoreDelegates()
            super.viewWillDisappear(animated)
        }

        func restoreDelegates() {
            if let gesture = popGesture, gesture.delegate === self {
                gesture.delegate = previousGestureDelegate
                gesture.isEnabled = previousGestureEnabled
            }
            if let presentation = guardedPresentation, presentation.delegate === self {
                presentation.delegate = previousPresentationDelegate
            }
            popGesture = nil
            guardedPresentation = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard (navigationController?.viewControllers.count ?? 0) > 1 else { return false }
            if isDirty {
                onExitAttempt?()
                return false
            }
            return previousGestureDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !isDirty && (previousPresentationDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if isDirty {
                onExitAttempt?()
            } else {
                previousPresentationDelegate?.presentationControllerDidAttemptToDismiss?(presentationController)
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            previousPresentationDelegate?.presentationControllerDidDismiss?(presentationController)
        }
    }
}
