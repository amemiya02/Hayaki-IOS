import CollectionStore
import ExtensionBridge
import HayakiAppearance
import NoteEditorFeature
import PackagesFeature
import ReminderFeature
import SwiftUI
import SyncFeature
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// The whole app: a short opening state while the collection opens, then the
/// sections.
public struct RootView: View {
    private let model: AppModel
    @State private var choosingRecoveryPackage = false
    @State private var recoveryPackage: URL?
    @State private var recoveryPickerError: String?

    // All app windows use the same active profile and set of operations.
    private static let launchModel: AppModel = {
        #if DEBUG
        if let testModel = UITestLaunch.model { return testModel }
        #endif
        return AppModel(extensionBridge: .appGroup)
    }()

    public init() {
        model = Self.launchModel
    }

    /// Work that must be done before the app finishes launching. The app
    /// calls it from its initializer.
    public static func prepareForLaunch() {
        // Opening a reminder that launched the app is only noticed if the
        // notification delegate is in place by then.
        ReminderOpener.shared.install()
    }

    /// The app passes its aggregate phase so that one window never starts
    /// background sync while another window is still active.
    public static func handleAppPhase(_ phase: ScenePhase) {
        let model = launchModel
        guard let sync = model.sync, let backups = model.backups else { return }
        switch phase {
        case .active:
            Task { await foregroundSync(model, sync: sync) }
        case .background:
            guard model.collectionIsIdle else { return }
            #if os(iOS)
            let time = SyncBackgroundTime { sync.cancel() }
            guard time.isValid else { return }
            #endif
            Task {
                #if os(iOS)
                defer { time.end() }
                #endif
                #if os(iOS)
                guard time.isValid else { return }
                #endif
                guard model.sync === sync, model.collectionIsIdle else { return }
                await sync.automaticSync(.background)
                #if os(iOS)
                guard time.isValid else { return }
                #endif
                if model.sync === sync, model.collectionIsIdle {
                    await backups.createAutomaticBackup()
                }
            }
        default:
            break
        }
    }

    fileprivate static func foregroundSync(_ model: AppModel, sync: SyncModel) async {
        guard model.sync === sync, model.collectionIsIdle else { return }
        if await !sync.automaticSync(.foreground) {
            await sync.refreshBadge()
        }
    }

    public var body: some View {
        Group {
            switch model.state {
            case .opening:
                ProgressView {
                    Text("Opening Your Collection…", bundle: .module)
                }
            case .ready(let store):
                if let importer = model.packageImport, let textImport = model.textImport,
                   let sync = model.sync, let backups = model.backups {
                    ReadyView(store: store, model: model, packageImport: importer, textImport: textImport, sync: sync, backups: backups)
                        .id(model.activeProfile.id)
                        .disabled(model.isSwitchingProfile)
                        .overlay {
                            if model.isSwitchingProfile {
                                ProgressView {
                                    Text("Opening Your Collection…", bundle: .module)
                                }
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label {
                        Text("Could Not Open Your Collection", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(message)
                } actions: {
                    if model.canRecover {
                        Button {
                            choosingRecoveryPackage = true
                        } label: {
                            Text("Choose Recovery Package", bundle: .module)
                        }
                    }
                }
            }
        }
        .hayakiAppearance()
        .task {
            await model.open()
            await model.routeWaitingDeckLink()
        }
        .onChange(of: ReminderOpener.shared.deckListRequested, initial: true) { _, requested in
            guard requested else { return }
            ReminderOpener.shared.deckListRequested = false
            askToOpen(.decks(profileID: nil))
        }
        .onChange(of: ReminderOpener.shared.deckRequested, initial: true) { _, requested in
            guard let requested else { return }
            ReminderOpener.shared.deckRequested = nil
            if let deckID = requested.deckID {
                askToOpen(.deck(profileID: requested.profileID, deckID: deckID, action: .study))
            } else {
                askToOpen(.decks(profileID: requested.profileID))
            }
        }
        .onChange(of: model.canHandleExtensionWork) { _, ready in
            if ready { Task { await model.routeWaitingDeckLink() } }
        }
        .fileImporter(isPresented: $choosingRecoveryPackage, allowedContentTypes: [.ankiCollectionPackage]) { result in
            switch result {
            case .success(let url): recoveryPackage = url
            case .failure(let error): recoveryPickerError = error.localizedDescription
            }
        }
        .alert(
            Text("Restore Collection?", bundle: .module),
            isPresented: Binding(get: { recoveryPackage != nil }, set: { if !$0 { recoveryPackage = nil } }),
            presenting: recoveryPackage
        ) { package in
            Button(role: .destructive) {
                Task { await model.recoverCollection(from: package) }
            } label: {
                Text("Restore", bundle: .module)
            }
            Button(role: .cancel) { recoveryPackage = nil } label: {
                Text("Cancel", bundle: .module)
            }
        } message: { package in
            Text("Restore “\(package.lastPathComponent)” to this device? The damaged database is copied to Backups first.", bundle: .module)
        }
        .alert(
            Text("Could Not Open Package", bundle: .module),
            isPresented: Binding(get: { recoveryPickerError != nil }, set: { if !$0 { recoveryPickerError = nil } })
        ) {
            Button { recoveryPickerError = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: recoveryPickerError ?? "")
        }
        // A collection package or deck package opened from Files, AirDrop or
        // another app's share sheet.
        .onOpenURL { url in
            if let link = DeckLink(url: url) {
                askToOpen(link)
            } else if url.isFileURL {
                Task { await model.openPackage(url) }
            }
        }
        .alert(
            Text("Could Not Open Deck", bundle: .module),
            isPresented: Binding(get: { model.deckLinkError != nil }, set: { if !$0 { model.deckLinkError = nil } })
        ) {
            Button { model.deckLinkError = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: model.deckLinkError ?? "")
        }
    }

    private func askToOpen(_ link: DeckLink) {
        model.waitingDeckLink = AppModel.LinkRequest(link: link)
        Task { await model.routeWaitingDeckLink() }
    }
}

private struct ReadyView: View {
    let store: CollectionStore
    let model: AppModel
    let packageImport: PackageImportModel
    let textImport: TextImportModel
    let sync: SyncModel
    let backups: BackupModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.showsWelcome {
                WelcomeScreen(sync: sync, onContinue: model.completeWelcome)
            } else {
                SectionsView(store: store, sync: sync, backups: backups, model: model)
            }
        }
        .keepingDailyReminderCurrent(store: store, profileID: model.activeProfile.id)
        .modifier(ExtensionIntegration(store: store, profile: model.activeProfile, model: model))
        .packageImport(packageImport)
        .textImport(textImport)
        .onChange(of: textImport.summary) { _, summary in
            if let summary, summary.added > 0, model.showsWelcome { model.completeWelcome() }
        }
        .onChange(of: packageImport.step) { _, step in
            if case .finished = step {
                backups.loadBackups()
                if model.showsWelcome { model.completeWelcome() }
            }
        }
        .task(id: sync.network != nil) {
            guard scenePhase == .active, sync.network != nil else { return }
            if model.collectionIsIdle { await backups.createAutomaticBackup() }
            guard !Task.isCancelled else { return }
            await RootView.foregroundSync(model, sync: sync)
        }
        .task(id: sync.policy.showsStatusBadge) {
            guard sync.policy.showsStatusBadge else { return }
            for await change in store.changes() where change.contains(.mtime) {
                if scenePhase == .active, model.collectionIsIdle { await sync.refreshBadge() }
            }
        }
        .onChange(of: sync.account?.hostKey) { _, _ in refreshSyncBadge() }
        .onChange(of: sync.account?.server) { _, _ in refreshSyncBadge() }
        .onChange(of: sync.policy.showsStatusBadge) { _, _ in refreshSyncBadge() }
        .onChange(of: sync.network) { old, _ in
            if old != nil { refreshSyncBadge() }
        }
    }

    private func refreshSyncBadge() {
        guard scenePhase == .active, model.collectionIsIdle else { return }
        Task { await sync.refreshBadge() }
    }
}


#if os(iOS)
@MainActor
private final class SyncBackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    var isValid: Bool { identifier != .invalid }

    init(onExpiration: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Hayaki Sync") { [weak self] in
            onExpiration()
            self?.end()
        }
    }

    func end() {
        guard isValid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
