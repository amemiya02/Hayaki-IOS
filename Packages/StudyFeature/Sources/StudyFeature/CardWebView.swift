import HayakiAppearance
import SwiftUI

public enum StudyDisplayPreferences {
    public static let focusTypedAnswerKey = "hayaki.reviewer.focusTypedAnswer"
    public static let inspectCardContentKey = "hayaki.developer.inspectCardContent"
}

/// A card side for the card host page to show.
struct CardDisplay: Equatable, Encodable {
    let html: String
    let css: String
    let bodyClass: String
    let isAnswer: Bool
    /// Which card this is, so showing the same side of another card with
    /// identical HTML still counts as a change.
    let cardID: Int64
    let presentation: Int

    init(_ card: StudyCard, isAnswer: Bool, presentation: Int = 0) {
        self.init(
            html: isAnswer ? card.answer.html : card.question.html,
            css: card.css, bodyClass: card.bodyClass, isAnswer: isAnswer, cardID: card.id, presentation: presentation
        )
    }

    init(html: String, css: String, bodyClass: String, isAnswer: Bool, cardID: Int64, presentation: Int = 0) {
        self.html = html
        self.css = css
        self.bodyClass = bodyClass
        self.isAnswer = isAnswer
        self.cardID = cardID
        self.presentation = presentation
    }

    /// The page reads only these.
    private enum CodingKeys: String, CodingKey {
        case html, css, bodyClass, isAnswer
    }
}

#if os(iOS)
import OSLog
import WebKit

@MainActor
struct CardTemplateContext {
    let cardID: Int64
    let isAnswer: Bool
    let isCurrent: () -> Bool
    let emit: (String, TemplateReply) -> Void
}

/// Draws a card in a web view, on Hayaki's own card host page
/// (`CardHost.html`); everything around the card is native (ADR 0004).
///
/// The page is loaded once and each side is handed to it, so turning a card
/// over or moving to the next one does not reload the page. The page, the
/// collection's media and the bundled MathJax come through the card URL
/// scheme (`CardResources`), never from the network.
struct CardWebView: UIViewRepresentable {
    @Environment(\.hayakiTheme) private var theme
    @AppStorage(StudyDisplayPreferences.focusTypedAnswerKey) private var focusTypedAnswer = true
    #if DEBUG
    @AppStorage(StudyDisplayPreferences.inspectCardContentKey) private var inspectCardContent = false
    #endif
    let display: CardDisplay
    /// The collection's media folder, which the card's images, sounds and
    /// fonts come from.
    let mediaFolder: URL
    /// The page zoom that follows the learner's text size.
    let zoom: CGFloat
    var reviewer: ReviewerWebOptions? = nil
    /// Called for what the learner does on the card.
    var onTemplateRequest: ((TemplateRequest, CardTemplateContext) async -> TemplateReply)? = nil
    let onEvent: (CardPageEvent) -> Void
    @AppStorage(CardTemplatePreference.externalApps) private var allowsExternalApps = false

    init(
        display: CardDisplay, mediaFolder: URL, zoom: CGFloat, reviewer: ReviewerWebOptions? = nil,
        onTemplateRequest: ((TemplateRequest, CardTemplateContext) async -> TemplateReply)? = nil,
        onEvent: @escaping (CardPageEvent) -> Void
    ) {
        self.display = display
        self.mediaFolder = mediaFolder
        self.zoom = zoom
        self.reviewer = reviewer
        self.onTemplateRequest = onTemplateRequest
        self.onEvent = onEvent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandler)
        configuration.userContentController.addScriptMessageHandler(
            context.coordinator, contentWorld: .page, name: Coordinator.templateHandler
        )
        if reviewer != nil,
           let url = Bundle.module.url(forResource: "ReviewerInput", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            configuration.userContentController.add(
                context.coordinator, contentWorld: .defaultClient, name: Coordinator.inputHandler
            )
            configuration.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
            )
        }
        configuration.setURLSchemeHandler(
            CardSchemeHandler(resources: CardResources(mediaFolder: mediaFolder)),
            forURLScheme: CardResources.scheme
        )
        configuration.dataDetectorTypes = []
        configuration.allowsInlineMediaPlayback = true
        // Audio and video a card's own HTML starts may play, as on desktop.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Before the page has drawn, and wherever the card sets no
        // background, the screen's own background shows.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        #if DEBUG
        webView.isInspectable = inspectCardContent
        #endif
        context.coordinator.webView = webView
        context.coordinator.updateAppearance(theme)
        context.coordinator.loadHostPage()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.updateAppearance(theme)
        context.coordinator.onTemplateRequest = onTemplateRequest
        context.coordinator.allowsExternalApps = allowsExternalApps
        if webView.pageZoom != zoom {
            webView.pageZoom = zoom
        }
        #if DEBUG
        webView.isInspectable = inspectCardContent
        #endif
        context.coordinator.focusTypedAnswer = focusTypedAnswer
        context.coordinator.updateReviewer(reviewer)
        context.coordinator.show(display)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.templateHandler)
        coordinator.invalidateTemplate()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.inputHandler, contentWorld: .defaultClient
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        static let messageHandler = "hayaki"
        static let templateHandler = "hayakiTemplate"
        static let inputHandler = "hayakiReviewerInput"
        private var reviewer: ReviewerWebOptions?
        private var command: ReviewerWebCommand?

        weak var webView: WKWebView?
        var focusTypedAnswer = true
        var onEvent: (CardPageEvent) -> Void = { _ in }
        var onTemplateRequest: ((TemplateRequest, CardTemplateContext) async -> TemplateReply)?
        var allowsExternalApps = false
        private var templateToken: String?
        private var reloaded: CardDisplay?
        private var awaitingTemplateRequests = 0
        /// The side the page should show.
        private var wanted: CardDisplay?
        /// The side last handed to the page.
        private var shown: CardDisplay?
        private var pageLoaded = false
        private var theme: HayakiTheme?

        func loadHostPage() {
            pageLoaded = false
            invalidateTemplate()
            shown = nil
            webView?.load(URLRequest(url: CardResources.hostPageURL))
        }

        func updateReviewer(_ options: ReviewerWebOptions?) {
            guard reviewer != options else { return }
            reviewer = options
            sendReviewerOptions()
        }

        private func sendReviewerOptions() {
            guard pageLoaded, let reviewer, let webView else { return }
            webView.callAsyncJavaScript(
                "window.hayakiReviewerKeys = keys; document.body.style.setProperty('--reviewer-image-zoom', imageZoom); document.body.classList.toggle('reviewer-centered', centered); document.body.classList.toggle('reviewer-hide-audio', hideAudio); document.body.classList.toggle('reviewer-reduced-motion', reducedMotion);",
                arguments: [
                    "keys": reviewer.keySignatures, "imageZoom": reviewer.imageZoom, "centered": reviewer.centerVertically,
                    "hideAudio": reviewer.hidesAudioButtons, "reducedMotion": reviewer.reducedMotion,
                ],
                in: nil, in: .defaultClient, completionHandler: nil
            )
            if let requested = reviewer.command, command != requested {
                command = requested
                webView.evaluateJavaScript(requested.javascript)
            }
        }

        func updateAppearance(_ theme: HayakiTheme) {
            guard self.theme != theme else { return }
            self.theme = theme
            webView?.overrideUserInterfaceStyle = theme == .light ? .light : .dark
            sendAppearance()
        }

        private func sendAppearance() {
            guard pageLoaded, let theme, let webView else { return }
            let canvas = String(format: "#%06X", theme.backgroundRGB)
            // The template's own styling can supply --canvas or style .nightMode.
            webView.callAsyncJavaScript(
                "document.documentElement.style.setProperty('--hayaki-night-canvas', canvas)",
                arguments: ["canvas": canvas], in: nil, in: .page, completionHandler: nil
            )
        }

        func show(_ display: CardDisplay) {
            if wanted != display { reloaded = nil }
            wanted = display
            sendIfReady()
        }

        private func sendIfReady() {
            guard pageLoaded, let wanted, wanted != shown, let webView else { return }
            guard let json = try? JSONEncoder().encode(wanted), let argument = String(data: json, encoding: .utf8) else {
                return
            }
            let token = UUID().uuidString
            templateToken = token
            awaitingTemplateRequests = 0
            shown = wanted
            webView.evaluateJavaScript("hayaki.show(\(argument), '\(token)', \(focusTypedAnswer)); true") { _, error in
                if let error {
                    Self.log.error("The card host page could not show a card: \(error, privacy: .public)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            sendAppearance()
            sendIfReady()
            sendReviewerOptions()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            Self.log.error("The card host page did not load: \(error, privacy: .public)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Self.log.error("The card web view's content process ended; reloading")
            loadHostPage()
        }

        private static let log = Logger(subsystem: "io.github.amemiya02.hayaki", category: "CardWebView")

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if Self.isHost(url) {
                decisionHandler(.allow)
                return
            }
            // A card can link to a site, but the site opens in the user's browser.
            if navigationAction.navigationType == .linkActivated,
               navigationAction.sourceFrame.isMainFrame, let scheme = url.scheme?.lowercased() {
                let isWeb = scheme == "http" || scheme == "https"
                let isLocal = ["file", "data", "blob", "about", "javascript", CardResources.scheme].contains(scheme)
                if isWeb || (allowsExternalApps && !isLocal) {
                    UIApplication.shared.open(url)
                }
            }
            decisionHandler(.cancel)
        }

        private static func isHost(_ url: URL) -> Bool {
            url.scheme == CardResources.scheme && url.host == CardResources.hostPageURL.host &&
                (url.path.isEmpty || url.path == "/") && url.query == nil
        }

        func invalidateTemplate() {
            templateToken = nil
            awaitingTemplateRequests = 0
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage,
            replyHandler: @escaping @MainActor (Any?, String?) -> Void
        ) {
            guard message.name == Self.templateHandler, message.frameInfo.isMainFrame,
                  let url = message.frameInfo.request.url, Self.isHost(url),
                  let pageToken = templateToken,
                  let body = message.body as? [String: Any], body["token"] as? String == pageToken,
                  let display = shown, let request = TemplateRequest(message: body)
            else {
                replyHandler(TemplateReply.unavailable.message, nil)
                return
            }
            guard request.isValid else {
                replyHandler(TemplateReply.invalid.message, nil)
                return
            }
            if request.command == "reloadPage" {
                guard reloaded != display else {
                    replyHandler(TemplateReply.unavailable.message, nil)
                    return
                }
                reloaded = display
                replyHandler(TemplateReply.accepted.message, nil)
                shown = nil
                sendIfReady()
                return
            }
            if request.command == "enableHorizontalScrollbar" || request.command == "enableVerticalScrollbar" {
                guard let scrollView = webView?.scrollView else {
                    replyHandler(TemplateReply.unavailable.message, nil)
                    return
                }
                let visible = request.data?.caseInsensitiveCompare("true") == .orderedSame
                if request.command == "enableHorizontalScrollbar" {
                    scrollView.showsHorizontalScrollIndicator = visible
                } else {
                    scrollView.showsVerticalScrollIndicator = visible
                }
                replyHandler(TemplateReply.accepted.message, nil)
                return
            }
            guard awaitingTemplateRequests < 16, let onTemplateRequest else {
                replyHandler(TemplateReply.unavailable.message, nil)
                return
            }
            awaitingTemplateRequests += 1
            Task {
                guard pageToken == templateToken else {
                    replyHandler(TemplateReply.unavailable.message, nil)
                    return
                }
                let context = CardTemplateContext(
                    cardID: display.cardID, isAnswer: display.isAnswer,
                    isCurrent: { [weak self] in self?.templateToken == pageToken },
                    emit: { [weak self] name, result in
                        guard let self, templateToken == pageToken else { return }
                        webView?.callAsyncJavaScript(
                            "hayakiTemplate.emit(token, name, result)",
                            arguments: ["token": pageToken, "name": name, "result": result.message],
                            in: nil, in: .page, completionHandler: nil
                        )
                    }
                )
                let result = await onTemplateRequest(request, context)
                if pageToken == templateToken { awaitingTemplateRequests -= 1 }
                replyHandler(result.message, nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame else { return }
            if message.name == Self.inputHandler {
                if let input = ReviewerWebInput(message.body) { onEvent(.reviewer(input)) }
            } else if let event = CardPageEvent(message: message.body) {
                onEvent(event)
            }
        }
    }
}
#endif

/// What the learner does on the card host page.
enum CardPageEvent: Equatable {
    /// A tap on the card, not on a link or control.
    case tap
    case reviewer(ReviewerWebInput)
    /// A tap on a replay button, by its id such as `q:0`.
    case play(String)
    /// The text in a typed-answer field, after it changed.
    case typed(String)
    /// Return pressed in a typed-answer field.
    case submitTypedAnswer

    /// The event a message the page posted stands for.
    init?(message: Any) {
        if message as? String == "tap" {
            self = .tap
        } else if let message = message as? [String: Any] {
            if let id = message["play"] as? String {
                self = .play(id)
            } else if let text = message["typed"] as? String {
                self = .typed(text)
            } else if message["submit"] != nil {
                self = .submitTypedAnswer
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}

/// Physical input crosses the web boundary from an isolated WebKit content world.
enum ReviewerWebInput: Equatable {
    case tap(Double, Double)
    case swipe(Double, Double, Double)
    case input(ReviewerInput)

    init?(_ body: Any) {
        guard let values = body as? [String: Any] else { return nil }
        if let x = values["tapX"] as? Double, let y = values["tapY"] as? Double, x.isFinite, y.isFinite {
            self = .tap(x, y)
        } else if let dx = values["dx"] as? Double, let dy = values["dy"] as? Double,
                  let time = values["time"] as? Double {
            self = .swipe(dx, dy, time)
        } else if let key = values["key"] as? String, let modifiers = values["modifiers"] as? [String] {
            self = .input(.key(key, modifiers: Set(modifiers.compactMap(ReviewerKey.Modifier.init(rawValue:)))))
        } else if let count = values["fingers"] as? Int, (2...4).contains(count) {
            self = .input(.gesture([.twoFingerTap, .threeFingerTap, .fourFingerTap][count - 2]))
        } else {
            return nil
        }
    }
}

struct ReviewerWebOptions: Equatable {
    let keySignatures: [String]
    var imageZoom = 1.0
    var centerVertically = false
    var hidesAudioButtons = false
    var reducedMotion = false
    let command: ReviewerWebCommand?
}

/// A native reviewer button may scroll or request an existing template hook.
struct ReviewerWebCommand: Equatable {
    var id = UUID()
    let javascript: String
}
