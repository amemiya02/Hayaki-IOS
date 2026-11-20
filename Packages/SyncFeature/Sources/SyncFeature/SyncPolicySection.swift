import SwiftUI

struct SyncPolicySection: View {
    @Bindable var model: SyncModel
    @State private var showsTimeout = false

    var body: some View {
        Section {
            Toggle(isOn: $model.policy.automatic) {
                Text("Automatic Sync", bundle: .module)
            }
            Toggle(isOn: $model.policy.showsStatusBadge) {
                Text("Show Sync Status Badge", bundle: .module)
            }
            Toggle(isOn: $model.policy.allowsMetered) {
                Text("Allow Sync on Metered Connections", bundle: .module)
            }
            Picker(selection: $model.policy.media) {
                Text("Always", bundle: .module).tag(SyncPolicy.Media.always)
                Text("Only on Unmetered Connections", bundle: .module).tag(SyncPolicy.Media.onlyUnmetered)
                Text("Never", bundle: .module).tag(SyncPolicy.Media.never)
            } label: {
                Text("Sync Media", bundle: .module)
            }
            Button {
                showsTimeout = true
            } label: {
                LabeledContent {
                    Text(Duration.seconds(model.policy.timeoutSeconds).formatted(.units(allowed: [.seconds], width: .abbreviated)))
                } label: {
                    Text("Network Timeout", bundle: .module)
                }
            }
        } header: {
            Text("Sync Preferences", bundle: .module)
        }
        .disabled(model.isBusy)
        .sheet(isPresented: $showsTimeout) {
            SyncTimeoutEditor(seconds: model.policy.timeoutSeconds) {
                model.policy.setTimeoutSeconds($0)
            }
        }
    }
}

private struct SyncTimeoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    let save: (Int) -> Void

    init(seconds: Int, save: @escaping (Int) -> Void) {
        _draft = State(initialValue: String(seconds))
        self.save = save
    }

    private var timeout: Int? {
        guard let seconds = Int(draft.trimmed), SyncPolicy.timeoutRange.contains(seconds) else { return nil }
        return seconds
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $draft) { Text("Seconds", bundle: .module) }
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } footer: {
                    Text("Enter a timeout from 30 to 99,999 seconds.", bundle: .module)
                }
            }
            .navigationTitle(Text("Network Timeout", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let timeout {
                            save(timeout)
                            dismiss()
                        }
                    } label: {
                        Text("Save", bundle: .module)
                    }
                    .disabled(timeout == nil)
                }
            }
        }
    }
}
