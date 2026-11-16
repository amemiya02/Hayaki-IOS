import CollectionStore
import SwiftUI

/// The Settings row that leads to sync. It shows the server when the learner
/// is signed in and "Off" when sync is not set up; it never prompts.
public struct SyncSettingsRow: View {
    @State private var model: SyncModel

    public init(store: CollectionStore) {
        _model = State(initialValue: SyncModel(store: store))
    }

    public var body: some View {
        NavigationLink {
            SyncScreen(model: model)
        } label: {
            LabeledContent {
                if let account = model.account {
                    Text(verbatim: account.server.host() ?? account.server.absoluteString)
                } else {
                    Text("Off", bundle: .module)
                }
            } label: {
                Label {
                    Text("Sync", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
    }
}

/// Signing in to the learner's own sync server, syncing, choosing a direction
/// when the two sides cannot be merged, and signing out.
public struct SyncScreen: View {
    @Bindable private var model: SyncModel

    public init(model: SyncModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if let account = model.account {
                SignedInSections(model: model, account: account)
            } else {
                NoAnkiWebSection()
                SignInSections(model: model)
            }
            if let failure = model.status.failure {
                FailureSection(failure: failure)
            }
            if model.account != nil {
                SignOutSection(model: model)
                NoAnkiWebSection()
            }
        }
        .navigationTitle(Text("Sync", bundle: .module))
    }
}

/// Why there is no AnkiWeb sign-in (ADR 0002), stated where the learner looks
/// for one.
private struct NoAnkiWebSection: View {
    var body: some View {
        Section {
            Text("Hayaki does not sign in to AnkiWeb. AnkiWeb's terms allow only apps its operators have approved, and Hayaki is not one of them. Hayaki syncs only with a sync server you run or choose yourself.", bundle: .module)
            Text("To move your collection to or from AnkiWeb, export it from Hayaki as a collection package and sync it from desktop Anki or AnkiDroid.", bundle: .module)
                .foregroundStyle(.secondary)
        } header: {
            Text("AnkiWeb", bundle: .module)
        }
    }
}

private struct SignInSections: View {
    @Bindable var model: SyncModel

    var body: some View {
        Section {
            TextField(text: $model.serverAddress, prompt: Text(verbatim: "https://sync.example.org/")) {
                Text("Server Address", bundle: .module)
            }
            .textContentType(.URL)
            .autocorrectionDisabled()
            .urlEntry()
            TextField(text: $model.userName, prompt: Text("Required", bundle: .module)) {
                Text("User Name", bundle: .module)
            }
            .textContentType(.username)
            .autocorrectionDisabled()
            .noAutocapitalization()
            SecureField(text: $model.password, prompt: Text("Required", bundle: .module)) {
                Text("Password", bundle: .module)
            }
            .textContentType(.password)
        } header: {
            Text("Your Sync Server", bundle: .module)
        } footer: {
            Text("The server's address, and your user name and password on it. Hayaki keeps only the key the server issues in exchange, in this device's Keychain; your password is not stored.", bundle: .module)
        }
        .disabled(model.isBusy)

        Section {
            if model.status == .signingIn {
                BusyRow(model: model) {
                    Text("Signing In…", bundle: .module)
                }
            } else {
                Button {
                    Task { await model.signIn() }
                } label: {
                    Text("Sign In", bundle: .module)
                }
                .disabled(!model.canSignIn)
            }
        }
    }
}

private struct SignedInSections: View {
    let model: SyncModel
    let account: SyncAccount

    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: account.server.absoluteString)
            } label: {
                Text("Server", bundle: .module)
            }
            LabeledContent {
                Text(verbatim: account.userName)
            } label: {
                Text("User Name", bundle: .module)
            }
        } header: {
            Text("Your Sync Server", bundle: .module)
        }

        Section {
            switch model.status {
            case .syncing(let progress):
                BusyRow(model: model) {
                    ProgressDescription(progress: progress)
                }
            case .choosingDirection(let choice):
                DirectionChoice(model: model, choice: choice)
            default:
                Button {
                    Task { await model.sync() }
                } label: {
                    Label {
                        Text("Sync Now", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                if case .synced(let outcome) = model.status {
                    OutcomeRow(outcome: outcome)
                }
            }
        } footer: {
            Text("Syncing sends the changes made on this device to the server and brings in the changes made on your other devices.", bundle: .module)
        }
    }
}

/// Asks which side to keep. Nothing is overwritten until a button is chosen.
private struct DirectionChoice: View {
    let model: SyncModel
    let choice: FullSyncChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose Which Collection to Keep", bundle: .module)
                .font(.headline)
            Group {
                switch choice {
                case .either:
                    Text("The collection on this device and the one on the server have changed in ways that cannot be merged, so one must replace the other. Nothing has been changed yet.", bundle: .module)
                case .uploadOnly:
                    Text("The server has no collection yet. Nothing has been changed yet.", bundle: .module)
                case .downloadOnly:
                    Text("The collection on this device is empty. Nothing has been changed yet.", bundle: .module)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)

        if choice.allowsUpload {
            ChoiceButton(systemImage: "arrow.up.circle") {
                Text("Upload to Server", bundle: .module)
            } explanation: {
                if choice == .uploadOnly {
                    Text("Send the collection on this device to the server, so your other devices can download it.", bundle: .module)
                } else {
                    Text("Replace the collection on the server with the one on this device. Changes that only the server has, from your other devices, are lost.", bundle: .module)
                }
            } action: {
                Task { await model.upload() }
            }
        }
        if choice.allowsDownload {
            ChoiceButton(systemImage: "arrow.down.circle") {
                Text("Download from Server", bundle: .module)
            } explanation: {
                if choice == .downloadOnly {
                    Text("Replace the empty collection on this device with the one on the server.", bundle: .module)
                } else {
                    Text("Replace the collection on this device with the one on the server. Changes that only this device has are lost.", bundle: .module)
                }
            } action: {
                Task { await model.download() }
            }
        }
        Button {
            model.keepBoth()
        } label: {
            Text("Not Now", bundle: .module)
        }
    }
}

private struct ChoiceButton<Title: View, Explanation: View>: View {
    let systemImage: String
    @ViewBuilder let title: Title
    @ViewBuilder let explanation: Explanation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    explanation
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

/// What is under way, with a button to cancel it.
private struct BusyRow<Description: View>: View {
    let model: SyncModel
    @ViewBuilder let description: Description

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            description
            Button(role: .cancel) {
                model.cancel()
            } label: {
                Text("Cancel", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

private struct ProgressDescription: View {
    let progress: SyncProgress

    var body: some View {
        switch progress {
        case .connecting:
            ProgressView {
                Text("Connecting…", bundle: .module)
            }
        case .syncing(let detail):
            ProgressView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Syncing…", bundle: .module)
                    if let detail {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .uploading(let transferred, let total):
            TransferProgress(transferred: transferred, total: total) {
                Text("Uploading…", bundle: .module)
            }
        case .downloading(let transferred, let total):
            TransferProgress(transferred: transferred, total: total) {
                Text("Downloading…", bundle: .module)
            }
        }
    }
}

private struct TransferProgress<Title: View>: View {
    let transferred: Int
    let total: Int
    @ViewBuilder let title: Title

    var body: some View {
        if total > 0 {
            ProgressView(value: Double(min(transferred, total)), total: Double(total)) {
                title
            } currentValueLabel: {
                Text("\(Self.bytes(transferred)) of \(Self.bytes(total))", bundle: .module)
            }
        } else {
            ProgressView { title }
        }
    }

    private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

private struct OutcomeRow: View {
    let outcome: SyncOutcome

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                switch outcome.kind {
                case .merged:
                    Text("This device and the server are in step.", bundle: .module)
                case .uploaded:
                    Text("The server now has the collection from this device.", bundle: .module)
                case .downloaded:
                    Text("This device now has the collection from the server.", bundle: .module)
                }
                if let message = outcome.serverMessage {
                    Text(verbatim: message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct FailureSection: View {
    let failure: SyncFailure

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: failure.message)
                    if let detail = failure.detail {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: failure.reason == .cancelled ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(failure.reason == .cancelled ? Color.secondary : Color.orange)
            }
        }
    }
}

private struct SignOutSection: View {
    let model: SyncModel

    var body: some View {
        Section {
            Button(role: .destructive) {
                model.signOut()
            } label: {
                Text("Sign Out", bundle: .module)
            }
            .disabled(model.isBusy)
        } footer: {
            Text("Signing out removes the server's key from this device. Your collection stays on this device.", bundle: .module)
        }
    }
}

private extension View {
    /// The packages also build for macOS, where tests run; these keyboard
    /// settings exist on iOS only.
    @ViewBuilder
    func urlEntry() -> some View {
        #if os(iOS)
        keyboardType(.URL).textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
