import AnkiProto
import Foundation
import Synchronization

/// The app's single way into Anki's core.
///
/// Every method of the core is available as a typed async method generated
/// from the core's descriptor set (see `Generated/CoreCalls.swift`), for
/// example `getDeckNames(_:)`. All of them run, one at a time and in the order
/// they were made, on one dedicated worker thread owned by the client: never
/// on the main thread and never on Swift's shared concurrency pool.
///
/// A long operation is started with `start(_:)` instead, which adds progress
/// reports and cancellation. Those use a second thread owned by the client,
/// the monitor, which only ever reads the core's latest progress and sets its
/// abort flag, so neither waits behind the operation they refer to.
///
/// A failed call throws `CoreError` with the core's error kind and its
/// localised message. After a panic inside the core (`CoreError.isPanic`) the
/// client replaces its backend, because a panic can leave the core's
/// collection lock poisoned; any collection that was open is then closed and
/// must be opened again.
public final class CoreClient: Sendable {
    private let worker: WorkerThread
    private let monitor: WorkerThread
    private let backend: Mutex<Backend?>
    /// The encoded `BackendInit`, kept to replace the backend after a panic.
    private let initRequest: Data

    /// Starts the core in exactly one language, the one the app's own screens
    /// resolved to, given as a BCP 47 tag such as `"en"`, `"ja"` or `"zh-CN"`.
    /// The core's messages, including error messages, use this language.
    public init(language: String) async throws(CoreError) {
        let initRequest: Data
        do {
            initRequest = try Anki_Backend_BackendInit.with { $0.preferredLangs = [language] }.serializedData()
        } catch {
            throw CoreError(kind: .protoError, message: "Could not encode the core's settings: \(error)")
        }
        let worker = WorkerThread(name: "Hayaki Core")
        let opened = await worker.run { () -> Result<Backend, CoreError> in
            do throws(CoreError) {
                return .success(try Backend(init: initRequest))
            } catch {
                return .failure(error)
            }
        }
        switch opened {
        case .success(let backend):
            self.worker = worker
            self.monitor = WorkerThread(name: "Hayaki Core Monitor")
            self.initRequest = initRequest
            self.backend = Mutex(backend)
        case .failure(let error):
            worker.stop()
            throw error
        }
    }

    deinit {
        monitor.stop()
        // Close the backend on the worker too, after any calls still queued.
        let backend = backend.withLock { $0.take() }
        worker.submit { [backend] in withExtendedLifetime(backend) {} }
        _ = consume backend
        worker.stop()
    }

    /// Runs one call on the worker thread and returns its typed response.
    public func perform<Response>(_ call: CoreCall<Response>) async throws(CoreError) -> Response {
        try await worker.run { self.execute(call) }.get()
    }

    /// Starts a long operation on the worker thread, queued behind earlier
    /// calls like any other, and returns at once. The operation polls the
    /// core's progress every `pollingInterval` while it runs; the core itself
    /// refreshes its progress at most every 0.1 seconds.
    ///
    /// Cancellation reaches the core through its abort flag, which only
    /// operations that report progress check, so `cancel()` stops those.
    public func start<Response>(
        _ call: CoreCall<Response>,
        pollingInterval: Duration = .milliseconds(100)
    ) -> LongOperation<Response> {
        let operation = LongOperation<Response> { operation in
            self.monitor.submit { self.abort(operation) }
        }
        worker.submit {
            // Whatever the core reports before the operation begins belongs to
            // an earlier one.
            let stale = (try? self.call(.latestProgress()).get()) ?? Anki_Collection_Progress()
            guard operation.begin(staleProgress: stale) else {
                operation.finish(.failure(.interrupted))
                return
            }
            operation.finish(self.execute(call))
        }
        Task {
            await self.poll(operation, every: pollingInterval)
        }
        return operation
    }

    // MARK: Worker thread

    private func execute<Response>(_ call: CoreCall<Response>) -> Result<Response, CoreError> {
        let result = self.call(call)
        if case .failure(let error) = result, error.isPanic {
            replaceBackend()
        }
        return result
    }

    /// If a new backend cannot be opened the old one stays, and later calls
    /// report whatever it reports.
    private func replaceBackend() {
        guard let fresh = try? Backend(init: initRequest) else { return }
        backend.withLock { $0 = fresh }
    }

    // MARK: Monitor thread

    /// Polls until the operation has finished. Only the sleeping happens on
    /// the concurrency pool; each poll is a quick call on the monitor thread.
    private func poll<Response>(_ operation: LongOperation<Response>, every interval: Duration) async {
        while !operation.isFinished {
            try? await Task.sleep(for: interval)
            await monitor.run {
                // Repeated while cancelled: the core clears its abort flag when
                // an operation sets up its progress reporting, so a request that
                // arrived just before that would otherwise be lost.
                self.abort(operation)
                if case .success(let progress) = self.call(.latestProgress()) {
                    operation.report(progress)
                }
            }
        }
    }

    private func abort<Response>(_ operation: LongOperation<Response>) {
        operation.abortIfCancelled {
            _ = self.call(.setWantsAbort())
        }
    }

    // MARK: Either thread

    /// Runs a call on the current thread.
    private func call<Response>(_ call: CoreCall<Response>) -> Result<Response, CoreError> {
        guard let backend = backend.withLock({ $0 }) else {
            return .failure(CoreError(kind: .invalidInput, message: "The core has been closed."))
        }
        return call.encodedRequest()
            .flatMap { backend.run(call.method, input: $0) }
            .flatMap(call.decode)
    }
}
