import AppShell
import SwiftUI

@main
struct HayakiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(HayakiAppDelegate.self) private var appDelegate
    init() {
        RootView.prepareForLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { _, phase in
            RootView.handleAppPhase(phase)
        }
    }
}
