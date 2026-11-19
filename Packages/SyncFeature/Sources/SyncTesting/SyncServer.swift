#if os(macOS)
import CollectionTesting
import Foundation
import Synchronization
import Testing

/// Upstream Anki's own sync server, built from the same pinned source as the
/// core by `scripts/build-sync-server.sh`, running on a free local port with a
/// throwaway data folder for one test.
public final class SyncServer {
    /// Where `scripts/build-sync-server.sh` puts the server, or the path in
    /// `HAYAKI_SYNC_SERVER` when that is set.
    static let binary: URL = {
        if let path = ProcessInfo.processInfo.environment["HAYAKI_SYNC_SERVER"] {
            return URL(fileURLWithPath: path)
        }
        // Packages/SyncFeature/Sources/SyncTesting/SyncServer.swift -> repository root
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("build/sync-server/anki-sync-server")
    }()

    public static var isBuilt: Bool { FileManager.default.isExecutableFile(atPath: binary.path) }

    public static let skipMessage: Comment = """
        The sync server has not been built, so the tests that sync against it are skipped. \
        Build it with scripts/build-sync-server.sh.
        """

    /// The address a learner would enter, such as `http://127.0.0.1:53817/`.
    public let address: String
    private var process: Process
    private var output: LogBuffer
    private let folder: URL
    private let environment: [String: String]

    /// Starts a server with these users, each `(name, password)`, and waits
    /// until it accepts connections.
    public init(users: [(String, String)]) async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("hayaki-sync-server-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var environment = [
            "SYNC_BASE": folder.path,
            "SYNC_HOST": "127.0.0.1",
            // The system picks a free port; the server logs which.
            "SYNC_PORT": "0",
            "RUST_LOG": "anki=info",
            "NO_COLOR": "1",
        ]
        for (index, user) in users.enumerated() {
            environment["SYNC_USER\(index + 1)"] = "\(user.0):\(user.1)"
        }
        let (process, output, port) = try await Self.launch(environment: environment)
        environment["SYNC_PORT"] = port
        self.environment = environment
        self.process = process
        self.output = output
        address = "http://127.0.0.1:\(port)/"
    }

    private static func launch(environment: [String: String]) async throws -> (Process, LogBuffer, String) {
        let process = Process()
        process.executableURL = Self.binary
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = LogBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            output.append(String(decoding: data, as: UTF8.self))
        }
        try process.run()

        var port: String?
        do {
            try await eventually(timeout: .seconds(20), "the sync server to start listening") {
                port = Self.listeningPort(in: output.text)
                return port != nil || !process.isRunning
            }
        } catch {
            process.terminate()
            throw error
        }
        guard let port else {
            throw ServerFailed(description: "The sync server exited:\n\(output.text)")
        }
        return (process, output, port)
    }

    deinit {
        stop()
        try? FileManager.default.removeItem(at: folder)
    }

    /// Everything the server has logged so far, one line per request.
    public var log: String { Self.withoutColour(output.text) }

    public var processIdentifier: Int32 { process.processIdentifier }

    public func resume() {
        if process.isRunning { _ = Darwin.kill(processIdentifier, SIGCONT) }
    }

    /// Drops active connections while keeping the server's on-disk data.
    public func interrupt() {
        if process.isRunning {
            _ = Darwin.kill(processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    @MainActor public func restart() async throws {
        stop()
        let (process, output, _) = try await Self.launch(environment: environment)
        self.process = process
        self.output = output
    }

    public func stop() {
        if process.isRunning {
            process.terminate()
            resume()
            process.waitUntilExit()
        }
    }

    private static func listeningPort(in output: String) -> String? {
        let text = withoutColour(output)
        guard let line = text.split(separator: "\n").first(where: { $0.contains("listening") }),
              let match = line.firstMatch(of: /addr=[0-9.]+:(\d+)/)
        else { return nil }
        return String(match.1)
    }

    private static func withoutColour(_ text: String) -> String {
        text.replacing(/\u{1B}\[[0-9;]*m/, with: "")
    }

    struct ServerFailed: Error, CustomStringConvertible {
        let description: String
    }
}

/// The server's output, appended to from the pipe's reading thread.
private final class LogBuffer: Sendable {
    private let contents = Mutex("")

    var text: String { contents.withLock { $0 } }

    func append(_ text: String) {
        contents.withLock { $0 += text }
    }
}

/// A local address where nothing listens, as when a server is down or the
/// address is mistyped: connections are refused at once.
public func unreachableAddress() throws -> String {
    let socket = try ListeningSocket()
    let port = socket.port
    socket.close()
    return "http://127.0.0.1:\(port)/"
}

/// A socket that accepts connections (the system completes them) but never
/// answers, like a server that has hung.
public final class ListeningSocket: Sendable {
    let port: UInt16
    private let descriptor: Mutex<Int32>

    public init() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.bind(fd, address, length) == 0
                    && Darwin.listen(fd, 16) == 0
                    && getsockname(fd, address, &length) == 0
            }
        }
        guard bound else {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        port = UInt16(bigEndian: address.sin_port)
        descriptor = Mutex(fd)
    }

    public var address: String { "http://127.0.0.1:\(port)/" }

    public func close() {
        descriptor.withLock { fd in
            if fd >= 0 { Darwin.close(fd) }
            fd = -1
        }
    }

    deinit { close() }
}
#endif
