import Foundation
import HayakiBridge

/// A call the core rejected. `encodedError` is an encoded `anki.backend.BackendError`
/// carrying the error kind and the core's localised message. A panic inside the
/// core arrives here too, with kind `ANKIDROID_PANIC_ERROR`.
public struct BackendFailure: Error, Sendable {
    public let encodedError: Data
}

/// One open backend of the Anki core, reached through the four C functions of
/// the Hayaki bridge. Requests and responses are encoded protobuf messages.
///
/// The core's backend is safe to call from several threads at once (it guards its
/// own state), hence `@unchecked Sendable`. Choosing which thread calls it is up
/// to the caller.
public final class Backend: @unchecked Sendable {
    private let handle: OpaquePointer

    /// Opens a backend from an encoded `anki.backend.BackendInit`.
    public init(init request: Data) throws(BackendFailure) {
        var error = HayakiBuffer()
        let handle = request.withUnsafeBytes { raw in
            hayaki_backend_open(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &error)
        }
        guard let handle else {
            throw BackendFailure(encodedError: Self.take(error))
        }
        self.handle = handle
    }

    /// Runs one method of the core and returns its encoded response.
    public func run(_ method: CoreMethod, input: Data) throws(BackendFailure) -> Data {
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
        guard status == 0 else {
            throw BackendFailure(encodedError: bytes)
        }
        return bytes
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
