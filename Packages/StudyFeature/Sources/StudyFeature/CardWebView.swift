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
    var reviewer: ReviewerWebOptions? = nil
    /// Called for what the learner does on the card.
    let onEvent: (CardPageEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandler)
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
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        context.coordinator.loadHostPage()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        if webView.pageZoom != zoom {
            webView.pageZoom = zoom
        }
        context.coordinator.updateReviewer(reviewer)
        context.coordinator.show(display)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandler)
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.inputHandler, contentWorld: .defaultClient
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandler = "hayaki"
        static let inputHandler = "hayakiReviewerInput"
        private var reviewer: ReviewerWebOptions?
        private var command: ReviewerWebCommand?

        weak var webView: WKWebView?
        var onEvent: (CardPageEvent) -> Void = { _ in }
        /// The side the page should show.
        private var wanted: CardDisplay?
        /// The side last handed to the page.
        private var shown: CardDisplay?
        private var pageLoaded = false

        func loadHostPage() {
            pageLoaded = false
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
                "window.hayakiReviewerKeys = keys; document.body.style.setProperty('--reviewer-image-zoom', imageZoom); document.body.classList.toggle('reviewer-centered', centered);",
                arguments: ["keys": reviewer.keySignatures, "imageZoom": reviewer.imageZoom, "centered": reviewer.centerVertically],
                in: nil, in: .defaultClient, completionHandler: nil
            )
            if let requested = reviewer.command, command != requested {
                command = requested
                webView.evaluateJavaScript(requested.javascript)
            }
        }

        func show(_ display: CardDisplay) {
            wanted = display
            sendIfReady()
        }

        private func sendIfReady() {
            guard pageLoaded, let wanted, wanted != shown, let webView else { return }
            guard let json = try? JSONEncoder().encode(wanted), let argument = String(data: json, encoding: .utf8) else {
                return
            }
            shown = wanted
            webView.evaluateJavaScript("hayaki.show(\(argument)); true") { _, error in
                if let error {
                    Self.log.error("The card host page could not show a card: \(error, privacy: .public)")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
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
            // The host page is the only page; a link on a card opens in the
            // learner's browser instead of replacing it.
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                // A link to a place on the card itself (#…) just scrolls.
                if url.scheme == CardResources.scheme, url.fragment != nil,
                   url.path(percentEncoded: false).isEmpty || url.path(percentEncoded: false) == "/" {
                    decisionHandler(.allow)
                    return
                }
                if url.scheme == "http" || url.scheme == "https" {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
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
    let command: ReviewerWebCommand?
}

/// A native reviewer button may scroll or request an existing template hook.
struct ReviewerWebCommand: Equatable {
    var id = UUID()
    let javascript: String
}
