import AnkiCore
import CollectionStore
import StudyFeature
import SwiftUI

struct BrowserPreviewScreen: View {
    let store: CollectionStore
    let cardIDs: [Int64]
    @State private var index = 0
    @State private var preview: CardPreviewContent?
    @State private var showsAnswer = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let preview {
                    CardPreviewView(content: preview, showsAnswer: showsAnswer, mediaFolder: store.location.mediaFolder)
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
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { index -= 1 } label: {
                        Label {
                            Text("Previous Card", bundle: .module)
                        } icon: { Image(systemName: "chevron.left") }
                        .labelStyle(.iconOnly)
                    }
                    .disabled(index == 0)
                    Spacer()
                    Button {
                        showsAnswer.toggle()
                    } label: {
                        showsAnswer ? Text("Show Question", bundle: .module) : Text("Show Answer", bundle: .module)
                    }
                    .disabled(preview == nil)
                    Spacer()
                    Button { index += 1 } label: {
                        Label {
                            Text("Next Card", bundle: .module)
                        } icon: { Image(systemName: "chevron.right") }
                        .labelStyle(.iconOnly)
                    }
                    .disabled(index + 1 >= cardIDs.count)
                }
                .buttonStyle(.bordered)
                .padding()
                .background(.bar)
            }
            .task(id: index) {
                await loadCard(at: index)
            }
        }
    }

    private func loadCard(at index: Int) async {
        preview = nil
        failure = nil
        showsAnswer = false
        let id = cardIDs[index]
        let core = store.core
        do {
            let card = try await core.getCard(.with { $0.cid = id })
            let note = try await core.getNote(.with { $0.nid = card.noteID })
            let noteType = try await core.getNotetype(.with { $0.ntid = note.notetypeID })
            let rendered = try await core.renderExistingCard(.with { $0.cardID = id })
            let result = try await CardPreviewContent(rendered: rendered, ordinal: card.templateIdx, note: note, notetype: noteType, core: core)
            guard !Task.isCancelled else { return }
            preview = result
        } catch {
            if !Task.isCancelled { failure = error.message }
        }
    }
}
