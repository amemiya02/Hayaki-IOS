import SwiftUI

/// A card side for the card host page to show.
struct CardDisplay: Equatable, Encodable {
    let html: String
    let css: String
    let bodyClass: String
    let isAnswer: Bool
    /// Which card this is, so showing the same side of another card with
    /// identical HTML still counts as a change.
    let cardID: Int64

    init(_ card: StudyCard, isAnswer: Bool) {
        self.init(
            html: isAnswer ? card.answer.html : card.question.html,
            css: card.css, bodyClass: card.bodyClass, isAnswer: isAnswer, cardID: card.id
        )
    }

    init(html: String, css: String, bodyClass: String, isAnswer: Bool, cardID: Int64) {
        self.html = html
        self.css = css
        self.bodyClass = bodyClass
        self.isAnswer = isAnswer
        self.cardID = cardID
    }

    /// The page reads only these.
    private enum CodingKeys: String, CodingKey {
        case html, css, bodyClass, isAnswer
    }
}

#if os(iOS)
import OSLog
import WebKit

/// Draws a card in a web view, on Hayaki's own card host page
/// (`CardHost.html`); everything around the card is native (ADR 0004).
///
/// The page is loaded once and each side is handed to it, so turning a card
/// over or moving to the next one does not reload the page. The page, the
/// collection's media and the bundled MathJax come through the card URL
/// scheme (`CardResources`), never from the network.
struct CardWebView: UIViewRepresentable {
    let display: CardDisplay
    /// The collection's media folder, which the card's images, sounds and
    /// fonts come from.
    let mediaFolder: URL
    /// The page zoom that follows the learner's text size.
    let zoom: CGFloat
    /// Called for what the learner does on the card.
    var onTemplateRequest: ((TemplateRequest, Int64, Bool) async -> TemplateReply)? = nil
    let onEvent: (CardPageEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandler)
        configuration.userContentController.addScriptMessageHandler(
            context.coordinator, contentWorld: .page, name: Coordinator.templateHandler
        )
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
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        context.coordinator.loadHostPage()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.onTemplateRequest = onTemplateRequest
        if webView.pageZoom != zoom {
            webView.pageZoom = zoom
        }
        context.coordinator.show(display)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.templateHandler)
        coordinator.invalidateTemplate()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        static let messageHandler = "hayaki"
        static let templateHandler = "hayakiTemplate"

        weak var webView: WKWebView?
        var onEvent: (CardPageEvent) -> Void = { _ in }
        var onTemplateRequest: ((TemplateRequest, Int64, Bool) async -> TemplateReply)?
        private var templateToken: String?
        private var reloaded: CardDisplay?
        private var awaitingTemplateRequests = 0
        /// The side the page should show.
        private var wanted: CardDisplay?
        /// The side last handed to the page.
        private var shown: CardDisplay?
        private var pageLoaded = false

        func loadHostPage() {
            pageLoaded = false
            invalidateTemplate()
            shown = nil
            webView?.load(URLRequest(url: CardResources.hostPageURL))
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
            webView.evaluateJavaScript("hayaki.show(\(argument), '\(token)'); true") { _, error in
                if let error {
                    Self.log.error("The card host page could not show a card: \(error, privacy: .public)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            sendIfReady()
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
               url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
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
                let result = await onTemplateRequest(request, display.cardID, display.isAnswer)
                if pageToken == templateToken { awaitingTemplateRequests -= 1 }
                replyHandler(result.message, nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let event = CardPageEvent(message: message.body) {
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
