import Foundation
import Synchronization
import UniformTypeIdentifiers

/// Everything the card web view loads, served through Hayaki's own URL
/// scheme so that nothing comes from the network:
///
/// - `hayaki-card://card/` is the card host page (`CardHost.html`). Card
///   HTML is shown inside it, so a relative reference such as
///   `<img src="sol.png">` or a font `url("_font.ttf")` resolves to
/// - `hayaki-card://card/<name>`: the file of that name in the collection's
///   media folder, which holds no folders; and
/// - `hayaki-card://card/_hayaki/<path>`: the web assets bundled with the
///   app (MathJax), which a media file cannot clash with because media file
///   names never contain a slash.
///
/// Files are streamed in pieces of at most `chunkSize` bytes rather than
/// read whole, and a `Range` request gets just the bytes it asks for, as
/// audio and video playback in the web view needs.
struct CardResources: Sendable {
    static let scheme = "hayaki-card"
    static let hostPageURL = URL(string: "\(scheme)://card/")!
    /// The most a single piece of a streamed file holds.
    static let chunkSize = 256 * 1024

    /// A response to one request: its status, headers and body.
    struct Response: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: AsyncThrowingStream<Data, any Error>
    }

    let mediaFolder: URL
    private let assetsFolder: URL?
    private let hostPage: URL?

    init(mediaFolder: URL) {
        self.mediaFolder = mediaFolder
        assetsFolder = Bundle.module.url(forResource: "WebAssets", withExtension: nil)
        hostPage = Bundle.module.url(forResource: "CardHost", withExtension: "html")
    }

    /// The response to a request for `url`, with the request's `Range`
    /// header if it has one.
    func response(to url: URL, range: String?) -> Response {
        guard let file = file(for: url) else { return .notFound }
        return Self.serve(file, range: range)
    }

    /// The file a URL of the scheme stands for, or nil when there is none
    /// it may reach.
    private func file(for url: URL) -> URL? {
        guard url.scheme == Self.scheme else { return nil }
        let path = url.path(percentEncoded: false)
        if path.isEmpty || path == "/" {
            return hostPage
        }
        let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if name.hasPrefix("_hayaki/") {
            return asset(at: name.dropFirst("_hayaki/".count))
        }
        return mediaFile(named: name)
    }

    private func mediaFile(named name: String) -> URL? {
        guard Self.isPlainName(name) else { return nil }
        // Anki stores media names in NFC; a name may reach us in either form.
        for candidate in [name, name.precomposedStringWithCanonicalMapping] {
            let file = mediaFolder.appendingPathComponent(candidate, isDirectory: false)
            if Self.isRegularFile(file) {
                return file
            }
        }
        return nil
    }

    private func asset(at path: Substring) -> URL? {
        guard let assetsFolder else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy(Self.isPlainName) else { return nil }
        let file = components.reduce(assetsFolder) { $0.appendingPathComponent($1, isDirectory: false) }
        return Self.isRegularFile(file) ? file : nil
    }

    /// A single file or folder name: not empty, not `.` or `..`, no slashes.
    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
            && !name.contains("\0")
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    // MARK: Serving a file

    private static func serve(_ file: URL, range: String?) -> Response {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            return .notFound
        }
        var headers = [
            "Content-Type": contentType(of: file),
            "Accept-Ranges": "bytes",
            "Cache-Control": "no-cache",
        ]
        let requested = range.flatMap { ByteRange(header: $0) }
        guard let requested else {
            headers["Content-Length"] = "\(size)"
            return Response(statusCode: 200, headers: headers, body: stream(file, offset: 0, length: size))
        }
        guard let bytes = requested.resolved(size: size) else {
            return Response(
                statusCode: 416,
                headers: ["Content-Range": "bytes */\(size)", "Content-Length": "0"],
                body: .empty
            )
        }
        headers["Content-Length"] = "\(bytes.count)"
        headers["Content-Range"] = "bytes \(bytes.lowerBound)-\(bytes.upperBound - 1)/\(size)"
        return Response(
            statusCode: 206,
            headers: headers,
            body: stream(file, offset: bytes.lowerBound, length: UInt64(bytes.count))
        )
    }

    private static func contentType(of file: URL) -> String {
        let type = UTType(filenameExtension: file.pathExtension.lowercased())?.preferredMIMEType
            ?? "application/octet-stream"
        return type.hasPrefix("text/") ? type + "; charset=utf-8" : type
    }

    /// The file's bytes from `offset`, read a piece at a time as the reader
    /// asks for them.
    private static func stream(_ file: URL, offset: UInt64, length: UInt64) -> AsyncThrowingStream<Data, any Error> {
        let reader: ChunkReader
        do {
            reader = try ChunkReader(file: file, offset: offset, length: length)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return AsyncThrowingStream(unfolding: { try reader.next() })
    }
}

extension CardResources.Response {
    static var notFound: Self {
        Self(statusCode: 404, headers: ["Content-Length": "0"], body: .empty)
    }
}

extension AsyncThrowingStream where Element == Data, Failure == any Error {
    static var empty: Self {
        Self { $0.finish() }
    }
}

/// One byte range of an HTTP `Range` header (`bytes=0-99`, `bytes=100-`,
/// `bytes=-100`). A header asking for several ranges is not supported and
/// is answered with the whole file, as HTTP allows.
struct ByteRange: Equatable {
    enum Kind: Equatable {
        case from(UInt64, through: UInt64?)
        case last(UInt64)
    }

    let kind: Kind

    init?(header: String) {
        let value = header.trimmingCharacters(in: .whitespaces)
        guard value.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = value.dropFirst("bytes=".count).trimmingCharacters(in: .whitespaces)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return nil }
        let first = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let last = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            guard let count = UInt64(last) else { return nil }
            kind = .last(count)
        } else {
            guard let start = UInt64(first) else { return nil }
            if last.isEmpty {
                kind = .from(start, through: nil)
            } else {
                guard let end = UInt64(last), end >= start else { return nil }
                kind = .from(start, through: end)
            }
        }
    }

    /// The bytes of a file of `size` bytes this range covers, or nil when it
    /// covers none.
    func resolved(size: UInt64) -> Range<UInt64>? {
        switch kind {
        case .from(let start, let end):
            guard start < size else { return nil }
            return start..<(min(end ?? (size - 1), size - 1) + 1)
        case .last(let count):
            guard count > 0, size > 0 else { return nil }
            return (size - min(count, size))..<size
        }
    }
}

/// Reads a stretch of a file a piece at a time, closing it when done.
private final class ChunkReader: Sendable {
    private struct State {
        var handle: FileHandle?
        var remaining: UInt64
    }

    private let state: Mutex<State>

    init(file: URL, offset: UInt64, length: UInt64) throws {
        let handle = try FileHandle(forReadingFrom: file)
        try handle.seek(toOffset: offset)
        state = Mutex(State(handle: handle, remaining: length))
    }

    func next() throws -> Data? {
        try state.withLock { state in
            guard let handle = state.handle else { return nil }
            guard state.remaining > 0 else {
                try? handle.close()
                state.handle = nil
                return nil
            }
            let count = Int(min(UInt64(CardResources.chunkSize), state.remaining))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else {
                // The file got shorter while it was being read.
                try? handle.close()
                state.handle = nil
                return nil
            }
            state.remaining -= UInt64(data.count)
            return data
        }
    }

    deinit {
        state.withLock { try? $0.handle?.close() }
    }
}
