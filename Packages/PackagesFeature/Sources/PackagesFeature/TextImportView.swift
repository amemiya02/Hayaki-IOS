import CollectionStore
import SwiftUI
import UniformTypeIdentifiers

public struct TextImportButton: View {
    @Environment(TextImportModel.self) private var model: TextImportModel?

    public init() {}

    public var body: some View {
        Button {
            model?.show()
        } label: {
            Label {
                Text("Import Text File", bundle: .module)
            } icon: {
                Image(systemName: "tablecells")
            }
        }
        .disabled(model == nil)
    }
}

extension View {
    public func textImport(_ model: TextImportModel) -> some View {
        environment(model)
            .sheet(isPresented: Binding(
                get: { model.isPresented },
                set: { if !$0 { model.dismiss() } }
            )) {
                TextImportSheet(model: model)
            }
    }
}

private struct TextImportSheet: View {
    let model: TextImportModel
    @State private var choosingFile = false
    @State private var pickerError: String?
    var body: some View {
        NavigationStack {
            Form {
                Button {
                    choosingFile = true
                } label: {
                    Text("Choose Text File", bundle: .module)
                }
                .disabled(model.isWorking)
                if let summary = model.summary {
                    result(summary)
                } else if let metadata = model.metadata {
                    inputOptions(metadata)
                        .disabled(model.isWorking)
                    fieldMapping(metadata)
                        .disabled(model.isWorking)
                    preview(metadata)
                }
                if model.isWorking {
                    ProgressView {
                        if let progress = model.progress {
                            Text(verbatim: progress)
                        } else {
                            Text("Reading Text File…", bundle: .module)
                        }
                    }
                }
                if let error = model.error ?? pickerError {
                    Label(error, systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle(Text("Import Text File", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        if model.isImporting { model.cancel() } else { model.dismiss() }
                    } label: {
                        if model.summary == nil {
                            Text("Cancel", bundle: .module)
                        } else {
                            Text("Done", bundle: .module)
                        }
                    }
                    .disabled(model.isWorking && !model.isImporting)
                }
                if model.summary == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await model.startImport() }
                        } label: {
                            Text("Import", bundle: .module)
                        }
                        .disabled(model.isWorking || model.metadata == nil)
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isWorking)
        .fileImporter(
            isPresented: $choosingFile,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let file):
                pickerError = nil
                Task { await model.prepare(file) }
            case .failure(let error): pickerError = error.localizedDescription
            }
        }
    }

    private func inputOptions(_ metadata: TextImportModel.Metadata) -> some View {
        Section {
            Picker(selection: Binding(
                get: { model.metadata?.delimiter ?? metadata.delimiter },
                set: { delimiter in Task { await model.updatePreview(delimiter: delimiter) } }
            )) {
                ForEach(TextImportModel.Metadata.Delimiter.allCases, id: \.rawValue) { delimiter in
                    delimiter.title.tag(delimiter)
                }
            } label: {
                Text("Delimiter", bundle: .module)
            }
            .disabled(metadata.forceDelimiter)
            Toggle(isOn: option(\.isHtml, fallback: false)) {
                Text("Allow HTML in Fields", bundle: .module)
            }
            .disabled(metadata.forceIsHtml)
            Picker(selection: option(\.dupeResolution, fallback: .update)) {
                Text("Update Existing Notes", bundle: .module).tag(TextImportModel.Metadata.DupeResolution.update)
                Text("Preserve Existing Notes", bundle: .module).tag(TextImportModel.Metadata.DupeResolution.preserve)
                Text("Add Duplicates", bundle: .module).tag(TextImportModel.Metadata.DupeResolution.duplicate)
            } label: {
                Text("Existing Notes", bundle: .module)
            }
            Picker(selection: option(\.matchScope, fallback: .notetype)) {
                Text("Note Type", bundle: .module).tag(TextImportModel.Metadata.MatchScope.notetype)
                Text("Note Type and Deck", bundle: .module).tag(TextImportModel.Metadata.MatchScope.notetypeAndDeck)
            } label: {
                Text("Match Scope", bundle: .module)
            }
        } header: {
            if let name = model.fileName { Text(verbatim: name) }
        }
    }

    private func fieldMapping(_ metadata: TextImportModel.Metadata) -> some View {
        Section {
            Picker(selection: Binding(
                get: { model.metadata?.deckID ?? 0 },
                set: { id in
                    if id == 0 { model.useFileDeck() } else { model.updateOptions { $0.deckID = id } }
                }
            )) {
                if model.suggestsDeckFromFile {
                    Text("From File", bundle: .module).tag(Int64(0))
                }
                ForEach(model.deckChoices, id: \.id) { deck in
                    Text(verbatim: deck.name).tag(deck.id)
                }
            } label: {
                Text("Deck", bundle: .module)
            }
            Picker(selection: Binding(
                get: { model.metadata?.globalNotetype.id ?? 0 },
                set: { id in
                    if id == 0 { model.useFileNoteType() } else { Task { await model.updatePreview(notetypeID: id) } }
                }
            )) {
                if model.suggestsNoteTypeFromFile {
                    Text("From File", bundle: .module).tag(Int64(0))
                }
                ForEach(model.noteTypeChoices, id: \.id) { type in
                    Text(verbatim: type.name).tag(type.id)
                }
            } label: {
                Text("Note Type", bundle: .module)
            }
            ForEach(Array(model.fieldNames.enumerated()), id: \.offset) { index, field in
                Picker(selection: Binding(
                    get: {
                        let columns = model.metadata?.globalNotetype.fieldColumns ?? []
                        return columns.indices.contains(index) ? columns[index] : 0
                    },
                    set: { column in model.setFieldColumn(column, forField: index) }
                )) {
                    columns(metadata)
                } label: {
                    Text(verbatim: field)
                }
            }
            Picker(selection: option(\.tagsColumn, fallback: 0)) {
                columns(metadata)
            } label: {
                Text("Tags Column", bundle: .module)
            }
            Picker(selection: option(\.guidColumn, fallback: 0)) {
                columns(metadata)
            } label: {
                Text("GUID Column", bundle: .module)
            }
        } header: {
            Text("Field Mapping", bundle: .module)
        }
    }

    @ViewBuilder
    private func columns(_ metadata: TextImportModel.Metadata) -> some View {
        Text("None", bundle: .module).tag(UInt32(0))
        ForEach(Array(metadata.columnLabels.enumerated()), id: \.offset) { index, label in
            if label.isEmpty {
                Text("Column \(index + 1)", bundle: .module).tag(UInt32(index + 1))
            } else {
                Text(verbatim: label).tag(UInt32(index + 1))
            }
        }
    }

    private func preview(_ metadata: TextImportModel.Metadata) -> some View {
        Section {
            ForEach(Array(metadata.preview.enumerated()), id: \.offset) { _, row in
                Text(verbatim: row.vals.joined(separator: " · "))
                    .textSelection(.enabled)
            }
        } header: {
            Text("Preview", bundle: .module)
        }
    }

    private func result(_ summary: TextImportSummary) -> some View {
        Section {
            resultCount(Text("Added", bundle: .module), summary.added)
            resultCount(Text("Updated", bundle: .module), summary.updated)
            resultCount(Text("Skipped", bundle: .module), summary.skipped)
            resultCount(Text("Invalid Rows", bundle: .module), summary.invalidRows)
        }
    }

    private func resultCount(_ label: Text, _ count: Int) -> some View {
        LabeledContent {
            Text(count.formatted())
        } label: {
            label
        }
    }

    private func option<Value>(
        _ key: WritableKeyPath<TextImportModel.Metadata, Value>, fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { model.metadata?[keyPath: key] ?? fallback },
            set: { value in model.updateOptions { $0[keyPath: key] = value } }
        )
    }
}

private extension TextImportModel.Metadata.Delimiter {
    var title: Text {
        switch self {
        case .tab: Text("Tab", bundle: .module)
        case .pipe: Text("Pipe", bundle: .module)
        case .semicolon: Text("Semicolon", bundle: .module)
        case .colon: Text("Colon", bundle: .module)
        case .comma: Text("Comma", bundle: .module)
        case .space: Text("Space", bundle: .module)
        case .UNRECOGNIZED: Text("Unknown Delimiter", bundle: .module)
        }
    }
}
