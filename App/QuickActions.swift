import AppShell
import UIKit

/// Receives the Home Screen quick actions declared under
/// `UIApplicationShortcutItems` in Info.plist. A quick action that launches
/// the app arrives with the scene's connection options; one chosen while the
/// app is running arrives at the scene delegate.
final class HayakiAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            AddNoteOpener.shared.open(quickActionType: item.type)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = HayakiSceneDelegate.self
        return configuration
    }
}

final class HayakiSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AddNoteOpener.shared.open(quickActionType: shortcutItem.type))
    }
}
