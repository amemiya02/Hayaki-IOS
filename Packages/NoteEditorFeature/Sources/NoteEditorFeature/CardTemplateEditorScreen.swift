import AnkiCore
import AnkiProto
import CollectionStore
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CardTemplateEditorScreen: View {
    @State private var model: CardTemplateEditorModel
    @State private var part: TemplateSource = .front
    @State private var cursor: TextSelection?
    @State private var nameEdit: NoteTypeTextEdit?
    @State private var preview: DraftCard?
    @State private var showingPreview = false
    @State private var showingBrowserEditor = false
    @State private var showingDecks = false
    @State private var showingStockKinds = false
    @State private var restoreKind: Anki_Notetypes_StockNotetype.Kind?
    @State private var stockChoices: [StockNoteTypeChoice] = []
    @State private var decks: [Choice] = []
    @State private var failure: String?
    @State private var isBusy = false
    @State private var confirmDiscard = false
    @State private var confirmDeletion = false
    @State private var confirmRestore = false
    @State private var confirmSync = false
    @State private var saveAction: SaveAction = .save
    @Environment(\.dismiss) private var dismiss

    init(store: CollectionStore, noteTypeID: Int64, initialTemplate: Int) {
        _model = State(initialValue: CardTemplateEditorModel(
            store: store, noteTypeID: noteTypeID, initialTemplate: initialTemplate
        ))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Card Templates", bundle: .module))
                .toolbar { toolbar }
                .navigationDestination(isPresented: $showingPreview) {
                    if let preview {
                        NotePreviewScreen(cards: [preview], initialOrdinal: preview.id, mediaFolder: model.store.location.mediaFolder)
                    }
                }
                .navigationDestination(isPresented: $showingBrowserEditor) {
                    BrowserAppearanceScreen(model: model)
                }
                .navigationDestination(isPresented: $showingDecks) {
                    deckOverride
                }
                .sheet(item: $nameEdit) { NoteTypeTextSheet(edit: $0) }
                .confirmationDialog(Text("Restore to Default", bundle: .module), isPresented: $showingStockKinds, titleVisibility: .visible) {
                    ForEach(stockChoices) { type in
                        Button(type.name) {
                            restoreKind = type.id
                            confirmRestore = true
                        }
                    }
                }
                .alert(Text("Discard Changes?", bundle: .module), isPresented: $confirmDiscard) {
                    Button(role: .destructive) { dismiss() } label: { Text("Discard", bundle: .module) }
                    Button(role: .cancel) {}
                }
                .alert(Text("Delete Card Template?", bundle: .module), isPresented: $confirmDeletion) {
                    Button(role: .destructive) {
                        model.deleteTemplate()
                        cursor = nil
                    } label: { Text("Delete", bundle: .module) }
                    Button(role: .cancel) {}
                } message: {
                    Text("Saving removes all cards made from this template and their scheduling.", bundle: .module)
                }
                .alert(Text("Restore to Default?", bundle: .module), isPresented: $confirmRestore) {
                    Button(role: .destructive) {
                        Task { await save(.restore(restoreKind)) }
                    } label: { Text("Restore", bundle: .module) }
                    Button(role: .cancel) {}
                } message: {
                    Text("Restoring replaces the fields, card templates, and styling with the stock definition.", bundle: .module)
                }
                .noteTypeSyncConfirmation(isPresented: $confirmSync) {
                    Task { await save(saveAction, confirming: true) }
                }
                .noteTypeError($failure)
        }
        .interactiveDismissDisabled(isBusy || model.hasChanges)
        .task {
            do { try await model.load() }
            catch { failure = error.localizedDescription }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .cancel) {
                if model.hasChanges { confirmDiscard = true }
                else { dismiss() }
            }
            .disabled(isBusy)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await showPreview() }
            } label: {
                Label { Text("Preview", bundle: .module) } icon: { Image(systemName: "eye") }
            }
            .disabled(isBusy || model.draft == nil)
            Menu {
                actions
            } label: {
                Label { Text("Card Template Actions", bundle: .module) } icon: { Image(systemName: "ellipsis.circle") }
            }
            .disabled(isBusy || model.draft == nil)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button { Task { await save(.save) } } label: { Text("Save", bundle: .module) }
                .disabled(isBusy || model.draft == nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let type = model.draft {
            VStack(spacing: 8) {
                Picker(selection: Binding(get: { model.selectedTemplate }, set: { index in
                    model.selectTemplate(index)
                    cursor = nil
                })) {
                    ForEach(Array(type.templates.enumerated()), id: \.offset) { index, template in
                        Text(template.name).tag(index)
                    }
                } label: {
                    Text("Card Template", bundle: .module)
                }
                .padding(.horizontal)
                Picker(selection: $part) {
                    Text("Front", bundle: .module).tag(TemplateSource.front)
                    Text("Back", bundle: .module).tag(TemplateSource.back)
                    Text("Styling", bundle: .module).tag(TemplateSource.styling)
                } label: {
                    Text("Template Editor", bundle: .module)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                TextEditor(text: source, selection: $cursor)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .padding(.horizontal)
                    .onChange(of: part) { cursor = nil }
                    .accessibilityLabel(Text("Template Source", bundle: .module))
                if part != .styling {
                    ScrollView(.horizontal) {
                        HStack {
                            Text("Insert Field", bundle: .module)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(type.fields, id: \.name) { field in
                                Button(field.name) { insert(field.name) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.top, 8)
            .disabled(isBusy)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !model.isCloze {
            Button {
                model.addTemplate()
                cursor = nil
            } label: {
                Label { Text("Add Card Template", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        }
        Button {
            nameEdit = NoteTypeTextEdit(title: "Rename Card Template", label: "Name", initial: model.template?.name ?? "") {
                try model.renameTemplate($0)
            }
        } label: {
            Label { Text("Rename Card Template", bundle: .module) } icon: { Image(systemName: "pencil") }
        }
        if let templates = model.draft?.templates, templates.count > 1 {
            Menu {
                ForEach(Array(templates.indices), id: \.self) { index in
                    Button {
                        model.moveTemplate(to: index)
                        cursor = nil
                    } label: { Text("\(index + 1)") }
                    .disabled(index == model.selectedTemplate)
                }
            } label: {
                Label { Text("Move to Position", bundle: .module) } icon: { Image(systemName: "line.3.horizontal") }
            }
        }
        Button { showingDecks = true } label: {
            Label { Text("Deck Override", bundle: .module) } icon: { Image(systemName: "tray") }
        }
        Button { showingBrowserEditor = true } label: {
            Label { Text("Browser Appearance", bundle: .module) } icon: { Image(systemName: "list.bullet.rectangle") }
        }
        Button(action: copyMarkdown) {
            Label { Text("Copy as Markdown", bundle: .module) } icon: { Image(systemName: "document.on.document") }
        }
        Button(role: .destructive) {
            Task { await proposeRestore() }
        } label: {
            Label { Text("Restore to Default", bundle: .module) } icon: { Image(systemName: "arrow.counterclockwise") }
        }
        if (model.draft?.templates.count ?? 0) > 1 {
            Button(role: .destructive) {
                confirmDeletion = true
            } label: {
                Label { Text("Delete Card Template", bundle: .module) } icon: { Image(systemName: "trash") }
            }
        }
    }

    private var deckOverride: some View {
        Form {
            Picker(selection: Binding(get: { model.template?.config.targetDeckID ?? 0 }, set: model.setDeckOverride)) {
                Text("Off", bundle: .module).tag(Int64(0))
                ForEach(decks) { deck in Text(deck.name).tag(deck.id) }
                if let deckID = model.template?.config.targetDeckID, deckID != 0,
                   !decks.contains(where: { $0.id == deckID }) {
                    Text("Unavailable Deck", bundle: .module).tag(deckID)
                }
            } label: {
                Text("Deck Override", bundle: .module)
            }
        }
        .navigationTitle(Text("Deck Override", bundle: .module))
        .task {
            do {
                decks = try await model.store.core.getDeckNames(.with { $0.includeFiltered = false }).entries.map {
                    Choice(id: $0.id, name: $0.name)
                }
            } catch { failure = error.localizedDescription }
        }
    }

    private var source: Binding<String> {
        Binding(get: { model.source(for: part) }, set: { model.setSource($0, for: part) })
    }

    private func insert(_ field: String) {
        var text = source.wrappedValue
        let insertion = "{{\(field)}}"
        if case .selection(let range) = cursor?.indices,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex,
           text.indices.contains(range.lowerBound) || range.lowerBound == text.endIndex,
           text.indices.contains(range.upperBound) || range.upperBound == text.endIndex {
            text.replaceSubrange(range, with: insertion)
        } else {
            text += insertion
        }
        source.wrappedValue = text
        cursor = nil
    }

    private func copyMarkdown() {
        let markdown = """
        ## Front

        ```html
        \(model.source(for: .front))
        ```

        ## Back

        ```html
        \(model.source(for: .back))
        ```

        ## Styling

        ```css
        \(model.source(for: .styling))
        ```
        """
        #if os(iOS)
        UIPasteboard.general.string = markdown
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif
    }

    private func showPreview() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            preview = try await model.preview()
            showingPreview = true
        } catch { failure = error.localizedDescription }
    }

    private func proposeRestore() async {
        guard model.draft?.config.originalStockKind == .unknown else {
            restoreKind = nil
            confirmRestore = true
            return
        }
        do {
            stockChoices = try await NoteTypeManager(store: model.store).stockChoices()
            showingStockKinds = true
        } catch { failure = error.localizedDescription }
    }

    private func save(_ action: SaveAction, confirming: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = switch action {
            case .save: try await model.save(confirmingFullSync: confirming)
            case .restore(let kind): try await model.restore(to: kind, confirmingFullSync: confirming)
            }
            switch result {
            case .saved: dismiss()
            case .needsFullSyncConfirmation:
                saveAction = action
                confirmSync = true
            }
        } catch { failure = error.localizedDescription }
    }

    private enum SaveAction {
        case save
        case restore(Anki_Notetypes_StockNotetype.Kind?)
    }
}

private struct BrowserAppearanceScreen: View {
    let model: CardTemplateEditorModel
    @State private var preview: DraftCard?
    @State private var showingPreview = false
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                editor(.browserFront, title: "Question Format")
                editor(.browserBack, title: "Answer Format")
            } footer: {
                Text("Leave a format blank to use the corresponding study template in Browse.", bundle: .module)
            }
        }
        .disabled(busy)
        .navigationTitle(Text("Browser Appearance", bundle: .module))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.setSource("", for: .browserFront)
                    model.setSource("", for: .browserBack)
                } label: {
                    Label { Text("Reset Browser Appearance", bundle: .module) } icon: { Image(systemName: "arrow.counterclockwise") }
                }
                Button {
                    Task { await showPreview() }
                } label: {
                    Label { Text("Preview", bundle: .module) } icon: { Image(systemName: "eye") }
                }
                .disabled(busy)
            }
        }
        .navigationDestination(isPresented: $showingPreview) {
            if let preview {
                NotePreviewScreen(cards: [preview], initialOrdinal: preview.id, mediaFolder: model.store.location.mediaFolder)
            }
        }
        .noteTypeError($failure)
    }

    private func editor(_ source: TemplateSource, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading) {
            Text(title, bundle: .module).font(.subheadline)
            TextEditor(text: Binding(get: { model.source(for: source) }, set: { model.setSource($0, for: source) }))
                .frame(minHeight: 90)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel(Text(title, bundle: .module))
        }
    }

    private func showPreview() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            preview = try await model.preview(browser: true)
            showingPreview = true
        } catch { failure = error.localizedDescription }
    }
}
