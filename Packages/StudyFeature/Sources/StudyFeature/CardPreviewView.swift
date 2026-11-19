import SwiftUI

/// A draft card on the same card host used by the reviewer.
public struct CardPreviewView: View {
    let content: CardPreviewContent
    let showsAnswer: Bool
    let mediaFolder: URL
    let onReveal: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @State private var audio = CardAudioPlayer()
    @State private var templateSpeech = TemplateSpeech()
    #endif

    public init(
        content: CardPreviewContent, showsAnswer: Bool, mediaFolder: URL, onReveal: (() -> Void)? = nil
    ) {
        self.content = content
        self.showsAnswer = showsAnswer
        self.mediaFolder = mediaFolder
        self.onReveal = onReveal
    }

    public var body: some View {
        let side = showsAnswer ? content.answer : content.question
        #if os(iOS)
        CardWebView(
            display: CardDisplay(
                html: side.html, css: content.css, bodyClass: "card card\(content.ordinal + 1)",
                isAnswer: showsAnswer, cardID: Int64(content.ordinal)
            ),
            mediaFolder: mediaFolder, zoom: dynamicTypeSize.cardZoom,
            onTemplateRequest: { request, _, isAnswer in
                if let response = templateSpeech.handle(request, prepareAudio: { audio.stop() }) {
                    return response
                }
                switch request.command {
                case "init": return .accepted
                case "isDisplayingAnswer": return .value(.boolean(isAnswer))
                case "isInNightMode": return .value(.boolean(colorScheme == .dark))
                case "showAnswer":
                    guard let onReveal else { return .unavailable }
                    onReveal()
                    return .accepted
                default: return .unavailable
                }
            }
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
        .onDisappear {
            audio.stop()
            templateSpeech.stop()
        }
        #else
        Text(verbatim: side.html)
        #endif
    }
}
