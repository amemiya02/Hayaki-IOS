import CollectionStore
import CollectionTesting
import Foundation
@testable import StudyFeature
import Testing

/// What the card web view is served through the card URL scheme: the host
/// page, the bundled MathJax and the collection's media files, streamed in
/// pieces and honouring range requests.
@Suite("Serving cards their page, media and MathJax", .timeLimit(.minutes(1)))
struct CardResourceTests {
    private static let size = 3 * 1024 * 1024 + 123

    /// A media folder inside `folder`, holding a large "video" with known
    /// bytes and a small image.
    private func makeMedia(in folder: URL) throws -> (folder: URL, video: Data) {
        let media = folder.appendingPathComponent("collection.media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let bytes = Data((0..<Self.size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 / 4096) })
        try bytes.write(to: media.appendingPathComponent("clip.mp4"))
        try Data("sun".utf8).write(to: media.appendingPathComponent("sol de día.png"))
        return (media, bytes)
    }

    private func url(_ path: String) -> URL {
        URL(string: "\(CardResources.scheme)://card/\(path)")!
    }

    private func body(of response: CardResources.Response) async throws -> (data: Data, pieces: [Int]) {
        var data = Data()
        var pieces: [Int] = []
        for try await piece in response.body {
            data.append(piece)
            pieces.append(piece.count)
        }
        return (data, pieces)
    }

    @Test("A large media file is served whole, in pieces no larger than the chunk size")
    func wholeFileInPieces() async throws {
        let folder = try TemporaryFolder()
        let (media, bytes) = try makeMedia(in: folder.url)
        let resources = CardResources(mediaFolder: media)

        let response = resources.response(to: url("clip.mp4"), range: nil)

        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Length"] == "\(Self.size)")
        #expect(response.headers["Accept-Ranges"] == "bytes")
        #expect(response.headers["Content-Type"] == "video/mp4")
        let (data, pieces) = try await body(of: response)
        #expect(data == bytes)
        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0 <= CardResources.chunkSize })
    }

    @Test("A range request gets just those bytes, as a partial response", arguments: [
        ("bytes=100-199", 100, 199),
        ("bytes=0-0", 0, 0),
        ("bytes=3000000-", 3_000_000, size - 1),
        ("bytes=-500", size - 500, size - 1),
        ("bytes=3145000-9999999", 3_145_000, size - 1),
    ])
    func rangeRequest(header: String, first: Int, last: Int) async throws {
        let folder = try TemporaryFolder()
        let (media, bytes) = try makeMedia(in: folder.url)
        let resources = CardResources(mediaFolder: media)

        let response = resources.response(to: url("clip.mp4"), range: header)

        #expect(response.statusCode == 206)
        #expect(response.headers["Content-Range"] == "bytes \(first)-\(last)/\(Self.size)")
        #expect(response.headers["Content-Length"] == "\(last - first + 1)")
        let (data, pieces) = try await body(of: response)
        #expect(data == bytes[first...last])
        #expect(pieces.allSatisfy { $0 <= CardResources.chunkSize })
    }

    @Test("A range beyond the end of the file is refused")
    func unsatisfiableRange() async throws {
        let folder = try TemporaryFolder()
        let (media, _) = try makeMedia(in: folder.url)
        let resources = CardResources(mediaFolder: media)

        let response = resources.response(to: url("clip.mp4"), range: "bytes=\(Self.size)-")

        #expect(response.statusCode == 416)
        #expect(response.headers["Content-Range"] == "bytes */\(Self.size)")
    }

    @Test("A file name with spaces and accents is found from its percent-encoded URL")
    func encodedName() async throws {
        let folder = try TemporaryFolder()
        let (media, _) = try makeMedia(in: folder.url)
        let resources = CardResources(mediaFolder: media)

        let response = resources.response(to: url("sol%20de%20d%C3%ADa.png"), range: nil)

        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "image/png")
        #expect(try await body(of: response).data == Data("sun".utf8))
    }

    @Test("Nothing outside the media folder and the bundled assets can be reached", arguments: [
        "missing.png", "..%2Fsecret.txt", "%2E%2E/secret.txt", "_hayaki/..%2F..%2Fsecret.txt", "_hayaki/nothing.js",
        "sub%2Fclip.mp4",
    ])
    func outsideIsNotFound(path: String) async throws {
        let folder = try TemporaryFolder()
        let (media, _) = try makeMedia(in: folder.url)
        try Data("secret".utf8).write(to: folder.url.appendingPathComponent("secret.txt"))
        let resources = CardResources(mediaFolder: media)

        let response = resources.response(to: url(path), range: nil)

        #expect(response.statusCode == 404)
        #expect(try await body(of: response).data.isEmpty)
    }

    @Test("The card host page and the bundled MathJax are served without any network")
    func hostPageAndMathJax() async throws {
        let folder = try TemporaryFolder()
        let (media, _) = try makeMedia(in: folder.url)
        let resources = CardResources(mediaFolder: media)

        let page = resources.response(to: CardResources.hostPageURL, range: nil)
        #expect(page.statusCode == 200)
        #expect(page.headers["Content-Type"]?.hasPrefix("text/html") == true)
        let html = String(decoding: try await body(of: page).data, as: UTF8.self)
        #expect(html.contains("hayaki.show"))

        let mathJax = resources.response(to: url("_hayaki/mathjax/tex-chtml-full.js"), range: nil)
        #expect(mathJax.statusCode == 200)
        #expect(mathJax.headers["Content-Type"]?.contains("javascript") == true)
        let script = String(decoding: try await body(of: mathJax).data, as: UTF8.self)
        #expect(script.contains("MathJax"))
        let font = resources.response(to: url("_hayaki/mathjax/output/chtml/fonts/woff-v2/MathJax_Main-Regular.woff"), range: nil)
        #expect(font.statusCode == 200)
    }
}
