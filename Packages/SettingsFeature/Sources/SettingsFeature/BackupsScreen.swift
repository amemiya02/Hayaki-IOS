import PackagesFeature
import SwiftUI
import SyncFeature

struct BackupsScreen: View {
    let model: BackupModel
    let sync: SyncModel

    var body: some View {
        List {
            Section {
                Button {
                    Task { await model.createBackup() }
                } label: {
                    Text("Create Backup", bundle: .module)
                }
                .disabled(model.status == .creating || sync.isBusy)
                switch model.status {
                case .idle:
                    EmptyView()
                case .creating:
                    ProgressView {
                        Text("Creating Backup…", bundle: .module)
                    }
                case .created:
                    Text("Backup created.", bundle: .module)
                case .unchanged:
                    Text("The current collection is already backed up.", bundle: .module)
                case .failed(let error):
                    Label(error, systemImage: "exclamationmark.triangle")
                }
            }
            Section {
                if model.entries.isEmpty {
                    Text("No backups yet.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.entries) { entry in
                    Button {
                        Task { await model.prepareRestore(entry) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            Text(verbatim: entry.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.status == .creating || sync.isBusy)
                }
            } header: {
                Text("Restore a Backup", bundle: .module)
            } footer: {
                Text("Backups are stored in Hayaki’s Backups folder in Files. Export a collection package to include media.", bundle: .module)
            }
        }
        .navigationTitle(Text("Backups", bundle: .module))
        .task { model.loadBackups() }
    }
}
