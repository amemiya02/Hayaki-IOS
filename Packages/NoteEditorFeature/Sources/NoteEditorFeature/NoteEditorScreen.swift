import CollectionStore
import PhotosUI
import SwiftUI

/// Adds or edits notes in a sheet. When adding, the editor stays open for
/// the next note.
public struct NoteEditorScreen: View {
    @State private var model: NoteEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var isBusy = false
    @State private var confirmDeletion = false
    @State private var confirmDiscard = false
    @State private var confirmDiscardForConversion = false
    @State private var showingConversion = false
    @State private var preview: PreviewRequest?
    @State private var newTag = ""
    @State private var markupFields: Set<Int> = []
    @State private var selections: [Int: TextSelection] = [:]
    @AppStorage("noteEditorToolbarLayout") private var toolbarLayout = EditorToolbarLayout.scroll
    private let onDelete: () -> Void
    @State private var warning: AddWarning?
    @State private var refusal: AddProblem?
    @State private var failure: String?
    @State private var added: AddedNote?
    @FocusState private var focusedField: Int?

    public init(store: CollectionStore) {
        _model = State(initialValue: NoteEditorModel(store: store))
        onDelete = {}
    }

    public init(store: CollectionStore, editingCardID: Int64, onDelete: @escaping () -> Void = {}) {
        _model = State(initialValue: NoteEditorModel(store: store, editingCardID: editingCardID))
        self.onDelete = onDelete
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.isEditing ? Text("Edit Note", bundle: .module) : Text("Add Note", bundle: .module))
                .toolbarTitleDisplayModeInline()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close, action: close)
                            .disabled(isBusy)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            Task { await showPreview() }
                        } label: {
                            Label { Text("Preview", bundle: .module) } icon: { Image(systemName: "eye") }
                        }
                        .accessibilityIdentifier("preview-note")
                        .disabled(model.state != .ready || isBusy)
                        editorMenu
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                            Task { await submit() }
                        } label: {
                            if model.isEditing { Text("Save", bundle: .module) }
                            else { Text("Add", bundle: .module) }
                        }
                        .accessibilityIdentifier("submit-note")
                        .disabled(model.state != .ready || isBusy)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        addedBanner
                        if model.state == .ready {
                            EditorFormattingToolbar(layout: toolbarLayout, isCloze: model.isCloze, format: applyFormat)
                                .disabled(isBusy)
                        }
                    }
                }
                .navigationDestination(isPresented: isPresent($preview)) {
                    if let preview {
                        NotePreviewScreen(
                            cards: preview.cards,
                            initialOrdinal: model.preferredPreviewOrdinal,
                            mediaFolder: model.mediaFolder
                        )
                    }
                }
        }
        .task { await model.load() }
        .interactiveDismissDisabled(isBusy || model.hasChanges || !newTag.isEmpty)
        .alert(Text("Discard Changes?", bundle: .module), isPresented: $confirmDiscard) {
            Button(role: .destructive) { dismiss() } label: { Text("Discard", bundle: .module) }
            Button(role: .cancel) {}
        }
        .sheet(isPresented: $showingConversion) {
            if let conversion = model.noteTypeConversion() {
                ChangeNoteTypeScreen(model: conversion, onSave: reloadAfterConversion)
            }
        }
        .alert(Text("Discard Changes?", bundle: .module), isPresented: $confirmDiscardForConversion) {
            Button(role: .destructive) {
                model.discardDraft()
                resetFieldInput()
                showingConversion = true
            } label: {
                Text("Discard", bundle: .module)
            }
            Button(role: .cancel) {}
        } message: {
            Text("Changing the note type uses the saved note.", bundle: .module)
        }
        .alert(Text("Delete Note?", bundle: .module), isPresented: $confirmDeletion) {
            Button(role: .destructive) {
                Task { await deleteNote() }
            } label: {
                Text("Delete", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: {
            Text("This deletes the note and all its cards.", bundle: .module)
        }
        .alert(warningTitle, isPresented: isPresent($warning), presenting: warning) { warning in
            Button {
                Task { await submit(confirming: warning) }
            } label: {
                if model.isEditing { Text("Save Anyway", bundle: .module) }
                else { Text("Add Anyway", bundle: .module) }
            }
            Button(role: .cancel) {}
        } message: { warning in
            warningMessage(warning)
        }
        .alert(refusalTitle, isPresented: isPresent($refusal), presenting: refusal) { _ in
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: { refusal in
            refusalMessage(refusal)
        }
        .alert(Text("Could Not Change the Note", bundle: .module), isPresented: isPresent($failure), presenting: failure) { _ in
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    if model.isEditing { Text("Could Not Open the Note", bundle: .module) }
                    else { Text("Could Not Start a Note", bundle: .module) }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(message)
            }
        case .ready:
            form.disabled(isBusy)
        }
    }

    private var form: some View {
        Form {
            Section {
                if model.isEditing {
                    if let name = model.notetypeName {
                        Button(action: changeNoteType) {
                            LabeledContent {
                                HStack {
                                    Text(name)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .accessibilityHidden(true)
                                }
                            } label: {
                                Text("Note Type", bundle: .module)
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("change-editor-note-type")
                    }
                    if let name = model.deckName {
                        LabeledContent { Text(name) } label: { Text("Deck", bundle: .module) }
                    }
                } else {
                    Picker(selection: notetypeSelection) {
                        ForEach(model.notetypes) { notetype in
                            Text(notetype.name).tag(notetype.id)
                        }
                    } label: {
                        Text("Note Type", bundle: .module)
                    }
                    Picker(selection: deckSelection) {
                        ForEach(model.decks) { deck in
                            Text(deck.name).tag(deck.id)
                        }
                    } label: {
                        Text("Deck", bundle: .module)
                    }
                    .navigationLinkPickerStyle()
                }
            }
            ForEach(Array(model.fields.enumerated()), id: \.offset) { index, field in
                FieldSection(
                    model: model, index: index, field: field,
                    focusedField: $focusedField,
                    selection: Binding(get: { selections[index] }, set: { selections[index] = $0 }),
                    showsMarkup: field.requiresMarkup || markupFields.contains(index),
                    toggleMarkup: {
                        selections[index] = nil
                        if markupFields.contains(index) { markupFields.remove(index) }
                        else { markupFields.insert(index) }
                    },
                    toggleSticky: { Task { await setSticky(index) } }
                )
            }
            TagsSection(model: model, newTag: $newTag)
        }
    }

    private var editorMenu: some View {
        Menu {
            Picker(selection: $toolbarLayout) {
                ForEach(EditorToolbarLayout.allCases, id: \.self) { layout in
                    layout.title.tag(layout)
                }
            } label: {
                Text("Toolbar Layout", bundle: .module)
            }
            if model.isEditing {
                Button(role: .destructive) {
                    confirmDeletion = true
                } label: {
                    Label { Text("Delete Note", bundle: .module) } icon: { Image(systemName: "trash") }
                }
            }
        } label: {
            Label { Text("Editor Options", bundle: .module) } icon: { Image(systemName: "ellipsis.circle") }
        }
        .disabled(model.state != .ready || isBusy)
    }

    private func close() {
        if model.hasChanges || !newTag.isEmpty { confirmDiscard = true }
        else { dismiss() }
    }

    private func changeNoteType() {
        if model.hasChanges || !newTag.isEmpty { confirmDiscardForConversion = true }
        else { showingConversion = true }
    }

    private func reloadAfterConversion() async {
        do {
            try await model.reloadAfterNoteTypeChange()
            resetFieldInput()
        } catch {
            failure = error.message
        }
    }

    private func resetFieldInput() {
        selections = [:]
        markupFields = []
        focusedField = nil
        newTag = ""
    }

    private func commitTags() {
        model.addTags(newTag)
        newTag = ""
    }

    private func submit(confirming accepted: AddWarning? = nil) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        commitTags()
        if model.isEditing {
            switch await model.save(confirming: accepted) {
            case .saved: dismiss()
            case .needsConfirmation(let warning): self.warning = warning
            case .refused(let problem): refusal = problem
            case .failed(let message): failure = message
            }
        } else {
            switch await model.add(confirming: accepted) {
            case .added(let note):
                withAnimation { added = note }
                markupFields = []
                selections = [:]
                focusedField = 0
                AccessibilityNotification.Announcement(addedMessage(note)).post()
            case .needsConfirmation(let warning): self.warning = warning
            case .refused(let problem): refusal = problem
            case .failed(let message): failure = message
            }
        }
    }

    private func deleteNote() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await model.delete()
            onDelete()
            dismiss()
        } catch {
            failure = error.message
        }
    }

    private func showPreview() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        commitTags()
        do {
            preview = PreviewRequest(cards: try await model.preview())
        } catch {
            failure = error.message
        }
    }

    private func setSticky(_ index: Int) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await model.setSticky(!model.isSticky(index), ofField: index)
        } catch {
            failure = error.message
        }
    }

    private func applyFormat(_ format: EditorTextFormat) {
        let index = focusedField ?? 0
        guard model.fields.indices.contains(index) else { return }
        let field = model.fields[index]
        let editingMarkup = field.requiresMarkup || markupFields.contains(index)
        let displayed = editingMarkup ? field.content : field.text
        let selected: Range<String.Index>
        if case .selection(let range) = selections[index]?.indices,
           range.lowerBound >= displayed.startIndex, range.upperBound <= displayed.endIndex,
           displayed.indices.contains(range.lowerBound) || range.lowerBound == displayed.endIndex,
           displayed.indices.contains(range.upperBound) || range.upperBound == displayed.endIndex {
            selected = range
        } else {
            selected = displayed.endIndex..<displayed.endIndex
        }
        let before = String(displayed[..<selected.lowerBound])
        let selectedText = String(displayed[selected])
        let after = String(displayed[selected.upperBound...])
        let wrap = format.wrapper(fields: model.fields)
        let start = (editingMarkup ? before : FieldMarkup.html(fromPlainText: before)) + wrap.prefix
        let middle = editingMarkup ? selectedText : FieldMarkup.html(fromPlainText: selectedText)
        var html = start + middle + wrap.suffix + (editingMarkup ? after : FieldMarkup.html(fromPlainText: after))
        if !editingMarkup {
            html += field.images.map { "<img src=\"\(FieldMarkup.escaped($0, quotes: true))\">" }.joined()
        }
        model.setMarkup(html, ofField: index)
        markupFields.insert(index)
        let lower = html.index(html.startIndex, offsetBy: start.count)
        let upper = html.index(lower, offsetBy: middle.count)
        selections[index] = TextSelection(range: lower..<upper)
        focusedField = index
    }

    @ViewBuilder
    private var addedBanner: some View {
        if let added {
            Text(addedMessage(added))
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect()
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: added.noteID) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { self.added = nil }
                }
        }
    }

    private func addedMessage(_ note: AddedNote) -> String {
        String(localized: "Note added with \(note.cardCount) cards.", bundle: .module)
    }

    // MARK: Messages

    private var warningTitle: Text {
        switch warning {
        case .duplicate: Text("Duplicate Note", bundle: .module)
        case .noClozeDeletions, nil: Text("No Cloze Deletions", bundle: .module)
        }
    }

    private func warningMessage(_ warning: AddWarning) -> Text {
        switch warning {
        case .duplicate:
            Text("Another note of this note type has the same first field.", bundle: .module)
        case .noClozeDeletions:
            Text("This is a cloze note type, but the note has no cloze deletions, such as {{c1::text}}.", bundle: .module)
        }
    }

    private var refusalTitle: Text {
        model.isEditing ? Text("Cannot Save the Note", bundle: .module) : Text("Cannot Add the Note", bundle: .module)
    }

    private func refusalMessage(_ problem: AddProblem) -> Text {
        switch problem {
        case .firstFieldEmpty:
            Text("The first field is empty.", bundle: .module)
        case .clozeOutsideClozeNotetype:
            Text("Cloze deletions can only be used with a cloze note type.", bundle: .module)
        case .clozeOutsideClozeField:
            Text("Cloze deletions can only be used in the note type's cloze field, usually the first.", bundle: .module)
        }
    }

    // MARK: Bindings

    private func selectNotetype(_ id: Int64) async {
        guard !isBusy, id != model.notetypeID else { return }
        isBusy = true
        defer { isBusy = false }
        await model.selectNotetype(id)
        selections = [:]
        markupFields = []
    }

    private var notetypeSelection: Binding<Int64> {
        Binding(get: { model.notetypeID }, set: { id in
            Task { await selectNotetype(id) }
        })
    }

    private var deckSelection: Binding<Int64> {
        Binding(get: { model.deckID }, set: { model.selectDeck($0) })
    }

    private func isPresent<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}

private struct PreviewRequest {
    let cards: [DraftCard]
}

/// One field: its text, the images attached to it, and a button to attach
/// another from the photo library.
private struct FieldSection: View {
    let model: NoteEditorModel
    let index: Int
    let field: EditableField
    @FocusState.Binding var focusedField: Int?
    @Binding var selection: TextSelection?
    let showsMarkup: Bool
    let toggleMarkup: () -> Void
    let toggleSticky: () -> Void
    @State private var photo: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var attachError: AttachImageError?

    var body: some View {
        Section {
            TextField(text: text, selection: $selection, axis: .vertical) {
                Text(field.name)
            }
            .lineLimit(1...12)
            .focused($focusedField, equals: index)
            .accessibilityLabel(Text(field.name))
            .accessibilityIdentifier("note-field-\(index)")
            .font(showsMarkup ? .body.monospaced() : .body)
            .disableMarkupAutocorrection(showsMarkup)
            ForEach(field.images, id: \.self) { name in
                ImageRow(file: model.mediaFile(named: name), fieldName: field.name) {
                    model.removeImage(named: name, fromField: index)
                }
            }
            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) {
                Label {
                    Text("Add Image", bundle: .module)
                } icon: {
                    Image(systemName: "photo.badge.plus")
                }
            }
            .disabled(isLoadingPhoto)
            .accessibilityLabel(Text("Add Image to \(field.name)", bundle: .module))
        } header: {
            HStack {
                Text(field.name)
                Spacer()
                if !field.requiresMarkup {
                    Button(action: toggleMarkup) {
                        Image(systemName: showsMarkup ? "textformat" : "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showsMarkup ? Text("Edit Text", bundle: .module) : Text("Edit HTML", bundle: .module))
                } else {
                    Text("HTML", bundle: .module)
                        .font(.caption.monospaced())
                }
                if !model.isEditing {
                    let pinned = model.isSticky(index)
                    Button(action: toggleSticky) {
                        Image(systemName: pinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(pinned ? Text("Unpin Field", bundle: .module) : Text("Pin Field", bundle: .module))
                    .accessibilityIdentifier("sticky-field-\(index)")
                }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await attach(item) }
        }
        .alert(
            Text("Could Not Add the Image", bundle: .module),
            isPresented: Binding(get: { attachError != nil }, set: { if !$0 { attachError = nil } }),
            presenting: attachError
        ) { _ in
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        } message: { error in
            switch error {
            case .notAnImage: Text("The selected item is not an image Hayaki can read.", bundle: .module)
            case .notStored(let message): Text(message)
            }
        }
    }

    private var text: Binding<String> {
        Binding(get: { showsMarkup ? field.content : field.text }, set: {
            if showsMarkup { model.setMarkup($0, ofField: index) }
            else { model.setText($0, ofField: index) }
        })
    }

    private func attach(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer {
            isLoadingPhoto = false
            photo = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                attachError = .notAnImage
                return
            }
            try await model.attachImage(data, toField: index)
        } catch let error as AttachImageError {
            attachError = error
        } catch {
            attachError = .notStored(message: error.localizedDescription)
        }
    }
}

/// An attached image, small, with a button to remove it from the field.
private struct ImageRow: View {
    let file: URL
    let fieldName: String
    let remove: () -> Void

    var body: some View {
        HStack {
            thumbnail
                .frame(maxWidth: .infinity, maxHeight: 160, alignment: .leading)
                .accessibilityLabel(Text("Image in \(fieldName)", bundle: .module))
            Button(role: .destructive, action: remove) {
                Label {
                    Text("Remove Image", bundle: .module)
                } icon: {
                    Image(systemName: "minus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let image = UIImage(contentsOfFile: file.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 6))
        } else {
            Image(systemName: "photo")
        }
        #else
        Image(systemName: "photo")
        #endif
    }
}

/// The note's tags, each removable, and a field to add more.
private struct TagsSection: View {
    let model: NoteEditorModel
    @Binding var newTag: String

    var body: some View {
        Section {
            ForEach(model.tags, id: \.self) { tag in
                HStack {
                    Label(tag, systemImage: "tag")
                    Spacer()
                    Button {
                        model.removeTag(tag)
                    } label: {
                        Label {
                            Text("Remove \(tag)", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onDelete { offsets in
                for tag in offsets.map({ model.tags[$0] }) { model.removeTag(tag) }
            }
            TextField(text: $newTag) {
                Text("Add Tags", bundle: .module)
            }
            .noAutocapitalization()
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit {
                model.addTags(newTag)
                newTag = ""
            }
        } header: {
            Text("Tags", bundle: .module)
        } footer: {
            Text("Separate tags with spaces.", bundle: .module)
        }
    }
}

private extension View {
    @ViewBuilder
    func disableMarkupAutocorrection(_ enabled: Bool) -> some View {
        #if os(iOS)
        if enabled { autocorrectionDisabled().textInputAutocapitalization(.never) }
        else { self }
        #else
        autocorrectionDisabled(enabled)
        #endif
    }

    /// Inline titles and no automatic capitalisation exist only on iOS; the
    /// package also builds for macOS so its tests run there.
    @ViewBuilder
    func toolbarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// A long list of decks reads best on its own page.
    @ViewBuilder
    func navigationLinkPickerStyle() -> some View {
        #if os(iOS)
        pickerStyle(.navigationLink)
        #else
        self
        #endif
    }

    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
