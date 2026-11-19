import CollectionStore
import PackagesFeature
import SwiftUI
import SyncFeature

struct TransferGuideScreen: View {
    let store: CollectionStore
    let sync: SyncModel

    var body: some View {
        List {
            Section {
                Text("A deck package (.apkg) merges into the receiving collection.", bundle: .module)
                Text("A collection package (.colpkg) replaces the receiving collection.", bundle: .module)
            } header: {
                Text("Choose a Package", bundle: .module)
            }

            Section {
                Text("In Hayaki on Android or in AnkiDroid, choose Export from the Decks menu for the whole collection. For one deck, touch and hold the deck, then choose Export.", bundle: .module)
                Text("In desktop Anki, choose File > Export and select a deck or collection package.", bundle: .module)
                Text("Save or share the package to Files on your iPhone or iPad, then choose it below. Hayaki asks you to confirm and makes a backup before replacing your collection.", bundle: .module)
                ImportPackageButton()
                    .accessibilityIdentifier("TransferGuideImport")
            } header: {
                Text("Bring a Package into Hayaki", bundle: .module)
            }

            Section {
                Text("Export a deck or collection package below. Include media to bring images and audio. For a deck package, also include scheduling information if you want to move review progress.", bundle: .module)
                Text("Tap Share to send the package to the other device. In Hayaki on Android or in AnkiDroid, open the file from the Decks menu with Import. In desktop Anki, choose File > Import.", bundle: .module)
                ExportPackageButton(store: store)
                    .accessibilityIdentifier("TransferGuideExport")
            } header: {
                Text("Send a Package from Hayaki", bundle: .module)
            }

            Section {
                Text("In Sync Destination, choose AnkiWeb and sign in with your AnkiWeb email address and password.", bundle: .module)
                Text("For your own server, choose Self-Hosted. Enter its address and sign in with the user name and password for that server.", bundle: .module)
                Text("Use the same sync destination on your other devices. To switch destinations, sign out first.", bundle: .module)
                SyncSettingsRow(model: sync)
            } header: {
                Text("Sync Between Devices", bundle: .module)
            }
        }
        .navigationTitle(Text("Transfer Guide", bundle: .module))
    }
}
