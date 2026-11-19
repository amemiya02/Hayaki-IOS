import PackagesFeature
import SwiftUI
import SyncFeature

struct WelcomeScreen: View {
    let sync: SyncModel
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onContinue) {
                        Text("Start Empty", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Section {
                    ImportPackageButton()
                    SharedDecksLink()
                    NavigationLink {
                        SyncScreen(model: sync)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(action: onContinue) {
                                        Text("Done", bundle: .module)
                                    }
                                    .disabled(sync.isBusy)
                                }
                            }
                    } label: {
                        Label {
                            Text("Set Up Sync", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
            .navigationTitle(Text("Welcome to Hayaki", bundle: .module))
        }
    }
}
