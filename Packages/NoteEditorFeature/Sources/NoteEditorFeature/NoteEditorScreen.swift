import CollectionStore
import PhotosUI
import SwiftUI

/// Adding notes: note type, deck, fields, images and tags. Shown as a sheet
/// from anywhere in the app; it stays open after each note so several can be
/// added in a row.
public struct NoteEditorScreen: View {
    @State private var model: NoteEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var warning: AddWarning?
    @State private var refusal: AddProblem?
    @State private var failure: String?
    @State private var added: AddedNote?
    @FocusState private var focusedField: Int?

    public init(store: CollectionStore) {
        _model = State(initialValue: NoteEditorModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Add Note", bundle: .module))
                .toolbarTitleDisplayModeInline()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                            Task { await add() }
                        } label: {
                            Text("Add", bundle: .module)
                        }
                        .disabled(model.state != .ready || isAdding)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .safeAreaInset(edge: .bottom) { addedBanner }
        }
        .task { await model.load() }
        .alert(warningTitle, isPresented: isPresent($warning), presenting: warning) { warning in
            Button {
                Task { await add(confirming: warning) }
            } label: {
                Text("Add Anyway", bundle: .module)
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
        .alert(Text("Could Not Add the Note", bundle: .module), isPresented: isPresent($failure), presenting: failure) { _ in
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
                    Text("Could Not Start a Note", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(message)
            }
        case .ready:
            form
        }
    }

    private var form: some View {
        Form {
            Section {
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
            ForEach(Array(model.fields.enumerated()), id: \.offset) { index, field in
                FieldSection(model: model, index: index, field: field, focusedField: $focusedField)
            }
            TagsSection(model: model)
        }
    }

    // MARK: Adding

    private func add(confirming accepted: AddWarning? = nil) async {
        isAdding = true
        defer { isAdding = false }
        switch await model.add(confirming: accepted) {
        case .added(let note):
            withAnimation { added = note }
            focusedField = 0
            AccessibilityNotification.Announcement(addedMessage(note)).post()
        case .needsConfirmation(let warning):
            self.warning = warning
        case .refused(let problem):
            refusal = problem
        case .failed(let message):
            failure = message
        }
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
        Text("Cannot Add the Note", bundle: .module)
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

    private var notetypeSelection: Binding<Int64> {
        Binding(get: { model.notetypeID }, set: { id in Task { await model.selectNotetype(id) } })
    }

    private var deckSelection: Binding<Int64> {
        Binding(get: { model.deckID }, set: { model.selectDeck($0) })
    }

    private func isPresent<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}

/// One field: its text, the images attached to it, and a button to attach
/// another from the photo library.
private struct FieldSection: View {
    let model: NoteEditorModel
    let index: Int
    let field: EditableField
    @FocusState.Binding var focusedField: Int?
    @State private var photo: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var attachError: AttachImageError?

    var body: some View {
        Section {
            TextField(text: text, axis: .vertical) {
                Text(field.name)
            }
            .lineLimit(1...12)
            .focused($focusedField, equals: index)
            .accessibilityLabel(Text(field.name))
            ForEach(field.images, id: \.self) { name in
                ImageRow(file: model.mediaFile(named: name), fieldName: field.name) {
                    model.removeImage(named: name, fromField: index)
                }
            }
            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) {
                HStack {
                    Label {
                        Text("Add Image", bundle: .module)
                    } icon: {
                        Image(systemName: "photo.badge.plus")
                    }
                    if isLoadingPhoto {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isLoadingPhoto)
            .accessibilityLabel(Text("Add Image to \(field.name)", bundle: .module))
        } header: {
            Text(field.name)
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
        Binding(get: { field.text }, set: { model.setText($0, ofField: index) })
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
    @State private var newTag = ""

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
