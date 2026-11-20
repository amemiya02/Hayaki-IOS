import CollectionTesting
import Foundation
@testable import StudyFeature
import Testing
import WebKit

@MainActor
@Suite("Drawing card text", .timeLimit(.minutes(1)))
struct CardTypographyTests {
    @Test("An answer does not paint in the fallback font while its local font loads")
    func answerWaitsForItsFont() async throws {
        let folder = try TemporaryFolder()
        let resources = CardResources(mediaFolder: folder.url)
        let fontURL = try #require(URL(string: "hayaki-card://card/_hayaki/mathjax/output/chtml/fonts/woff-v2/MathJax_Main-Regular.woff"))
        var font = Data()
        for try await chunk in resources.response(to: fontURL, range: nil).body {
            font.append(chunk)
        }
        try font.write(to: folder.url.appendingPathComponent("answer-font.woff"))
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(DelayedAnswerFont(resources: resources), forURLScheme: CardResources.scheme)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        webView.load(URLRequest(url: CardResources.hostPageURL))
        let clock = ContinuousClock()
        let readyDeadline = clock.now.advanced(by: .seconds(5))
        while (try? await webView.evaluateJavaScript("typeof window.hayaki?.show") as? String) != "function" {
            guard clock.now < readyDeadline else {
                Issue.record("The card host did not load")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        let result = try await webView.callAsyncJavaScript("""
            const css = '@font-face { font-family: AnswerFont; src: url("answer-font.woff"); font-display: swap; }'
                + ' .answer { font: 36px AnswerFont, monospace; }';
            const side = { css, bodyClass: "card" };
            const qa = document.getElementById("qa");
            window.hayaki.show({ ...side, html: "Question", isAnswer: false }, "front", false);
            await new Promise(resolve => setTimeout(resolve, 20));
            window.hayaki.show({
                ...side, html: 'Question<hr id="answer"><span class="answer">Welcome</span>', isAnswer: true,
            }, "back", false);
            let sawVisibleFallback = false;
            const deadline = performance.now() + 2000;
            while (performance.now() < deadline) {
                const answer = qa.querySelector(".answer");
                if (answer) {
                    answer.getBoundingClientRect();
                    const font = Array.from(document.fonts).find(face => face.family === "AnswerFont");
                    if (getComputedStyle(qa).opacity === "1") {
                        if (font?.status === "loaded") return { sawVisibleFallback, loaded: true };
                        sawVisibleFallback = true;
                    }
                }
                await new Promise(resolve => setTimeout(resolve, 10));
            }
            return { sawVisibleFallback, loaded: false };
            """, arguments: [:], in: nil, contentWorld: .page)
        let observation = try #require(result as? [String: Bool])
        #expect(observation["loaded"] == true)
        #expect(observation["sawVisibleFallback"] == false)
    }
}

@MainActor
private final class DelayedAnswerFont: NSObject, WKURLSchemeHandler {
    private let handler: CardSchemeHandler
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(resources: CardResources) {
        handler = CardSchemeHandler(resources: resources)
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard task.request.url?.lastPathComponent == "answer-font.woff" else {
            handler.webView(webView, start: task)
            return
        }
        let id = ObjectIdentifier(task)
        pending[id] = Task {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            pending[id] = nil
            handler.webView(webView, start: task)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        if let delayed = pending.removeValue(forKey: ObjectIdentifier(task)) {
            delayed.cancel()
        } else {
            handler.webView(webView, stop: task)
        }
    }
}
