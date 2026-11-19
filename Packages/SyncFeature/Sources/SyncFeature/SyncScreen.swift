import CollectionStore
import SwiftUI

/// The Settings row that leads to sync. It shows the server when the learner
/// is signed in and "Off" when sync is not set up; it never prompts.
public struct SyncSettingsRow: View {
    @State private var model: SyncModel

    public init(store: CollectionStore) {
        _model = State(initialValue: SyncModel(store: store))
    }

    public init(model: SyncModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationLink {
            SyncScreen(model: model)
        } label: {
            LabeledContent {
                if case .syncing = model.mediaStatus {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Syncing Media…", bundle: .module))
                } else if let account = model.account {
                    if let server = account.server {
                        Text(verbatim: server.host() ?? server.absoluteString)
                    } else {
                        Text("AnkiWeb", bundle: .module)
                    }
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
        .accessibilityIdentifier("sync-settings")
    }
}

/// Choosing a sync destination, signing in, and syncing the collection and media.
public struct SyncScreen: View {
    @Bindable private var model: SyncModel
    @State private var confirmingDestinationChange = false

    public init(model: SyncModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            if let account = model.account, !model.isChangingDestination {
                SignedInSections(model: model, account: account)
                MediaSyncSection(model: model)
            } else {
                SignInSections(model: model)
            }
            if let failure = model.status.failure {
                FailureSection(failure: failure)
            }
            if model.isChangingDestination {
                Section {
                    Button {
                        model.cancelDestinationChange()
                    } label: {
                        Text("Keep Current Sign-In", bundle: .module)
                    }
                    .disabled(model.isBusy)
                }
            } else if model.account != nil {
                Section {
                    Button {
                        confirmingDestinationChange = true
                    } label: {
                        Text("Change Sync Destination…", bundle: .module)
                    }
                    .disabled(model.isBusy)
                }
                SignOutSection(model: model)
            }
        }
        .navigationTitle(Text("Sync", bundle: .module))
        .alert(Text("Change Sync Destination?", bundle: .module), isPresented: $confirmingDestinationChange) {
            Button {
                model.beginDestinationChange()
            } label: {
                Text("Continue", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text("Your current sign-in will stay active until you sign in to the new destination.", bundle: .module)
        }
    }
}

private struct SignInSections: View {
    @Bindable var model: SyncModel

    private var userNameLabel: Text {
        model.destination == .ankiWeb
            ? Text("Email Address", bundle: .module)
            : Text("User Name", bundle: .module)
    }

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { model.destination },
                set: { model.selectDestination($0) }
            )) {
                Text("AnkiWeb", bundle: .module).tag(SyncModel.Destination.ankiWeb)
                Text("Self-Hosted", bundle: .module).tag(SyncModel.Destination.selfHosted)
            } label: {
                Text("Sync Destination", bundle: .module)
            }
            .accessibilityIdentifier("sync-destination")
            if model.destination == .selfHosted {
                FieldRow {
                    Text("Server Address", bundle: .module)
                } field: {
                    TextField(text: $model.serverAddress, prompt: Text(verbatim: "https://sync.example.org/")) {
                        Text("Server Address", bundle: .module)
                    }
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .urlEntry()
                    .accessibilityIdentifier("server-address")
                }
            }
            FieldRow {
                userNameLabel
            } field: {
                TextField(text: $model.userName, prompt: Text("Required", bundle: .module)) {
                    userNameLabel
                }
                .textContentType(.username)
                .autocorrectionDisabled()
                .syncUserNameEntry(isEmail: model.destination == .ankiWeb)
                .accessibilityIdentifier("user-name")
            }
            FieldRow {
                Text("Password", bundle: .module)
            } field: {
                SecureField(text: $model.password, prompt: Text("Required", bundle: .module)) {
                    Text("Password", bundle: .module)
                }
                .textContentType(.password)
                .accessibilityIdentifier("password")
            }
        } footer: {
            Text("Hayaki stores the sign-in key in this device’s Keychain.", bundle: .module)
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

/// A form row with its label visible beside the field, which a field in a
/// form does not show by itself. The label stays readable at large text
/// sizes by stacking above the field.
private struct FieldRow<Label: View, Field: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let field: Field

    // VoiceOver reads the field's own title, so the visible label is hidden from it.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                label
                    .fixedSize()
                    .accessibilityHidden(true)
                field
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                label
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                field
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
                if let server = account.server {
                    Text(verbatim: server.absoluteString)
                } else {
                    Text("AnkiWeb", bundle: .module)
                }
            } label: {
                Text("Sync Destination", bundle: .module)
            }
            LabeledContent {
                Text(verbatim: account.userName)
            } label: {
                if account.server == nil {
                    Text("Email Address", bundle: .module)
                } else {
                    Text("User Name", bundle: .module)
                }
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
                .disabled(model.isBusy)
                if case .synced(let outcome) = model.status {
                    OutcomeRow(outcome: outcome)
                }
            }
        } footer: {
            Text("Syncing sends the changes made on this device to the server and brings in the changes made on your other devices.", bundle: .module)
        }
    }
}

private struct MediaSyncSection: View {
    let model: SyncModel

    var body: some View {
        if model.mediaStatus != .idle {
            Section {
                switch model.mediaStatus {
                case .idle:
                    EmptyView()
                case .syncing(let progress):
                    BusyRow(model: model) {
                        ProgressView {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Syncing Media…", bundle: .module)
                                if let progress {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: progress.checked)
                                        Text(verbatim: progress.added)
                                        Text(verbatim: progress.removed)
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                case .synced:
                    Text("Media sync complete.", bundle: .module)
                case .cancelled:
                    Text("Media sync cancelled.", bundle: .module)
                case .interrupted:
                    Text("Media sync was interrupted.", bundle: .module)
                case .failed(let failure):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Media sync failed.", bundle: .module)
                        if let failure, let detail = failure.reason == .other ? failure.detail : failure.message {
                            Text(verbatim: detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if model.canRetryMediaSync {
                    Button {
                        Task { await model.retryMediaSync() }
                    } label: {
                        Text("Retry Media Sync", bundle: .module)
                    }
                    .accessibilityIdentifier("retry-media-sync")
                }
            } header: {
                Text("Media Sync", bundle: .module)
            }
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
                    Text("Collection sync complete.", bundle: .module)
                case .uploaded:
                    Text("Collection upload complete.", bundle: .module)
                case .downloaded:
                    Text("Collection download complete.", bundle: .module)
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
    func syncUserNameEntry(isEmail: Bool) -> some View {
        #if os(iOS)
        keyboardType(isEmail ? .emailAddress : .default).textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
