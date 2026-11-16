import CollectionStore
import SwiftUI

/// How the Settings section appears in the tab bar and sidebar.
public enum SettingsSection {
    public static var title: Text { Text("Settings", bundle: .module) }
    public static let systemImage = "gearshape"
}

/// The Settings section. A placeholder until sync, backups, reminders and
/// About are built.
public struct SettingsScreen: View {
    private let store: CollectionStore

    public init(store: CollectionStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text("Settings Are Coming", bundle: .module)
                } icon: {
                    Image(systemName: SettingsSection.systemImage)
                }
            } description: {
                Text("Sync, backups, reminders and About will appear here.", bundle: .module)
            }
            .navigationTitle(SettingsSection.title)
        }
    }
}
