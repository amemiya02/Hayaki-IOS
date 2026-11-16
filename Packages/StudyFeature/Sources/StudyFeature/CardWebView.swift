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
        html = isAnswer ? card.answer.html : card.question.html
        css = card.css
        bodyClass = card.bodyClass
        self.isAnswer = isAnswer
        cardID = card.id
    }

    /// The page reads only these.
    private enum CodingKeys: String, CodingKey {
        case html, css, bodyClass, isAnswer
    }
}

#if os(iOS)
import WebKit

/// Draws a card in a web view, on Hayaki's own card host page
/// (`CardHost.html`); everything around the card is native (ADR 0004).
///
/// The page is loaded once and each side is handed to it, so turning a card
/// over or moving to the next one does not reload the page.
struct CardWebView: UIViewRepresentable {
    let display: CardDisplay
    /// The page zoom that follows the learner's text size.
    let zoom: CGFloat
    /// Called when the learner taps the card anywhere but on a link or
    /// control.
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageHandler)
        configuration.dataDetectorTypes = []
        configuration.allowsInlineMediaPlayback = true
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
        context.coordinator.onTap = onTap
        if webView.pageZoom != zoom {
            webView.pageZoom = zoom
        }
        context.coordinator.show(display)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandler)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandler = "hayaki"

        weak var webView: WKWebView?
        var onTap: () -> Void = {}
        /// The side the page should show.
        private var wanted: CardDisplay?
        /// The side last handed to the page.
        private var shown: CardDisplay?
        private var pageLoaded = false

        func loadHostPage() {
            pageLoaded = false
            shown = nil
            webView?.loadHTMLString(Self.hostPage, baseURL: nil)
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
            webView.evaluateJavaScript("hayaki.show(\(argument))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            sendIfReady()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loadHostPage()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            // The host page is the only page; a link on a card opens in the
            // learner's browser instead of replacing it.
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.body as? String == "tap" {
                onTap()
            }
        }

        private static let hostPage: String = {
            guard let url = Bundle.module.url(forResource: "CardHost", withExtension: "html"),
                  let page = try? String(contentsOf: url, encoding: .utf8)
            else {
                fatalError("CardHost.html is missing from StudyFeature's resources")
            }
            return page
        }()
    }
}
#endif
