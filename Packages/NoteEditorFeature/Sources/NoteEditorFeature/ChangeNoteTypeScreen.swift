import CollectionStore
import SwiftUI

public struct ChangeNoteTypeScreen: View {
    @State private var model: NoteTypeConversionModel
    private let onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var confirmSync = false
    @State private var preview: [DraftCard] = []
    @State private var showingPreview = false
    @State private var failure: String?

    public init(store: CollectionStore, noteIDs: [Int64], onSave: @escaping () async -> Void = {}) {
        self.init(model: NoteTypeConversionModel(store: store, noteIDs: noteIDs), onSave: onSave)
    }

    init(model: NoteTypeConversionModel, onSave: @escaping () async -> Void) {
        _model = State(initialValue: model)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Change Note Type", bundle: .module))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) { dismiss() }.disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { await save() } } label: { Text("Save", bundle: .module) }
                            .disabled(busy || !model.hasChanges)
                    }
                }
                .navigationDestination(isPresented: $showingPreview) {
                    NotePreviewScreen(cards: preview, initialOrdinal: preview.first?.id ?? 0, mediaFolder: model.store.location.mediaFolder)
                }
                .noteTypeSyncConfirmation(isPresented: $confirmSync) {
                    Task { await save(confirming: true) }
                }
                .noteTypeError($failure)
        }
        .interactiveDismissDisabled(busy)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let destinationID = model.destinationID {
            Form {
                Section {
                    LabeledContent {
                        Text(model.sourceName)
                    } label: {
                        Text("Current Note Type", bundle: .module)
                    }
                    Picker(selection: Binding(get: { destinationID }, set: { id in Task { await choose(id) } })) {
                        ForEach(model.destinations) { Text($0.name).tag($0.id) }
                    } label: {
                        Text("New Note Type", bundle: .module)
                    }
                } footer: {
                    if model.noteCount > 1 {
                        Text("\(model.noteCount) Notes Selected", bundle: .module)
                    }
                }
                Section {
                    ForEach(model.fieldMappings) { row in
                        mappingPicker(row, names: model.sourceFields, set: { model.mapField(row.id, from: $0) })
                    }
                } header: {
                    Text("Fields", bundle: .module)
                } footer: {
                    if !model.unmappedFields.isEmpty {
                        Text("Field content will be removed from \(model.unmappedFields.formatted(.list(type: .and))).", bundle: .module)
                    }
                }
                Section {
                    if model.usesClozeOrdinals {
                        Text("Cards are matched by position when changing to or from a cloze note type.", bundle: .module)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.templateMappings) { row in
                            mappingPicker(row, names: model.sourceTemplates, set: { model.mapTemplate(row.id, from: $0) })
                        }
                    }
                } header: {
                    Text("Card Templates", bundle: .module)
                } footer: {
                    if !model.unmappedTemplates.isEmpty {
                        Text("Cards and scheduling will be removed from \(model.unmappedTemplates.formatted(.list(type: .and))).", bundle: .module)
                    }
                }
                Section {
                    Button { Task { await showPreview() } } label: {
                        Label { Text("Preview", bundle: .module) } icon: { Image(systemName: "eye") }
                    }
                } footer: {
                    if model.noteCount > 1 {
                        Text("The preview shows one selected note.", bundle: .module)
                    }
                }
            }
            .disabled(busy)
        } else if busy {
            ProgressView()
        } else {
            ContentUnavailableView {
                Label { Text("Could Not Load Note Type Mappings", bundle: .module) } icon: { Image(systemName: "exclamationmark.triangle") }
            } actions: {
                Button { Task { await load() } } label: { Text("Try Again", bundle: .module) }
            }
        }
    }

    private func mappingPicker(_ row: NoteTypeMapping, names: [String], set: @escaping @MainActor @Sendable (Int?) -> Void) -> some View {
        Picker(selection: Binding(get: { row.source }, set: set)) {
            Text("Nothing", bundle: .module).tag(Int?.none)
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                Text(name).tag(Optional(index))
            }
        } label: {
            Text(row.destination)
        }
        .accessibilityHint(Text("Choose the source for this destination.", bundle: .module))
    }

    private func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await model.load() }
        catch { failure = error.localizedDescription }
    }

    private func choose(_ id: Int64) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await model.chooseDestination(id) }
        catch { failure = error.localizedDescription }
    }

    private func showPreview() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            preview = try await model.preview()
            showingPreview = true
        } catch { failure = error.localizedDescription }
    }

    private func save(confirming: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            switch try await model.save(confirmingFullSync: confirming) {
            case .saved:
                await onSave()
                dismiss()
            case .needsFullSyncConfirmation:
                confirmSync = true
            }
        } catch { failure = error.localizedDescription }
    }
}
