import SwiftUI

/// A draft card on the same card host used by the reviewer.
public struct CardPreviewView: View {
    let content: CardPreviewContent
    let showsAnswer: Bool
    let mediaFolder: URL
    let cardID: Int64?
    let controls: PreviewControls?
    let replay: UUID?
    let onCommand: ((PreviewCommand) -> Void)?
    let onReveal: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    let inlineImage: (name: String, dataURL: String)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @State private var audio = CardAudioPlayer()
    @State private var templateSpeech = TemplateSpeech()
    @State private var gesturePreferences: ReviewerPreferences?
    @State private var pendingTap: Task<Void, Never>?
    #endif

    public init(
        content: CardPreviewContent,
        showsAnswer: Bool,
        mediaFolder: URL,
        inlineImage: (name: String, dataURL: String)? = nil,
        onReveal: (() -> Void)? = nil
    ) {
        self.init(
            content: content, showsAnswer: showsAnswer, mediaFolder: mediaFolder,
            inlineImage: inlineImage, controls: nil, onReveal: onReveal
        )
    }

    public init(
        content: CardPreviewContent,
        showsAnswer: Bool,
        mediaFolder: URL,
        inlineImage: (name: String, dataURL: String)? = nil,
        cardID: Int64? = nil,
        controls: PreviewControls?,
        replay: UUID? = nil,
        onCommand: ((PreviewCommand) -> Void)? = nil,
        onReveal: (() -> Void)? = nil
    ) {
        self.content = content
        self.showsAnswer = showsAnswer
        self.mediaFolder = mediaFolder
        self.cardID = cardID
        self.controls = controls
        self.replay = replay
        self.onCommand = onCommand
        self.onReveal = onReveal
        self.inlineImage = inlineImage
    }

    public var body: some View {
        let side = showsAnswer ? content.answer : content.question
        #if os(iOS)
        CardWebView(
            display: CardDisplay(
                html: htmlForDisplay(side.html), css: content.css, bodyClass: "card card\(content.ordinal + 1)",
                isAnswer: showsAnswer, cardID: cardID ?? Int64(content.ordinal)
            ),
            mediaFolder: mediaFolder, zoom: dynamicTypeSize.cardZoom,
            reviewer: controls.map { ReviewerWebOptions(keySignatures: $0.keySignatures, command: nil) },
            onTemplateRequest: { request, context in
                if let response = templateSpeech.handle(request, prepareAudio: { audio.stop() }) {
                    return response
                }
                switch request.command {
                case "init": return .accepted
                case "isDisplayingAnswer": return .value(.boolean(context.isAnswer))
                case "isInNightMode": return .value(.boolean(colorScheme == .dark))
                case "showAnswer":
                    guard let onReveal else { return .unavailable }
                    onReveal()
                    return .accepted
                default: return .unavailable
                }
            }
        ) { event in
            if case .reviewer(let input) = event {
                handleWebInput(input)
            } else if case .play(let id) = event, let button = PlayButtons.parse(id) {
                let sounds = button.isQuestion ? content.question.audio : content.answer.audio
                if sounds.indices.contains(button.index) {
                    audio.play([CardSound(sounds[button.index], mediaFolder: mediaFolder)])
                }
            }
        }
        .focusable(controls != nil, interactions: .activate)
        .onKeyPress { send(.keyboard(ReviewerKey($0))) ? .handled : .ignored }
        .modifier(ReviewerController(enabled: controls?.usesController == true) { _ = send($0) })
        .modifier(ReviewerShake(enabled: controls?.command(for: .gesture(.shake)) != nil) {
            _ = send(.gesture(.shake))
        })
        .onChange(of: Presentation(cardID: cardID, answer: showsAnswer, side: side), initial: true) {
            pendingTap?.cancel()
            pendingTap = nil
            playSide()
        }
        .onChange(of: replay) { if replay != nil { playSide() } }
        .onDisappear {
            pendingTap?.cancel()
            pendingTap = nil
            audio.stop()
            templateSpeech.stop()
        }
        #else
        Text(verbatim: side.html)
        #endif
    }

    #if os(iOS)
    private struct Presentation: Equatable {
        let cardID: Int64?
        let answer: Bool
        let side: CardSide
    }

    @discardableResult
    private func send(_ input: ReviewerInput) -> Bool {
        guard let command = controls?.command(for: input), let onCommand else { return false }
        onCommand(command)
        return true
    }

    private func handleWebInput(_ event: ReviewerWebInput) {
        guard let controls else { return }
        switch event {
        case .input(let input):
            send(input)
        case .swipe(let dx, let dy, let time):
            let scale = 100 / Double(max(gestureSettings().swipeSensitivity, 1))
            let distance = hypot(dx, dy)
            guard distance >= 44 * scale, distance / max(1, time) >= 0.2 * scale else { return }
            let gesture: ReviewerGesture = abs(dx) > abs(dy)
                ? (dx < 0 ? .swipeLeft : .swipeRight)
                : (dy < 0 ? .swipeUp : .swipeDown)
            send(.gesture(gesture))
        case .tap(let x, let y):
            let settings = gestureSettings()
            let zone = ReviewerInput.gesture(settings.tapZones.gesture(x: x, y: y))
            let interval = settings.doubleTapMilliseconds
            guard interval > 0, controls.command(for: .gesture(.doubleTap)) != nil else {
                send(zone)
                return
            }
            if let pendingTap {
                pendingTap.cancel()
                self.pendingTap = nil
                send(.gesture(.doubleTap))
            } else {
                pendingTap = Task {
                    try? await Task.sleep(for: .milliseconds(interval))
                    guard !Task.isCancelled else { return }
                    pendingTap = nil
                    send(zone)
                }
            }
        }
    }

    private func gestureSettings() -> ReviewerPreferences {
        if let gesturePreferences { return gesturePreferences }
        let settings = ReviewerPreferences.load()
        gesturePreferences = settings
        return settings
    }

    private func playSide() {
        templateSpeech.stop()
        let side = showsAnswer ? content.answer : content.question
        audio.play(side.audio.map { CardSound($0, mediaFolder: mediaFolder) })
    }
    #endif

    private func htmlForDisplay(_ html: String) -> String {
        guard let inlineImage else { return html }
        return html.replacingOccurrences(of: "src=\"\(inlineImage.name)\"", with: "src=\"\(inlineImage.dataURL)\"")
    }
}
