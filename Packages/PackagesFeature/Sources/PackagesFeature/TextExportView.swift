import CollectionStore
import SwiftUI

public struct TextExportButton: View {
    private let store: CollectionStore
    @Environment(\.showPackageSheet) private var showPackageSheet
    @State private var presented = false

    public init(store: CollectionStore) {
        self.store = store
    }

    public var body: some View {
        Button {
            if let showPackageSheet {
                showPackageSheet(.exportText)
            } else {
                presented = true
            }
        } label: {
            Label {
                Text("Export Text File", bundle: .module)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
        }
        .sheet(isPresented: $presented) {
            TextExportScreen(store: store)
        }
    }
}

public struct TextExportScreen: View {
    let store: CollectionStore
    let selection: ExportSelection?
    @Environment(\.dismiss) private var dismiss

    public init(store: CollectionStore, selection: ExportSelection? = nil) {
        self.store = store
        self.selection = selection
    }

    public var body: some View {
        NavigationStack {
            if let folder = try? PackageExportModel.standardExportFolder() {
                TextExportForm(store: store, folder: folder, selection: selection)
            } else {
                ContentUnavailableView {
                    Text("Could Not Export", bundle: .module)
                } description: {
                    Text("Hayaki cannot reach its Documents folder.", bundle: .module)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("Close", bundle: .module) }
                    }
                }
            }
        }
    }
}

private struct TextExportForm: View {
    @State private var model: TextExportModel
    @Environment(\.dismiss) private var dismiss

    init(store: CollectionStore, folder: URL, selection: ExportSelection?) {
        _model = State(initialValue: TextExportModel(store: store, folder: folder, selection: selection))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if let file = model.exportedFile, let count = model.count {
                LabeledContent {
                    Text(count.formatted())
                } label: {
                    if model.format == .notes {
                        Text("Notes", bundle: .module)
                    } else {
                        Text("Cards", bundle: .module)
                    }
                }
                ShareLink(item: file) {
                    Label {
                        Text("Share Text File", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            } else {
                options(model: $model)
                    .disabled(model.isExporting)
                if model.isExporting {
                    ProgressView {
                        Text("Exporting…", bundle: .module)
                    }
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
            }
        }
        .navigationTitle(Text("Export Text File", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .interactiveDismissDisabled(model.isExporting)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if model.isExporting {
                    Button(role: .cancel) { model.cancel() } label: {
                        Text("Cancel Export", bundle: .module)
                    }
                } else {
                    Button { dismiss() } label: {
                        if model.exportedFile != nil {
                            Text("Done", bundle: .module)
                        } else {
                            Text("Cancel", bundle: .module)
                        }
                    }
                }
            }
            if model.exportedFile == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.export() }
                    } label: {
                        Text("Export", bundle: .module)
                    }
                    .disabled(model.isExporting)
                }
            }
        }
        .task { await model.loadDecks() }
    }

    private func options(model fields: Bindable<TextExportModel>) -> some View {
        Section {
            Picker(selection: fields.format) {
                Text("Notes in Plain Text", bundle: .module).tag(TextExportModel.Format.notes)
                Text("Cards in Plain Text", bundle: .module).tag(TextExportModel.Format.cards)
            } label: {
                Text("Format", bundle: .module)
            }
            if model.selection == nil {
                Picker(selection: fields.deckID) {
                    Text("All Decks", bundle: .module).tag(nil as Int64?)
                    ForEach(model.decks, id: \.id) { deck in
                        Text(verbatim: deck.name).tag(Optional(deck.id))
                    }
                } label: {
                    Text("Deck", bundle: .module)
                }
            }
            Toggle(isOn: fields.includeHTML) { Text("Include HTML", bundle: .module) }
            if model.format == .notes {
                Toggle(isOn: fields.includeTags) { Text("Include Tags", bundle: .module) }
                Toggle(isOn: fields.includeDeck) { Text("Include Deck Name", bundle: .module) }
                Toggle(isOn: fields.includeNoteType) { Text("Include Note Type", bundle: .module) }
                Toggle(isOn: fields.includeGUID) { Text("Include GUID", bundle: .module) }
            }
        } footer: {
            Text("Text files use tabs between columns.", bundle: .module)
        }
    }
}
