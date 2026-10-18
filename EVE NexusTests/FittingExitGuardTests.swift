import SwiftUI
import UIKit
import XCTest
@testable import EVE_Nexus

@MainActor
final class FittingExitGuardTests: XCTestCase {
    func testInteractiveBackCannotDiscardDirtyDraftAndRestoresNavigationDelegate() async throws {
        var exitAttempts = 0
        let host = UIHostingController(rootView: FittingExitGuard(isDirty: true) { exitAttempts += 1 })
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(host, animated: false)
        _ = navigation.view
        let previousDelegate = navigation.interactivePopGestureRecognizer?.delegate
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
        }

        // Wait for representable containment and viewDidAppear, not just controller creation.
        for _ in 0..<40 {
            if navigation.interactivePopGestureRecognizer?.delegate is FittingExitGuard.Controller { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let gesture = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
        let guardController = try XCTUnwrap(gesture.delegate as? FittingExitGuard.Controller)
        XCTAssertFalse(guardController.gestureRecognizerShouldBegin(gesture))
        XCTAssertEqual(exitAttempts, 1)
        XCTAssertEqual(navigation.viewControllers.count, 2)

        guardController.isDirty = false
        guardController.restoreDelegates()
        XCTAssertTrue(gesture.delegate === previousDelegate)
    }

    func testSheetDismissRequiresConfirmationOnlyForDirtyDraft() {
        let controller = FittingExitGuard.Controller()
        let presentation = UIPresentationController(presentedViewController: UIViewController(), presenting: nil)
        var exitAttempts = 0
        controller.onExitAttempt = { exitAttempts += 1 }
        controller.isDirty = true
        XCTAssertFalse(controller.presentationControllerShouldDismiss(presentation))
        controller.presentationControllerDidAttemptToDismiss(presentation)
        XCTAssertEqual(exitAttempts, 1)
        controller.isDirty = false
        XCTAssertTrue(controller.presentationControllerShouldDismiss(presentation))
    }
}
