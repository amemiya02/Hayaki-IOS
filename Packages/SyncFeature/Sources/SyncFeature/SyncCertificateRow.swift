import SwiftUI

struct SyncCertificateRow: View {
    let model: SyncModel
    @State private var editing = false

    var body: some View {
        Button {
            editing = true
        } label: {
            LabeledContent {
                if model.customCertificate.isEmpty {
                    Text("Optional", bundle: .module)
                } else {
                    Text("Configured", bundle: .module)
                }
            } label: {
                Text("Custom TLS Certificate", bundle: .module)
            }
        }
        .disabled(model.isBusy)
        .sheet(isPresented: $editing) {
            SyncCertificateEditor(model: model)
        }
    }
}

private struct SyncCertificateEditor: View {
    let model: SyncModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var failure: SyncFailure?

    init(model: SyncModel) {
        self.model = model
        _draft = State(initialValue: model.customCertificate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .frame(minHeight: 180)
                        .accessibilityLabel(Text("PEM Certificate", bundle: .module))
                } footer: {
                    Text("Paste one PEM certificate for your HTTPS sync server. Clear the field to use the system’s default certificates.", bundle: .module)
                }
                if let failure {
                    Text(verbatim: failure.message)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(Text("Custom TLS Certificate", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            failure = await model.updateCustomCertificate(draft)
                            if failure == nil { dismiss() }
                        }
                    } label: {
                        Text("Save", bundle: .module)
                    }
                    .disabled(model.isBusy)
                }
            }
        }
    }
}
