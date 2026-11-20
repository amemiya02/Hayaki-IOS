import PackagesFeature
import SwiftUI
import SyncFeature

struct BackupsScreen: View {
    let model: BackupModel
    let sync: SyncModel

    var body: some View {
        List {
            NavigationLink {
                BackupRetentionScreen(model: model, sync: sync)
            } label: {
                Text("Backup Retention", bundle: .module)
            }
            Section {
                Button {
                    Task { await model.createBackup() }
                } label: {
                    Text("Create Backup", bundle: .module)
                }
                .disabled(model.isBusy || sync.isBusy)
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
                    .disabled(model.isBusy || sync.isBusy)
                }
            } header: {
                Text("Restore a Backup", bundle: .module)
            } footer: {
                Text("Backups are stored in Hayaki’s Backups folder in Files. Export a collection package to include media.", bundle: .module)
            }
        }
        .navigationTitle(Text("Backups", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { model.loadBackups() }
    }
}


private struct BackupRetentionScreen: View {
    let model: BackupModel
    let sync: SyncModel
    @State private var draft: BackupRetention?
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let limits = Binding($draft) {
                TextField(value: limits.intervalMinutes, format: .number.grouping(.never)) {
                    Text("Minutes Between Automatic Backups", bundle: .module)
                }
                TextField(value: limits.daily, format: .number.grouping(.never)) {
                    Text("Daily Backups to Keep", bundle: .module)
                }
                TextField(value: limits.weekly, format: .number.grouping(.never)) {
                    Text("Weekly Backups to Keep", bundle: .module)
                }
                TextField(value: limits.monthly, format: .number.grouping(.never)) {
                    Text("Monthly Backups to Keep", bundle: .module)
                }
                if !limits.wrappedValue.isValid {
                    Text("Use 5 to 99999 minutes and 0 to 99999 backups.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
                Button {
                    let updated = limits.wrappedValue
                    isSaving = true
                    Task {
                        if await model.saveRetention(updated) { dismiss() }
                        isSaving = false
                    }
                } label: {
                    Text("Save", bundle: .module)
                }
                .disabled(!limits.wrappedValue.isValid)
            } else if case .idle = model.status {
                ProgressView()
            }
            if case .failed(let error) = model.status {
                Label(error, systemImage: "exclamationmark.triangle")
            }
        }
        .disabled(isSaving || sync.isBusy)
        .navigationTitle(Text("Backup Retention", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { draft = await model.loadRetention() }
    }
}
