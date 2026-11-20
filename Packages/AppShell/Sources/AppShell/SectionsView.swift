import BrowseFeature
import CollectionStore
import DeckOptionsFeature
import DecksFeature
import NoteEditorFeature
import PackagesFeature
import ReminderFeature
import SettingsFeature
import StatisticsFeature
import StudyFeature
import SwiftUI
import SyncFeature

/// The app's sections. iPhone shows them as tabs; iPad shows them in a
/// sidebar with the chosen section beside it.
///
/// Each section's screen comes from its feature package, which also supplies
/// its title and symbol; the shell only arranges them.
struct SectionsView: View {
    let store: CollectionStore
    let sync: SyncModel
    let backups: BackupModel
    @Bindable var model: AppModel
    @State private var selection: AppSection = .decks

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppSection.decks) {
                DeckListScreen(store: store, profileID: model.activeProfile.id, presentation: $model.deckPresentation) {
                    DeckSyncButton(model: sync)
                }
            } label: {
                Label { DecksSection.title } icon: { Image(systemName: DecksSection.systemImage) }
            }
            Tab(value: AppSection.browse) {
                BrowseScreen(store: store)
            } label: {
                Label { BrowseSection.title } icon: { Image(systemName: BrowseSection.systemImage) }
            }
            Tab(value: AppSection.statistics) {
                StatisticsScreen(store: store)
            } label: {
                Label { Text("Stats", bundle: .module) } icon: { Image(systemName: StatisticsSection.systemImage) }
            }
            Tab(value: AppSection.more) {
                SettingsScreen(store: store, sync: sync, backups: backups, profileID: model.activeProfile.id) {
                    NavigationLink {
                        ProfilesScreen(model: model)
                    } label: {
                        LabeledContent {
                            Text(verbatim: model.activeProfile.name)
                        } label: {
                            Label {
                                Text("Profiles", bundle: .module)
                            } icon: {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                    }
                    .accessibilityIdentifier("profiles-settings")
                }
            } label: {
                Label { SettingsSection.title } icon: { Image(systemName: SettingsSection.systemImage) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .sidebarOnWideScreens()
        .syncProgressAccessory(sync)
        .addNoteAction(store: store)
        .reviewerDestination { route, study in
            ReviewerDestinationView(route: route, store: store, study: study)
        }
        .onChange(of: model.decksRequested, initial: true) { _, request in
            if request != nil { selection = .decks }
        }
    }
}

private extension View {
    /// On iPad, open with the sidebar showing rather than the tab bar. (The
    /// packages also build for macOS so their tests run on the Mac, where
    /// this does not apply.)
    @ViewBuilder
    func sidebarOnWideScreens() -> some View {
        #if os(iOS)
        defaultAdaptableTabBarPlacement(.sidebar)
        #else
        self
        #endif
    }
}

enum AppSection: Hashable {
    case decks
    case browse
    case statistics
    case more
}
