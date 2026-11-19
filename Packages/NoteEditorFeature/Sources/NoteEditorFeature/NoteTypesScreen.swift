import AnkiCore
import AnkiProto
import CollectionStore
import SwiftUI

public struct NoteTypesScreen: View {
    private let manager: NoteTypeManager
    @State private var entries: [ManagedNoteType]?
    @State private var search = ""
    @State private var showsAdd = false
    @State private var failure: String?

    public init(store: CollectionStore) {
        manager = NoteTypeManager(store: store)
    }

    public var body: some View {
        Group {
            if let entries {
                let matches = entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                if matches.isEmpty && !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List(matches) { entry in
                        NavigationLink {
                            NoteTypeDetailScreen(manager: manager, entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name)
                                Text("\(entry.noteCount) Notes", bundle: .module)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if failure != nil {
                ContentUnavailableView {
                    Label {
                        Text("Could Not Load Note Types", bundle: .module)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } actions: {
                    Button { Task { await refresh() } } label: { Text("Try Again", bundle: .module) }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text("Note Types", bundle: .module))
        .searchable(text: $search, prompt: Text("Search Note Types", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsAdd = true } label: {
                    Label { Text("Add Note Type", bundle: .module) } icon: { Image(systemName: "plus") }
                }
                .disabled(entries == nil)
            }
        }
        .sheet(isPresented: $showsAdd) {
            AddNoteTypeSheet(manager: manager, entries: entries ?? [])
        }
        .noteTypeError($failure)
        .task {
            let changes = manager.store.changes()
            await refresh()
            for await change in changes where !change.isDisjoint(with: [.notetype, .note]) {
                await refresh()
            }
        }
    }

    private func refresh() async {
        do { entries = try await manager.entries() }
        catch { failure = error.localizedDescription }
    }
}

private struct AddNoteTypeSheet: View {
    let manager: NoteTypeManager
    let entries: [ManagedNoteType]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var stockSources: [StockNoteTypeChoice] = []
    @State private var source: NoteTypeSource = .stock(.basic)
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) { Text("Name", bundle: .module) }
                Picker(selection: $source) {
                    Section {
                        ForEach(stockSources) { choice in
                            Text(choice.name).tag(NoteTypeSource.stock(choice.id))
                        }
                    } header: {
                        Text("Stock Note Types", bundle: .module)
                    }
                    Section {
                        ForEach(entries) { entry in
                            Text(entry.name).tag(NoteTypeSource.existing(entry.id))
                        }
                    } header: {
                        Text("Clone a Note Type", bundle: .module)
                    }
                } label: {
                    Text("Start From", bundle: .module)
                }
            }
            .disabled(busy)
            .navigationTitle(Text("Add Note Type", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await add() }
                    } label: { Text("Add", bundle: .module) }
                    .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .noteTypeError($failure)
        }
        .interactiveDismissDisabled(busy)
        .task {
            do { stockSources = try await manager.stockChoices() }
            catch { failure = error.localizedDescription }
        }
    }

    private func add() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await manager.add(named: name, from: source)
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}

private struct NoteTypeDetailScreen: View {
    @Environment(\.locale) private var locale
    let manager: NoteTypeManager
    let entry: ManagedNoteType
    @Environment(\.dismiss) private var dismiss
    @State private var type: Anki_Notetypes_Notetype?
    @State private var textEdit: NoteTypeTextEdit?
    @State private var templateEditor: TemplateSelection?
    @State private var removingField: String?
    @State private var confirmsDeletion = false
    @State private var pendingSyncAction: DetailAction?
    @State private var confirmsSync = false
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        Group {
            if let type {
                List {
                    Section {
                        ForEach(Array(type.fields.enumerated()), id: \.element.name) { index, field in
                            fieldRow(field, index: index, in: type)
                        }
                        Button {
                            textEdit = NoteTypeTextEdit(title: "Add Field", label: "Name", initial: "") { name in
                                try await apply(.field(.add(name)), presentSyncImmediately: false)
                            }
                        } label: {
                            Label { Text("Add Field", bundle: .module) } icon: { Image(systemName: "plus") }
                        }
                    } header: {
                        Text("Fields", bundle: .module)
                    }
                    Section {
                        ForEach(Array(type.templates.enumerated()), id: \.offset) { index, template in
                            Button {
                                templateEditor = TemplateSelection(index: index)
                            } label: {
                                LabeledContent {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                } label: {
                                    Label(template.name, systemImage: "rectangle.on.rectangle")
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    } header: {
                        Text("Card Templates", bundle: .module)
                    }
                }
                .disabled(busy)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(type?.name ?? entry.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        textEdit = NoteTypeTextEdit(title: "Rename Note Type", label: "Name", initial: type?.name ?? entry.name) {
                            try await manager.rename(entry.id, to: $0)
                            await refresh()
                        }
                    } label: {
                        Label { Text("Rename Note Type", bundle: .module) } icon: { Image(systemName: "pencil") }
                    }
                    Button(role: .destructive) { confirmsDeletion = true } label: {
                        Label { Text("Delete Note Type", bundle: .module) } icon: { Image(systemName: "trash") }
                    }
                } label: {
                    Label { Text("Note Type Actions", bundle: .module) } icon: { Image(systemName: "ellipsis.circle") }
                }
                .disabled(busy || type == nil)
            }
        }
        .sheet(item: $textEdit, onDismiss: presentPendingSync) { edit in
            NoteTypeTextSheet(edit: edit)
        }
        .sheet(item: $templateEditor, onDismiss: { Task { await refresh() } }) { selection in
            CardTemplateEditorScreen(store: manager.store, noteTypeID: entry.id, initialTemplate: selection.index)
        }
        .alert(Text("Delete Field?", bundle: .module), isPresented: removingFieldPresented, presenting: removingField) { field in
            Button(role: .destructive) {
                Task { await perform(.field(.delete(field: field))) }
            } label: { Text("Delete", bundle: .module) }
            Button(role: .cancel) {}
        } message: { field in
            Text("Deleting “\(field)” removes its content from every note of this type.", bundle: .module)
        }
        .alert(Text("Delete Note Type?", bundle: .module), isPresented: $confirmsDeletion) {
            Button(role: .destructive) { Task { await perform(.deleteType) } } label: { Text("Delete", bundle: .module) }
            Button(role: .cancel) {}
        } message: {
            Text("This deletes all notes of this type and their cards.", bundle: .module)
        }
        .noteTypeSyncConfirmation(isPresented: $confirmsSync, onCancel: { pendingSyncAction = nil }) {
            guard let action = pendingSyncAction else { return }
            pendingSyncAction = nil
            Task { await perform(action, confirming: true) }
        }
        .noteTypeError($failure)
        .task { await refresh() }
    }

    private func fieldRow(
        _ field: Anki_Notetypes_Notetype.Field,
        index: Int,
        in type: Anki_Notetypes_Notetype
    ) -> some View {
        let language = manager.keyboardLanguage(of: field)
        return Menu {
            Button {
                textEdit = NoteTypeTextEdit(title: "Rename Field", label: "Name", initial: field.name) { name in
                    try await apply(.field(.rename(field: field.name, to: name)), presentSyncImmediately: false)
                }
            } label: {
                Label { Text("Rename Field", bundle: .module) } icon: { Image(systemName: "pencil") }
            }
            Menu {
                ForEach(Array(type.fields.indices), id: \.self) { position in
                    Button {
                        Task { await perform(.field(.move(field: field.name, to: position))) }
                    } label: { Text("\(position + 1)") }
                    .disabled(position == index)
                }
            } label: {
                Label { Text("Move to Position", bundle: .module) } icon: { Image(systemName: "line.3.horizontal") }
            }
            .disabled(type.fields.count < 2)
            Button {
                Task { await perform(.field(.useForSorting(field: field.name))) }
            } label: {
                Label { Text("Sort the Browser by This Field", bundle: .module) } icon: { Image(systemName: "list.number") }
            }
            .disabled(index == Int(type.config.sortFieldIdx))
            Button {
                textEdit = NoteTypeTextEdit(
                    title: "Keyboard Language", label: "Language Tag", initial: language ?? "", allowsEmpty: true
                ) { value in
                    try await apply(.field(.setKeyboardLanguage(
                        field: field.name, language: value.isEmpty ? nil : value
                    )), presentSyncImmediately: false)
                }
            } label: {
                Label { Text("Keyboard Language", bundle: .module) } icon: { Image(systemName: "keyboard") }
            }
            Button(role: .destructive) {
                removingField = field.name
            } label: {
                Label { Text("Delete Field", bundle: .module) } icon: { Image(systemName: "trash") }
            }
            .disabled(type.fields.count < 2 || field.config.preventDeletion)
        } label: {
            LabeledContent {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.name)
                    if index == Int(type.config.sortFieldIdx) {
                        Text("Sort Field", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let language {
                        Text(locale.localizedString(forIdentifier: language) ?? language)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private var removingFieldPresented: Binding<Bool> {
        Binding(get: { removingField != nil }, set: { if !$0 { removingField = nil } })
    }

    private func refresh() async {
        do { type = try await manager.noteType(entry.id) }
        catch { failure = error.localizedDescription }
    }

    private func apply(_ action: DetailAction, confirming: Bool = false, presentSyncImmediately: Bool) async throws(CoreError) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let result = switch action {
        case .field(let change):
            try await manager.editFields(of: entry.id, change, confirmingFullSync: confirming)
        case .deleteType:
            try await manager.delete(entry.id, confirmingFullSync: confirming)
        }
        switch result {
        case .needsFullSyncConfirmation:
            pendingSyncAction = action
            if presentSyncImmediately { presentPendingSync() }
        case .saved:
            switch action {
            case .field: await refresh()
            case .deleteType: dismiss()
            }
        }
    }

    private func perform(_ action: DetailAction, confirming: Bool = false) async {
        do { try await apply(action, confirming: confirming, presentSyncImmediately: true) }
        catch { failure = error.localizedDescription }
    }

    private func presentPendingSync() {
        confirmsSync = pendingSyncAction != nil
    }

    private enum DetailAction {
        case field(NoteTypeFieldAction)
        case deleteType
    }

    private struct TemplateSelection: Identifiable {
        let index: Int
        var id: Int { index }
    }
}

struct StockNoteTypeChoice: Identifiable {
    let id: Anki_Notetypes_StockNotetype.Kind
    let name: String
}

extension NoteTypeManager {
    func stockChoices() async throws(CoreError) -> [StockNoteTypeChoice] {
        var choices: [StockNoteTypeChoice] = []
        for kind in Anki_Notetypes_StockNotetype.Kind.allCases {
            let stock = try await store.core.getStockNotetypeLegacy(.with { $0.kind = kind })
            if let json = try? JSONSerialization.jsonObject(with: stock.json) as? [String: Any],
               let name = json["name"] as? String {
                choices.append(StockNoteTypeChoice(id: kind, name: name))
            }
        }
        return choices
    }
}
