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

/// The More section: one row per area, each leading to its own screen.
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
                if matches(.profiles) { profileEntry }
                if matches(.general) {
                    settingsLink("General", symbol: "gearshape") {
                        GeneralSettingsScreen(store: store)
                    }
                }
                if matches(.appearance) {
                    settingsLink("Appearance", symbol: "circle.lefthalf.filled") {
                        AppearanceSettingsScreen(background: DeckBackground(collectionFolder: store.location.folder))
                    }
                }
                if matches(.reviewer) {
                    settingsLink("Reviewer", symbol: "rectangle.on.rectangle") {
                        ReviewerSettingsScreen(store: store)
                    }
                }
                if matches(.accessibility) {
                    settingsLink("Accessibility", symbol: "accessibility") {
                        AccessibilitySettingsScreen(store: store)
                    }
                }
                if matches(.sync) { SyncSettingsRow(model: sync) }
                if matches(.reminders) {
                    ReminderSettingsRow(store: store, profileID: profileID)
                    if let profileID { DeckReminderSettingsRow(store: store, profileID: profileID) }
                }
                if matches(.backups), let backups {
                    settingsLink("Backups", symbol: "externaldrive.badge.clock") {
                        BackupsScreen(model: backups, sync: sync)
                    }
                }
                if matches(.storage) {
                    settingsLink("Manage Space", symbol: "externaldrive") {
                        CollectionMaintenanceScreen(store: store, sync: sync)
                    }
                }
                if matches(.noteTypes) {
                    settingsLink("Note Types", symbol: "rectangle.on.rectangle") {
                        NoteTypesScreen(store: store)
                    }
                }
                if matches(.advanced) {
                    settingsLink("Advanced", symbol: "gearshape.2") {
                        AdvancedSettingsScreen()
                    }
                }
                #if DEBUG
                if matches(.developer) {
                    settingsLink("Developer Options", symbol: "hammer") {
                        DeveloperSettingsScreen()
                    }
                }
                #endif
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
        _ title: LocalizedStringKey, symbol: String, @ViewBuilder destination: () -> Content
    ) -> some View {
        NavigationLink(destination: destination) {
            Label {
                Text(title, bundle: .module)
            } icon: { Image(systemName: symbol) }
        }
    }
}

extension SettingsScreen where ProfileEntry == EmptyView {
    public init(store: CollectionStore, sync: SyncModel? = nil, backups: BackupModel? = nil) {
        self.init(store: store, sync: sync, backups: backups) { EmptyView() }
    }
}
