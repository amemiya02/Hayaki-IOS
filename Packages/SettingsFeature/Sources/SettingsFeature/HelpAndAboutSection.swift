import CollectionStore
import SwiftUI

struct HelpAndAboutSection: View {
    let store: CollectionStore

    var body: some View {
        Section {
            NavigationLink {
                TransferGuideScreen(store: store)
            } label: {
                Label {
                    Text("Transfer Guide", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.left.arrow.right")
                }
            }
            NavigationLink {
                HelpScreen()
            } label: {
                Label {
                    Text("Help", bundle: .module)
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
            }
            NavigationLink {
                AboutScreen()
            } label: {
                Label {
                    Text("About", bundle: .module)
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
        } header: {
            Text("Help & About", bundle: .module)
        }
    }
}

private struct HelpScreen: View {
    var body: some View {
        List {
            Section {
                Link(destination: URL(string: "https://docs.ankiweb.net/")!) {
                    Text("Desktop Anki Manual", bundle: .module)
                }
                Link(destination: URL(string: "https://docs.ankidroid.org/manual.html")!) {
                    Text("AnkiDroid Manual", bundle: .module)
                }
            } header: {
                Text("Manuals", bundle: .module)
            }
            Section {
                Link(destination: URL(string: "https://forums.ankiweb.net/")!) {
                    Text("Anki Forums", bundle: .module)
                }
                Link(destination: AboutScreen.repository.appending(path: "issues")) {
                    Text("Report a Hayaki Issue", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("Help", bundle: .module))
    }
}
