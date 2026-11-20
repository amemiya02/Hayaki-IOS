import AnkiCore
import HayakiAppearance
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AboutScreen: View {
    static let repository = URL(string: "https://github.com/amemiya02/Hayaki-iOS")!

    private static let buildInfo: BuildInfo? = {
        guard let url = Bundle.main.url(forResource: "HayakiBuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(BuildInfo.self, from: data)
    }()
    @State private var didCopy = false

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
                if let info = Self.buildInfo {
                    LabeledContent {
                        Text(info.date, format: .dateTime.year().month().day())
                    } label: {
                        Text("Build Date", bundle: .module)
                    }
                    LabeledContent {
                        Text(verbatim: info.fsrsVersion)
                    } label: {
                        Text(verbatim: "FSRS")
                    }
                }
                Button {
                    copyDiagnostics()
                } label: {
                    Label {
                        Text("Copy Debug Information", bundle: .module)
                    } icon: {
                        Image(systemName: "document.on.document")
                    }
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
                Link(destination: Self.repository) {
                    Text(verbatim: "github.com/amemiya02/Hayaki-iOS")
                }
                Link(destination: Self.repository.appending(path: "blob/main/LICENSE")) {
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
            } header: {
                Text("Credits", bundle: .module)
            }
            Section {
                Text("Hayaki sends no usage analytics or automatic crash reports.", bundle: .module)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy", bundle: .module)
            }
        }
        .hayakiScrollBackground()
        .navigationTitle(Text("About", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(Text("Debug Information Copied", bundle: .module), isPresented: $didCopy) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        }
    }

    private func copyDiagnostics() {
        let app = "\(bundleValue("CFBundleShortVersionString")) (\(bundleValue("CFBundleVersion")))"
        var details = ["Hayaki \(app)", "Anki Core \(CoreClient.embeddedVersion)"]
        if let info = Self.buildInfo {
            details.append("FSRS \(info.fsrsVersion)")
            details.append("Build \(info.date.formatted(.iso8601))")
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let platform = ProcessInfo.processInfo.isiOSAppOnMac ? "macOS (iOS app)" : UIDevice.current.systemName
        #else
        let platform = "macOS"
        #endif
        details.append("\(platform) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        let text = details.joined(separator: "\n")
        #if os(iOS)
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true])
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        didCopy = true
    }

    private struct BuildInfo: Decodable {
        let date: Date
        let fsrsVersion: String

        enum CodingKeys: String, CodingKey {
            case date = "BuildDate"
            case fsrsVersion = "FSRSVersion"
        }
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}

private struct ChangelogScreen: View {
    var body: some View {
        List {
            Section {
                Text("Hayaki now shares its app icon, ten themes and public version across Android, iPhone and iPad.", bundle: .module)
            } header: {
                Text(verbatim: "0.2.0")
                    .monospacedDigit()
            }

            Section {
                Text("Initial iPhone and iPad development release.", bundle: .module)
                Text("Study and edit collections offline. Import and export deck and collection packages, review statistics, and change deck options.", bundle: .module)
                Text("Sync with AnkiWeb or a self-hosted Anki sync server.", bundle: .module)
                Text("Added an in-app transfer guide, help links and build information.", bundle: .module)
            } header: {
                Text(verbatim: "0.1.0")
                    .monospacedDigit()
            }
        }
        .navigationTitle(Text("Changelog", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
