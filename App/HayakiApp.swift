import AppShell
import SwiftUI

@main
struct HayakiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    init() {
        RootView.prepareForLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands { HayakiCommands() }
        .onChange(of: scenePhase) { _, phase in
            RootView.handleAppPhase(phase)
        }
    }
}
