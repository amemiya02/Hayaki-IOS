#if os(iOS)
import WebKit

/// Answers the card web view's `hayaki-card://` requests from
/// `CardResources`, passing each file on a piece at a time as it is read.
@MainActor
final class CardSchemeHandler: NSObject, WKURLSchemeHandler {
    private let resources: CardResources
    /// The requests being answered, until they finish or the web view stops
    /// them; nothing more may be sent for a stopped one.
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(resources: CardResources) {
        self.resources = resources
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let response = resources.response(to: url, range: urlSchemeTask.request.value(forHTTPHeaderField: "Range"))
        guard let http = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else {
            urlSchemeTask.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        urlSchemeTask.didReceive(http)
        let id = ObjectIdentifier(urlSchemeTask)
        running[id] = Task { [weak self] in
            do {
                for try await piece in response.body {
                    guard self?.running[id] != nil else { return }
                    urlSchemeTask.didReceive(piece)
                }
                guard self?.running.removeValue(forKey: id) != nil else { return }
                urlSchemeTask.didFinish()
            } catch {
                guard self?.running.removeValue(forKey: id) != nil else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        running.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
#endif
