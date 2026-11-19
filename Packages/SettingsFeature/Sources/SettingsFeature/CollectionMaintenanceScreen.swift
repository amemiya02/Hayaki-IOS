import CollectionStore
import PackagesFeature
import SwiftUI
import SyncFeature

struct CollectionMaintenanceScreen: View {
    @State private var model: CollectionMaintenanceModel
    @State private var confirmDatabaseCheck = false
    @State private var confirmTrash = false
    @State private var confirmEmptyTrash = false
    let sync: SyncModel

    init(store: CollectionStore, sync: SyncModel) {
        _model = State(initialValue: CollectionMaintenanceModel(store: store))
        self.sync = sync
    }

    var body: some View {
        List {
            if let usage = model.storageUsage {
                Section {
                    LabeledContent {
                        Text(verbatim: formattedBytes(usage.database))
                    } label: {
                        Text("Collection Database", bundle: .module)
                    }
                    LabeledContent {
                        Text(verbatim: formattedBytes(usage.media))
                    } label: {
                        Text("Media Files", bundle: .module)
                    }
                }
            }
            Section {
                Button {
                    confirmDatabaseCheck = true
                } label: {
                    Text("Check Collection", bundle: .module)
                }
                if let problems = model.databaseProblems {
                    if problems.isEmpty {
                        Text("No problems found.", bundle: .module)
                    } else {
                        ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                            Text(verbatim: problem)
                        }
                    }
                }
                Button {
                    Task { await model.checkMedia() }
                } label: {
                    Text("Check Media", bundle: .module)
                }
            }
            if let media = model.media {
                Section {
                    if media.missing.isEmpty {
                        Text("No missing files.", bundle: .module)
                    } else {
                        ForEach(media.missing, id: \.self) { Text(verbatim: $0) }
                    }
                } header: {
                    Text("Missing Media", bundle: .module)
                }
                Section {
                    if media.unused.isEmpty {
                        Text("No unused files.", bundle: .module)
                    } else {
                        ForEach(media.unused, id: \.self) { Text(verbatim: $0) }
                        Button(role: .destructive) {
                            confirmTrash = true
                        } label: {
                            Text("Move Unused Files to Trash", bundle: .module)
                        }
                    }
                } header: {
                    Text("Unused Media", bundle: .module)
                }
                if media.hasTrash {
                    Section {
                        Button {
                            Task { await model.restoreMediaTrash() }
                        } label: {
                            Text("Restore Trashed Media", bundle: .module)
                        }
                        Button(role: .destructive) {
                            confirmEmptyTrash = true
                        } label: {
                            Text("Empty Media Trash", bundle: .module)
                        }
                    }
                }
            }
            if model.isRunning {
                ProgressView()
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
            }
        }
        .disabled(model.isRunning || sync.isBusy)
        .navigationTitle(Text("Manage Space", bundle: .module))
        .task { await model.loadStorageUsage() }
        .alert(Text("Check Collection", bundle: .module), isPresented: $confirmDatabaseCheck) {
            Button {
                Task { await model.checkDatabase() }
            } label: {
                Text("Check", bundle: .module)
            }
            cancelButton
        } message: {
            Text("Hayaki will check the collection database and repair any problems it can.", bundle: .module)
        }
        .alert(Text("Move Unused Files to Trash", bundle: .module), isPresented: $confirmTrash) {
            Button(role: .destructive) {
                Task { await model.trashUnusedMedia() }
            } label: {
                Text("Move to Trash", bundle: .module)
            }
            cancelButton
        } message: {
            Text("You can restore these files from the media trash.", bundle: .module)
        }
        .alert(Text("Empty Media Trash", bundle: .module), isPresented: $confirmEmptyTrash) {
            Button(role: .destructive) {
                Task { await model.emptyMediaTrash() }
            } label: {
                Text("Delete", bundle: .module)
            }
            cancelButton
        } message: {
            Text("Files in the media trash will be permanently deleted.", bundle: .module)
        }
    }

    private var cancelButton: some View {
        Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
    }

    private func formattedBytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
