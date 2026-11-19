import AnkiCore
import SwiftUI

struct AboutScreen: View {
    static let repository = URL(string: "https://github.com/amemiya02/Hayaki-IOS")!

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(verbatim: bundleValue("CFBundleShortVersionString"))
                } label: {
                    Text("App Version", bundle: .module)
                }
                LabeledContent {
                    Text(verbatim: bundleValue("CFBundleVersion"))
                } label: {
                    Text("Build", bundle: .module)
                }
                LabeledContent {
                    Text(verbatim: CoreClient.embeddedVersion)
                } label: {
                    Text("Anki Core", bundle: .module)
                }
                NavigationLink {
                    ChangelogScreen()
                } label: {
                    Text("Changelog", bundle: .module)
                }
            } header: {
                Text(verbatim: "Hayaki")
            }

            Section {
                Link(destination: Self.repository.appending(path: "tree/hayaki-v1")) {
                    Text(verbatim: "github.com/amemiya02/Hayaki-IOS")
                }
                Link(destination: Self.repository.appending(path: "blob/hayaki-v1/LICENSE")) {
                    Text(verbatim: "AGPL-3.0-or-later")
                }
            } header: {
                Text("Source Code and License", bundle: .module)
            } footer: {
                Text("Hayaki is an independent project. It has no affiliation with or endorsement from the makers of Anki, AnkiWeb or AnkiDroid.", bundle: .module)
            }

            Section {
                Link(destination: URL(string: "https://github.com/ankitects/anki")!) {
                    Text(verbatim: "Anki")
                }
                Link(destination: URL(string: "https://github.com/ankidroid/Anki-Android")!) {
                    Text(verbatim: "AnkiDroid")
                }
                Link(destination: URL(string: "https://github.com/antigluten/amgi")!) {
                    Text(verbatim: "Amgi")
                }
            } header: {
                Text("Credits", bundle: .module)
            }
        }
        .navigationTitle(Text("About", bundle: .module))
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}

private struct ChangelogScreen: View {
    var body: some View {
        List {
            Section {
                Text("Initial iPhone and iPad development release.", bundle: .module)
                Text("Study and edit collections offline. Import and export deck and collection packages, review statistics, and change deck options.", bundle: .module)
                Text("Added an in-app transfer guide, help links and build information.", bundle: .module)
            } header: {
                Text(verbatim: "0.1.0")
                    .monospacedDigit()
            }
        }
        .navigationTitle(Text("Changelog", bundle: .module))
    }
}
