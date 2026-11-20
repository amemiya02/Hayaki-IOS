import CollectionStore
import HayakiAppearance
import NoteEditorFeature
import PackagesFeature
import ReminderFeature
import StudyFeature
import SwiftUI
import SyncFeature

/// How the More section appears in the tab bar and sidebar.
public enum SettingsSection {
    public static var title: Text { Text("More", bundle: .module) }
    public static let systemImage = "ellipsis.circle"
}

/// The More section: one row per area, each leading to its own screen, grouped the way
/// iOS Settings groups its rows, with Profiles on top.
public struct SettingsScreen<ProfileEntry: View>: View {
    private let store: CollectionStore
    private let backups: BackupModel?
    private let profileID: UUID?
    private let profileEntry: ProfileEntry
    @State private var sync: SyncModel
    @State private var query = ""

    public init(
        store: CollectionStore,
        sync: SyncModel? = nil,
        backups: BackupModel? = nil,
        profileID: UUID? = nil,
        @ViewBuilder profileEntry: () -> ProfileEntry
    ) {
        self.store = store
        self.backups = backups
        self.profileID = profileID
        self.profileEntry = profileEntry()
        _sync = State(initialValue: sync ?? SyncModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            List {
                if matches(.profiles) {
                    Section { profileEntry.settingsIcon(.profiles) }
                }
                Section {
                    if matches(.general) {
                        settingsLink("General", icon: .general) {
                            GeneralSettingsScreen(store: store)
                        }
                    }
                    if matches(.appearance) {
                        settingsLink("Appearance", icon: .appearance) {
                            AppearanceSettingsScreen(background: DeckBackground(collectionFolder: store.location.folder))
                        }
                    }
                    if matches(.accessibility) {
                        settingsLink("Accessibility", icon: .accessibility) {
                            AccessibilitySettingsScreen(store: store)
                        }
                    }
                    if matches(.reviewer) {
                        settingsLink("Reviewer", icon: .reviewer) {
                            ReviewerSettingsScreen(store: store)
                        }
                    }
                }
                Section {
                    if matches(.sync) { SyncSettingsRow(model: sync).settingsIcon(.sync) }
                    if matches(.backups), let backups {
                        settingsLink("Backups", icon: .backups) {
                            BackupsScreen(model: backups, sync: sync)
                        }
                    }
                    if matches(.storage) {
                        settingsLink("Manage Space", icon: .storage) {
                            CollectionMaintenanceScreen(store: store, sync: sync)
                        }
                    }
                }
                if matches(.reminders) {
                    Section {
                        ReminderSettingsRow(store: store, profileID: profileID).settingsIcon(.dailyReminder)
                        if let profileID {
                            DeckReminderSettingsRow(store: store, profileID: profileID).settingsIcon(.deckReminders)
                        }
                    }
                }
                Section {
                    if matches(.noteTypes) {
                        settingsLink("Note Types", icon: .noteTypes) {
                            NoteTypesScreen(store: store)
                        }
                    }
                    if matches(.advanced) {
                        settingsLink("Advanced", icon: .advanced) {
                            AdvancedSettingsScreen()
                        }
                    }
                    #if DEBUG
                    if matches(.developer) {
                        settingsLink("Developer Options", icon: .developer) {
                            DeveloperSettingsScreen()
                        }
                    }
                    #endif
                }
                HelpAndAboutSection(store: store, sync: sync, shows: matches)
            }
            .hayakiScrollBackground()
            .overlay {
                if !SettingsTopic.allCases.contains(where: matches) {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle(SettingsSection.title)
            .searchable(text: $query, prompt: Text("Search Settings", bundle: .module))
        }
    }

    private func matches(_ topic: SettingsTopic) -> Bool {
        if topic == .backups, backups == nil { return false }
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return topic.matches(query, locale: locale)
    }

    private func settingsLink<Content: View>(
        _ title: LocalizedStringKey, icon: SettingsIcon, @ViewBuilder destination: () -> Content
    ) -> some View {
        NavigationLink(destination: destination) {
            Label {
                Text(title, bundle: .module)
            } icon: { Image(systemName: icon.symbol) }
        }
        .settingsIcon(icon)
    }
}

extension SettingsScreen where ProfileEntry == EmptyView {
    public init(store: CollectionStore, sync: SyncModel? = nil, backups: BackupModel? = nil) {
        self.init(store: store, sync: sync, backups: backups) { EmptyView() }
    }
}
