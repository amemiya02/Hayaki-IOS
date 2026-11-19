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
/// the monitor, which reads progress and media sync results and makes the
/// core's abort calls without waiting behind the operation they refer to.
///
/// A failed call throws `CoreError` with the core's error kind and its
/// localised message. After a panic inside the core (`CoreError.isPanic`) the
/// client replaces its backend, because a panic can leave the core's
/// collection lock poisoned; any collection that was open is then closed and
/// must be opened again.
public final class CoreClient: Sendable {
    /// The Anki release bundled with the app, generated during the core build.
    public static let embeddedVersion = embeddedAnkiVersion

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
            throw CoreError(kind: .protoError, message: String(
                localized: "Could not encode the core's settings: \(error.localizedDescription)", bundle: .module
            ))
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

    /// Updates just the scheduler preferences on the core's serialized worker.
    public func updateSchedulingPreferences(
        _ update: @Sendable @escaping (inout Anki_Config_Preferences.Scheduling) -> Void
    ) async throws(CoreError) -> Anki_Collection_OpChanges {
        try await worker.run {
            self.execute(.getPreferences()).flatMap { latest in
                var scheduling = latest.scheduling
                update(&scheduling)
                return self.execute(.setPreferences(.with { $0.scheduling = scheduling }))
            }
        }.get()
    }

    /// Reads a page with one browser's columns and row mode. The core shares
    /// both settings among all browser windows, so no other call may run
    /// between configuring the page and retrieving its rows.
    public func browserRows(ids: [Int64], columns: [String], notesMode: Bool) async throws(CoreError)
        -> [Int64: Anki_Search_BrowserRow]
    {
        try await worker.run { () -> Result<[Int64: Anki_Search_BrowserRow], CoreError> in
            do throws(CoreError) {
                let key = Anki_Config_ConfigKey.BoolEnum.browserTableShowNotesMode
                let preferredMode = try self.execute(.getConfigBool(.with { $0.key = key })).get().val
                _ = try self.execute(.setActiveBrowserColumns(.with { $0.vals = columns })).get()
                if preferredMode != notesMode {
                    _ = try self.execute(.setConfigBool(.with {
                        $0.key = key
                        $0.value = notesMode
                    })).get()
                }
                var rows: [Int64: Anki_Search_BrowserRow] = [:]
                for id in ids {
                    // The search's IDs may include a row that was since deleted.
                    if let row = try? self.execute(.browserRowForId(.with { $0.val = id })).get() {
                        rows[id] = row
                    }
                }
                if preferredMode != notesMode {
                    _ = try self.execute(.setConfigBool(.with {
                        $0.key = key
                        $0.value = preferredMode
                    })).get()
                }
                return .success(rows)
            } catch {
                return .failure(error)
            }
        }.get()
    }

    /// Atomically applies an undo offer if the core is still at the expected step.
    public func undo(ifLastStep step: UInt32) async throws(CoreError) -> Anki_Collection_OpChangesAfterUndo? {
        try await worker.run {
            self.execute(.getUndoStatus()).flatMap { status in
                guard status.lastStep == step, !status.undo.isEmpty else { return .success(nil) }
                return self.execute(.undo()).map(Optional.some)
            }
        }.get()
    }

    /// Starts a long operation on the worker thread, queued behind earlier
    /// calls like any other, and returns at once. The operation polls the
    /// core's progress every `pollingInterval` while it runs; the core itself
    /// refreshes its progress at most every 0.1 seconds.
    ///
    /// Cancellation reaches the core through `abortCall`. The default,
    /// `SetWantsAbort`, sets the core's abort flag, which only operations that
    /// report progress check, so `cancel()` stops those. Signing in to a sync
    /// server and syncing the collection have an abort call of their own and
    /// must pass `.abortSync()`. Use `startMediaSync(_:)` for media.
    public func start<Response>(
        _ call: CoreCall<Response>,
        abortingWith abortCall: CoreCall<Anki_Generic_Empty> = .setWantsAbort(),
        pollingInterval: Duration = .milliseconds(100)
    ) -> LongOperation<Response> {
        let operation = LongOperation<Response> { operation in
            self.monitor.submit { self.abort(operation, with: abortCall) }
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
            await self.poll(operation, abortingWith: abortCall, every: pollingInterval)
        }
        return operation
    }

    /// Starts Anki's background media sync. The worker starts the transfer
    /// against the open collection and is free to handle other calls while
    /// the monitor collects progress, the final result and any error.
    public func startMediaSync(_ auth: Anki_Sync_SyncAuth) -> LongOperation<Anki_Generic_Empty> {
        let operation = LongOperation<Anki_Generic_Empty> { operation in
            self.monitor.submit { self.abort(operation, with: .abortMediaSync()) }
        }
        worker.submit {
            let stale = (try? self.call(.latestProgress()).get()) ?? Anki_Collection_Progress()
            guard operation.begin(staleProgress: stale) else {
                operation.finish(.failure(.interrupted))
                return
            }
            switch self.execute(.syncMedia(auth)) {
            case .success:
                Task { await self.pollMediaSync(operation) }
            case .failure(let error):
                operation.finish(.failure(error))
            }
        }
        return operation
    }

    /// Discards the derived media sync database so the next sign-in can
    /// reconcile the existing files against its own server's change sequence.
    /// The worker excludes other collection calls. An inactive media status
    /// means the core has joined the background task and closed its database.
    public func resetMediaDatabase(at database: URL) async throws(CoreError) {
        let result: Result<Void, CoreError> = await worker.run {
            self.execute(.mediaSyncStatus()).flatMap { status in
                guard !status.active else {
                    return .failure(CoreError(kind: .invalidInput, message: String(localized: "Media sync is still running.", bundle: .module)))
                }
                do {
                    for suffix in ["-wal", "-shm", ""] {
                        let file = URL(filePath: database.path() + suffix)
                        do {
                            try FileManager.default.removeItem(at: file)
                        } catch let error as CocoaError where error.code == .fileNoSuchFile {
                            continue
                        }
                    }
                    return .success(())
                } catch {
                    return .failure(CoreError(kind: .ioError, message: error.localizedDescription))
                }
            }
        }
        try result.get()
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

    private func pollMediaSync(_ operation: LongOperation<Anki_Generic_Empty>) async {
        while !operation.isFinished {
            await monitor.run {
                self.abort(operation, with: .abortMediaSync())
                switch self.call(.mediaSyncStatus()) {
                case .success(let status):
                    if status.hasProgress {
                        operation.report(.with { $0.value = .mediaSync(status.progress) })
                    }
                    if !status.active { operation.finish(.success(.init())) }
                case .failure(let error):
                    operation.finish(.failure(error))
                }
            }
            if !operation.isFinished { try? await Task.sleep(for: .milliseconds(100)) }
        }
    }

    /// Polls until the operation has finished. Only the sleeping happens on
    /// the concurrency pool; each poll is a quick call on the monitor thread.
    private func poll<Response>(
        _ operation: LongOperation<Response>,
        abortingWith abortCall: CoreCall<Anki_Generic_Empty>,
        every interval: Duration
    ) async {
        while !operation.isFinished {
            try? await Task.sleep(for: interval)
            await monitor.run {
                // Repeated while cancelled: the core clears its abort flag when
                // an operation sets up its progress reporting, and a sync only
                // becomes abortable once it has registered itself, so a request
                // that arrived just before either would otherwise be lost.
                self.abort(operation, with: abortCall)
                if case .success(let progress) = self.call(.latestProgress()) {
                    operation.report(progress)
                }
            }
        }
    }

    private func abort<Response>(_ operation: LongOperation<Response>, with abortCall: CoreCall<Anki_Generic_Empty>) {
        operation.abortIfCancelled {
            _ = self.call(abortCall)
        }
    }

    // MARK: Either thread

    /// Runs a call on the current thread.
    private func call<Response>(_ call: CoreCall<Response>) -> Result<Response, CoreError> {
        guard let backend = backend.withLock({ $0 }) else {
            return .failure(CoreError(kind: .invalidInput, message: String(localized: "The core has been closed.", bundle: .module)))
        }
        return call.encodedRequest()
            .flatMap { backend.run(call.method, input: $0) }
            .flatMap(call.decode)
    }
}
