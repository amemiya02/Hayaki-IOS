import CollectionStore
import ReminderFeature
import SwiftUI
import SyncFeature

/// How the Settings section appears in the tab bar and sidebar.
public enum SettingsSection {
    public static var title: Text { Text("Settings", bundle: .module) }
    public static let systemImage = "gearshape"
}

/// The Settings section: one row per area, each leading to its own screen.
public struct SettingsScreen: View {
    private let store: CollectionStore

    public init(store: CollectionStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                SyncSettingsRow(store: store)
                ReminderSettingsRow(store: store)
                HelpAndAboutSection(store: store)
            }
            .navigationTitle(SettingsSection.title)
        }
    }
}
