import SwiftUI
import UIKit

final class WidgetShortcutAppDelegate: NSObject, UIApplicationDelegate {
    fileprivate static let shortcutType = "secgg.EVE-Nexus.widget-settings"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.updateShortcut(in: application)
        return true
    }

    static func updateShortcut(in application: UIApplication) {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: shortcutType,
                localizedTitle: String(localized: "Widget_Settings_Title", table: "Widgets", bundle: WidgetLocalization.bundle),
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "square.grid.2x2"),
                userInfo: nil
            ),
        ]
    }

    func application(
        _: UIApplication,
        configurationForConnecting session: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowApplication {
            configuration.delegateClass = WidgetShortcutSceneDelegate.self
        }
        return configuration
    }
}

final class WidgetShortcutSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    @Published var shouldOpenSettings = false

    func scene(_: UIScene, willConnectTo _: UISceneSession, options: UIScene.ConnectionOptions) {
        if let shortcut = options.shortcutItem {
            handle(shortcut)
        }
    }

    func windowScene(
        _: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handle(shortcutItem))
    }

    @discardableResult
    private func handle(_ shortcut: UIApplicationShortcutItem) -> Bool {
        guard shortcut.type == WidgetShortcutAppDelegate.shortcutType else { return false }
        shouldOpenSettings = true
        return true
    }
}

struct OpenWidgetSettingsShortcut: ViewModifier {
    @EnvironmentObject private var sceneDelegate: WidgetShortcutSceneDelegate
    let open: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: sceneDelegate.shouldOpenSettings, initial: true) { _, requested in
            guard requested else { return }
            sceneDelegate.shouldOpenSettings = false
            open()
        }
    }
}
