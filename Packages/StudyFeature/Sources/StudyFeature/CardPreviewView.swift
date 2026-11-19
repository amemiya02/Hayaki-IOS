import SwiftUI

/// A draft card on the same card host used by the reviewer.
public struct CardPreviewView: View {
    let content: CardPreviewContent
    let showsAnswer: Bool
    let mediaFolder: URL
    let inlineImage: (name: String, dataURL: String)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @State private var audio = CardAudioPlayer()
    #endif

    public init(
        content: CardPreviewContent,
        showsAnswer: Bool,
        mediaFolder: URL,
        inlineImage: (name: String, dataURL: String)? = nil
    ) {
        self.content = content
        self.showsAnswer = showsAnswer
        self.mediaFolder = mediaFolder
        self.inlineImage = inlineImage
    }

    public var body: some View {
        let side = showsAnswer ? content.answer : content.question
        #if os(iOS)
        CardWebView(
            display: CardDisplay(
                html: htmlForDisplay(side.html), css: content.css, bodyClass: "card card\(content.ordinal + 1)",
                isAnswer: showsAnswer, cardID: Int64(content.ordinal)
            ),
            mediaFolder: mediaFolder, zoom: dynamicTypeSize.cardZoom
        ) { event in
            if case .play(let id) = event, let button = PlayButtons.parse(id) {
                let sounds = button.isQuestion ? content.question.audio : content.answer.audio
                if sounds.indices.contains(button.index) {
                    audio.play([CardSound(sounds[button.index], mediaFolder: mediaFolder)])
                }
            }
        }
        .onChange(of: side, initial: true) {
            audio.play(side.audio.map { CardSound($0, mediaFolder: mediaFolder) })
        }
        .onDisappear { audio.stop() }
        #else
        Text(verbatim: side.html)
        #endif
    }

    private func htmlForDisplay(_ html: String) -> String {
        guard let inlineImage else { return html }
        return html.replacingOccurrences(of: "src=\"\(inlineImage.name)\"", with: "src=\"\(inlineImage.dataURL)\"")
    }
}
