import AnkiCore
import CollectionStore
import NoteEditorFeature
import StudyFeature
import SwiftUI

struct BrowserPreviewScreen: View {
    let store: CollectionStore
    @State private var cardIDs: [Int64]
    @State private var index = 0
    @State private var preview: CardPreviewContent?
    @State private var showsAnswer = false
    @State private var answerOnly = false
    @State private var noteID: Int64?
    @State private var marked = false
    @State private var flag: UInt32 = 0
    @State private var replay: UUID?
    @State private var editingCard: EditingCard?
    @State private var reload = 0
    @State private var controls = PreviewControls.load()
    @State private var busy = false
    @State private var failure: String?
    @State private var actionFailure: String?
    @Environment(\.dismiss) private var dismiss

    init(store: CollectionStore, cardIDs: [Int64]) {
        self.store = store
        _cardIDs = State(initialValue: cardIDs)
    }

    private var canGoBack: Bool { index > 0 || (showsAnswer && !answerOnly) }
    private var canGoNext: Bool { index + 1 < cardIDs.count || (preview != nil && !showsAnswer && !answerOnly) }
    private var inputEnabled: Bool { editingCard == nil && !busy && store.allowsNewProfileWork }

    var body: some View {
        NavigationStack {
            Group {
                if let preview {
                    CardPreviewView(
                        content: preview, showsAnswer: showsAnswer, mediaFolder: store.location.mediaFolder,
                        cardID: cardIDs[index], controls: editingCard == nil ? controls : nil, replay: replay,
                        onCommand: perform, onReveal: { showsAnswer = true }
                    )
                } else if let failure {
                    ContentUnavailableView {
                        Text("Could Not Preview Card", bundle: .module)
                    } description: {
                        Text(failure)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text("Preview", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
                ToolbarItem(placement: .primaryAction) {
                    actions.disabled(preview == nil || !inputEnabled)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { perform(.previous) } label: {
                        Label {
                            Text("Previous Card", bundle: .module)
                        } icon: { Image(systemName: "chevron.left") }
                        .labelStyle(.iconOnly)
                    }
                    .disabled(!canGoBack)
                    Spacer()
                    Button { showsAnswer.toggle() } label: {
                        showsAnswer ? Text("Show Question", bundle: .module) : Text("Show Answer", bundle: .module)
                    }
                    .disabled(preview == nil || answerOnly)
                    Spacer()
                    Button { perform(.next) } label: {
                        Label {
                            Text("Next Card", bundle: .module)
                        } icon: { Image(systemName: "chevron.right") }
                        .labelStyle(.iconOnly)
                    }
                    .disabled(!canGoNext)
                }
                .buttonStyle(.bordered)
                .disabled(!inputEnabled)
                .padding()
                .background(.bar)
            }
            .task(id: LoadKey(index: index, revision: reload)) {
                await loadCard(at: index)
            }
            .sheet(item: $editingCard, onDismiss: { reload += 1 }) { card in
                NoteEditorScreen(store: store, editingCardID: card.id) {
                    cardIDs.removeAll { card.siblingIDs.contains($0) }
                    if cardIDs.isEmpty {
                        preview = nil
                        dismiss()
                    } else {
                        move(to: min(index, cardIDs.count - 1))
                    }
                }
            }
            .alert(
                Text("Could Not Update Card", bundle: .module),
                isPresented: Binding(get: { actionFailure != nil }, set: { if !$0 { actionFailure = nil } })
            ) {
                Button(role: .cancel) { actionFailure = nil } label: { Text("OK", bundle: .module) }
            } message: {
                Text(actionFailure ?? "")
            }
        }
    }

    private var actions: some View {
        Menu {
            Button { perform(.edit) } label: {
                Label { Text("Edit Note", bundle: .module) } icon: { Image(systemName: "square.and.pencil") }
            }
            Button { perform(.mark) } label: {
                if marked {
                    Label { Text("Unmark Note", bundle: .module) } icon: { Image(systemName: "star.slash") }
                } else {
                    Label { Text("Mark Note", bundle: .module) } icon: { Image(systemName: "star") }
                }
            }
            Menu {
                ForEach([PreviewCommand.clearFlag] + PreviewCommand.coloredFlags, id: \.self) { command in
                    Button { perform(command) } label: {
                        Label(command.title, systemImage: flag == command.flag ? "checkmark" : "flag")
                    }
                }
            } label: {
                Label { Text("Flag", bundle: .module) } icon: { Image(systemName: "flag") }
            }
            Button { perform(.answerOnly) } label: {
                Label(PreviewCommand.answerOnly.title, systemImage: answerOnly ? "checkmark.square" : "square")
            }
            Button { perform(.replayMedia) } label: {
                Label(PreviewCommand.replayMedia.title, systemImage: "speaker.wave.2")
            }
        } label: {
            Label {
                Text("Preview Options", bundle: .module)
            } icon: { Image(systemName: "ellipsis.circle") }
        }
    }

    private func perform(_ command: PreviewCommand) {
        guard inputEnabled, cardIDs.indices.contains(index) else { return }
        switch command {
        case .previous:
            if index > 0 { move(to: index - 1) }
            else if !answerOnly { showsAnswer = false }
        case .next:
            if preview != nil && !showsAnswer && !answerOnly {
                showsAnswer = true
            } else if index + 1 < cardIDs.count {
                move(to: index + 1)
            }
        default:
            guard preview != nil else { return }
            let cardID = cardIDs[index]
            switch command {
            case .edit:
                guard let noteID else { return }
                mutate {
                    let siblings = try await store.core.cardsOfNote(.with { $0.nid = noteID })
                    guard store.allowsNewProfileWork else { return }
                    editingCard = EditingCard(id: cardID, siblingIDs: Set(siblings.cids))
                }
            case .answerOnly:
                answerOnly.toggle()
                showsAnswer = answerOnly
            case .replayMedia: replay = UUID()
            case .mark:
                mutate { marked = try await PreviewCardActions.toggleMark(cardID: cardID, in: store) }
            default:
                if let flag = command.flag {
                    mutate { self.flag = try await PreviewCardActions.toggleFlag(flag, cardID: cardID, in: store) }
                }
            }
        }
    }

    private func move(to index: Int) {
        preview = nil
        failure = nil
        showsAnswer = answerOnly
        self.index = index
    }

    private func mutate(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await operation()
            } catch {
                actionFailure = error.localizedDescription
            }
        }
    }

    private struct EditingCard: Identifiable {
        let id: Int64
        let siblingIDs: Set<Int64>
    }

    private struct LoadKey: Equatable {
        let index: Int
        let revision: Int
    }

    private func loadCard(at index: Int) async {
        guard cardIDs.indices.contains(index), store.allowsNewProfileWork else { return }
        failure = nil
        let id = cardIDs[index]
        let core = store.core
        do {
            let card = try await core.getCard(.with { $0.cid = id })
            let note = try await core.getNote(.with { $0.nid = card.noteID })
            let noteType = try await core.getNotetype(.with { $0.ntid = note.notetypeID })
            let rendered = try await core.renderExistingCard(.with { $0.cardID = id })
            let result = try await CardPreviewContent(rendered: rendered, ordinal: card.templateIdx, note: note, notetype: noteType, core: core)
            guard !Task.isCancelled, index == self.index, store.allowsNewProfileWork else { return }
            noteID = card.noteID
            marked = note.tags.contains(where: PreviewCardActions.isMarkTag)
            flag = card.flags & 7
            preview = result
        } catch {
            guard !Task.isCancelled, index == self.index, store.allowsNewProfileWork else { return }
            preview = nil
            failure = error.message
        }
    }
}
