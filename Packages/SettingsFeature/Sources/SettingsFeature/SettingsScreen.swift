import CollectionStore
import ReminderFeature
import SwiftUI
import SyncFeature

/// How the More section appears in the tab bar and sidebar.
public enum SettingsSection {
    public static var title: Text { Text("More", bundle: .module) }
    public static let systemImage = "ellipsis.circle"
}

/// The More section: one row per area, each leading to its own screen.
public struct SettingsScreen: View {
    private let store: CollectionStore
    @State private var sync: SyncModel

    public init(store: CollectionStore, sync: SyncModel? = nil) {
        self.store = store
        _sync = State(initialValue: sync ?? SyncModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            List {
                SyncSettingsRow(model: sync)
                ReminderSettingsRow(store: store)
                HelpAndAboutSection(store: store, sync: sync)
            }
            .navigationTitle(SettingsSection.title)
        }
    }
}
