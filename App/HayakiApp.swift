import AppShell
import SwiftUI

@main
struct HayakiApp: App {
    init() {
        RootView.prepareForLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
