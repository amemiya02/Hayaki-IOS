import CollectionStore
import PackagesFeature
import ReminderFeature
import SwiftUI
import SyncFeature

/// The whole app: a short opening state while the collection opens, then the
/// sections.
public struct RootView: View {
    @State private var model: AppModel

    public init() {
        #if DEBUG
        if let emptyCollection = UITestLaunch.emptyCollectionModel {
            _model = State(initialValue: emptyCollection)
            return
        }
        #endif
        _model = State(initialValue: AppModel())
    }

    /// Work that must be done before the app finishes launching. The app
    /// calls it from its initializer.
    public static func prepareForLaunch() {
        // Opening a reminder that launched the app is only noticed if the
        // notification delegate is in place by then.
        ReminderOpener.shared.install()
    }

    public var body: some View {
        Group {
            switch model.state {
            case .opening:
                ProgressView {
                    Text("Opening Your Collection…", bundle: .module)
                }
            case .ready(let store):
                if let packageImport = model.packageImport {
                    ReadyView(store: store, model: model, packageImport: packageImport)
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
                }
            }
        }
        .task { await model.open() }
        // A collection package or deck package opened from Files, AirDrop or
        // another app's share sheet.
        .onOpenURL { url in
            Task { await model.openPackage(url) }
        }
    }
}

private struct ReadyView: View {
    let store: CollectionStore
    let model: AppModel
    let packageImport: PackageImportModel
    @State private var sync: SyncModel
    @State private var backups: BackupModel
    @Environment(\.scenePhase) private var scenePhase

    init(store: CollectionStore, model: AppModel, packageImport: PackageImportModel) {
        self.store = store
        self.model = model
        self.packageImport = packageImport
        _sync = State(initialValue: SyncModel(store: store))
        _backups = State(initialValue: BackupModel(store: store, folder: packageImport.backupFolder, importer: packageImport))
    }

    var body: some View {
        Group {
            if model.showsWelcome {
                WelcomeScreen(sync: sync, onContinue: model.completeWelcome)
            } else {
                SectionsView(store: store, sync: sync, backups: backups)
            }
        }
        .packageImport(packageImport)
        .onChange(of: packageImport.step) { _, step in
            if case .finished = step {
                backups.loadBackups()
                if model.showsWelcome { model.completeWelcome() }
            }
        }
        .task {
            guard !sync.isBusy else { return }
            await backups.createAutomaticBackup()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, !sync.isBusy else { return }
            Task { await backups.createAutomaticBackup() }
        }
    }
}
