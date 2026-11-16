import AnkiProto
import Foundation

/// A call the core rejected, with the core's error kind and its message,
/// already localised by the core into the Core Client's language.
public struct CoreError: Error, Sendable, Equatable, LocalizedError {
    public typealias Kind = Anki_Backend_BackendError.Kind

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    /// A panic inside the core. The Core Client has replaced its backend, so
    /// any collection that was open is closed and must be opened again.
    public var isPanic: Bool { kind == .ankidroidPanicError }

    /// The operation was cancelled before it finished.
    public var isInterrupted: Bool { kind == .interrupted }

    public var errorDescription: String? { message }

    /// Decodes an encoded `anki.backend.BackendError`.
    init(encoded: Data) {
        do {
            let error = try Anki_Backend_BackendError(serializedBytes: encoded)
            self.init(kind: error.kind, message: error.message)
        } catch {
            self.init(kind: .protoError, message: "Unreadable error from the core: \(error)")
        }
    }

    /// The core reports an interrupted operation with this exact message; it
    /// is not translated (see `AnkiError::message` in rslib).
    static let interrupted = CoreError(kind: .interrupted, message: "Interrupted")
}
