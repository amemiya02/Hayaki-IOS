import SwiftUI

enum CardTemplatePreference {
    static let collectionAccess = "hayakiTemplateCollectionAccess"
    static let microphone = "hayakiTemplateMicrophone"
    static let externalApps = "hayakiTemplateExternalApps"
}

public struct CardTemplateSettingsRow: View {
    public init() {}

    public var body: some View {
        NavigationLink {
            CardTemplateSettings()
        } label: {
            Label {
                Text("Card Template Permissions", bundle: .module)
            } icon: {
                Image(systemName: "lock.shield")
            }
        }
    }
}

private struct CardTemplateSettings: View {
    @AppStorage(CardTemplatePreference.collectionAccess) private var collectionAccess = false
    @AppStorage(CardTemplatePreference.microphone) private var microphone = false
    @AppStorage(CardTemplatePreference.externalApps) private var externalApps = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $collectionAccess) {
                    Text("Allow Collection Access", bundle: .module)
                }
            } footer: {
                Text("Card scripts can search your collection and add tags to other notes.", bundle: .module)
            }
            Section {
                Toggle(isOn: $microphone) {
                    Text("Allow Speech Recognition", bundle: .module)
                }
            } footer: {
                Text("Card scripts can request the microphone for speech recognition.", bundle: .module)
            }
            Section {
                Toggle(isOn: $externalApps) {
                    Text("Allow Opening Other Apps", bundle: .module)
                }
            } footer: {
                Text("Tapping a card link can open the app registered for that link.", bundle: .module)
            }
        }
        .navigationTitle(Text("Card Template Permissions", bundle: .module))
    }
}
