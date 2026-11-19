import StudyFeature
import SwiftUI

struct NotePreviewScreen: View {
    let cards: [DraftCard]
    let mediaFolder: URL
    let inlineImage: (name: String, dataURL: String)?
    @State private var ordinal: UInt32
    @State private var showsAnswer = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        cards: [DraftCard], initialOrdinal: UInt32, mediaFolder: URL, inlineImage: (name: String, dataURL: String)? = nil
    ) {
        self.cards = cards
        self.mediaFolder = mediaFolder
        self.inlineImage = inlineImage
        _ordinal = State(initialValue: cards.first { $0.id == initialOrdinal }?.id ?? cards.first?.id ?? 0)
    }

    var body: some View {
        Group {
            if let card = cards.first(where: { $0.id == ordinal }) {
                VStack(spacing: 0) {
                    templates
                    Divider()
                    CardPreviewView(
                        content: card.content, showsAnswer: showsAnswer, mediaFolder: mediaFolder, inlineImage: inlineImage
                    ) {
                        showsAnswer = true
                    }
                        .frame(maxWidth: horizontalSizeClass == .regular ? 820 : .infinity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("note-preview-card")
                    Divider()
                    Button {
                        showsAnswer.toggle()
                    } label: {
                        if showsAnswer {
                            Text("Show Question", bundle: .module)
                        } else {
                            Text("Show Answer", bundle: .module)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                    .accessibilityIdentifier("flip-note-preview")
                }
            } else {
                ContentUnavailableView {
                    Label { Text("No Cards to Preview", bundle: .module) } icon: { Image(systemName: "rectangle.on.rectangle") }
                }
            }
        }
        .navigationTitle(Text("Preview", bundle: .module))
    }

    private var templates: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(cards) { card in
                    Button {
                        ordinal = card.id
                        showsAnswer = false
                    } label: {
                        Text(card.name)
                    }
                    .buttonStyle(.bordered)
                    .tint(card.id == ordinal ? .accentColor : .secondary)
                    .accessibilityAddTraits(card.id == ordinal ? [.isSelected] : [])
                }
            }
            .padding(8)
        }
    }
}
