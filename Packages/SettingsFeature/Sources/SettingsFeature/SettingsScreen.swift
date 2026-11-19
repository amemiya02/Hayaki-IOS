import CollectionStore
import PackagesFeature
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
    private let backups: BackupModel?
    @State private var sync: SyncModel

    public init(store: CollectionStore, sync: SyncModel? = nil, backups: BackupModel? = nil) {
        self.store = store
        self.backups = backups
        _sync = State(initialValue: sync ?? SyncModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            List {
                SyncSettingsRow(model: sync)
                ReminderSettingsRow(store: store)
                if let backups {
                    NavigationLink {
                        BackupsScreen(model: backups, sync: sync)
                    } label: {
                        Label {
                            Text("Backups", bundle: .module)
                        } icon: {
                            Image(systemName: "externaldrive.badge.clock")
                        }
                    }
                }
                NavigationLink {
                    CollectionMaintenanceScreen(store: store, sync: sync)
                } label: {
                    Label {
                        Text("Manage Space", bundle: .module)
                    } icon: {
                        Image(systemName: "externaldrive")
                    }
                }
                HelpAndAboutSection(store: store, sync: sync)
            }
            .navigationTitle(SettingsSection.title)
        }
    }
}
