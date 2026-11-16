import Foundation
import HayakiBridge

/// One open backend of the Anki core, reached through the four C functions of
/// the Hayaki bridge. Requests and responses are encoded protobuf messages.
/// Only the Core Client uses it, and decides which thread calls it.
///
/// `@unchecked Sendable` is justified: the only state is the opaque handle,
/// which is immutable after `init`, and the core's backend guards its own state
/// with locks, so calling it from two threads at once is supported (upstream
/// Anki and AnkiDroid poll progress from a second thread the same way). The
/// handle is closed exactly once, in `deinit`.
final class Backend: @unchecked Sendable {
    private let handle: OpaquePointer

    /// Opens a backend from an encoded `anki.backend.BackendInit`.
    init(init request: Data) throws(CoreError) {
        var error = HayakiBuffer()
        let handle = request.withUnsafeBytes { raw in
            hayaki_backend_open(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &error)
        }
        guard let handle else {
            throw CoreError(encoded: Self.take(error))
        }
        self.handle = handle
    }

    /// Runs one method of the core and returns its encoded response.
    func run(_ method: CoreMethod, input: Data) -> Result<Data, CoreError> {
        var output = HayakiBuffer()
        let status = input.withUnsafeBytes { raw in
            hayaki_backend_run(
                handle,
                method.service,
                method.method,
                raw.bindMemory(to: UInt8.self).baseAddress,
                raw.count,
                &output
            )
        }
        let bytes = Self.take(output)
        return status == 0 ? .success(bytes) : .failure(CoreError(encoded: bytes))
    }

    deinit {
        hayaki_backend_close(handle)
    }

    /// Copies a buffer owned by the bridge and frees it.
    private static func take(_ buffer: HayakiBuffer) -> Data {
        defer { hayaki_buffer_free(buffer) }
        guard let data = buffer.data, buffer.len > 0 else { return Data() }
        return Data(bytes: data, count: buffer.len)
    }
}
