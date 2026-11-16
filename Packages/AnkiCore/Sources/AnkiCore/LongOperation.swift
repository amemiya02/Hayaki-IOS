import AnkiProto
import Foundation
import Synchronization

/// A call into the core that may run for a while, such as a sync, an import or
/// export, FSRS optimisation or a collection check. Start one with
/// `CoreClient.start(_:)`.
///
/// While it runs, `progress` yields the core's progress reports, and `cancel()`
/// asks the core to stop. Both go through a second thread of the Core Client,
/// so neither waits behind the operation itself. Await `result` for the
/// response; a cancelled operation throws a `CoreError` whose `isInterrupted`
/// is true, unless it had already finished.
public final class LongOperation<Response: SwiftProtobuf.Message>: Sendable {
    private enum Phase {
        case queued, running, finished
    }

    private struct State {
        var phase = Phase.queued
        var cancelRequested = false
        /// The progress the core reported before this operation started; it
        /// belongs to an earlier operation and is not passed on.
        var staleProgress: Anki_Collection_Progress?
        var lastProgress: Anki_Collection_Progress?
        var outcome: Result<Response, CoreError>?
        var waiters: [CheckedContinuation<Result<Response, CoreError>, Never>] = []
    }

    /// The core's progress reports while the operation runs, without repeats.
    /// The sequence ends when the operation ends.
    public let progress: AsyncStream<Anki_Collection_Progress>

    private let state = Mutex(State())
    private let progressContinuation: AsyncStream<Anki_Collection_Progress>.Continuation
    private let requestAbort: @Sendable (LongOperation) -> Void

    init(requestAbort: @escaping @Sendable (LongOperation) -> Void) {
        (progress, progressContinuation) = AsyncStream.makeStream()
        self.requestAbort = requestAbort
    }

    /// The operation's response. Cancelling the awaiting task cancels the
    /// operation.
    public var result: Response {
        get async throws(CoreError) {
            let outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    state.withLock { state in
                        if let outcome = state.outcome {
                            continuation.resume(returning: outcome)
                        } else {
                            state.waiters.append(continuation)
                        }
                    }
                }
            } onCancel: {
                cancel()
            }
            return try outcome.get()
        }
    }

    /// Asks the core to stop the operation. A queued operation does not start;
    /// a running one stops at the core's next progress checkpoint.
    public func cancel() {
        let running = state.withLock { state in
            state.cancelRequested = true
            return state.phase == .running
        }
        if running { requestAbort(self) }
    }

    // MARK: Driven by the Core Client

    /// On the worker, just before the call. Returns false if it must not run.
    func begin(staleProgress: Anki_Collection_Progress) -> Bool {
        state.withLock { state in
            guard !state.cancelRequested else { return false }
            state.phase = .running
            state.staleProgress = staleProgress
            return true
        }
    }

    /// On the worker, when the call has returned or was skipped.
    func finish(_ outcome: Result<Response, CoreError>) {
        let waiters = state.withLock { state in
            state.phase = .finished
            state.outcome = outcome
            defer { state.waiters = [] }
            return state.waiters
        }
        progressContinuation.finish()
        for waiter in waiters {
            waiter.resume(returning: outcome)
        }
    }

    /// On the monitor thread. Runs `abort` only while the operation runs and
    /// has been cancelled, holding the state lock so that the operation cannot
    /// be marked finished, and the next one begin, in the meantime.
    func abortIfCancelled(_ abort: () -> Void) {
        state.withLock { state in
            if state.phase == .running, state.cancelRequested { abort() }
        }
    }

    /// Whether the poller should stop.
    var isFinished: Bool {
        state.withLock { $0.phase == .finished }
    }

    /// Passes on a progress report read from the core while running.
    func report(_ progress: Anki_Collection_Progress) {
        let isNew = state.withLock { state in
            guard state.phase == .running, progress.value != nil else { return false }
            if state.lastProgress == nil, progress == state.staleProgress { return false }
            guard progress != state.lastProgress else { return false }
            state.lastProgress = progress
            return true
        }
        if isNew { progressContinuation.yield(progress) }
    }
}
