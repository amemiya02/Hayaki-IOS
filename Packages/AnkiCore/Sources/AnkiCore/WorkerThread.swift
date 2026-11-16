import Foundation
import Synchronization

/// A thread of its own that runs submitted jobs one at a time, in the order
/// they were submitted. Jobs never run on the main thread or on Swift's shared
/// concurrency pool.
final class WorkerThread: Sendable {
    private struct Queue {
        var jobs: [@Sendable () -> Void] = []
        var stopped = false
    }

    private let queue = Mutex(Queue())
    /// Signalled once per submitted job and once more on stop.
    private let wakeUp = DispatchSemaphore(value: 0)

    init(name: String) {
        let thread = Thread { [self] in runLoop() }
        thread.name = name
        // Secondary threads get 512 KB by default; the core's SQLite, template
        // and search code expect a main-thread-sized stack.
        thread.stackSize = 8 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Queues a job. Jobs submitted after `stop()` are dropped.
    func submit(_ job: @escaping @Sendable () -> Void) {
        let accepted = queue.withLock { queue in
            guard !queue.stopped else { return false }
            queue.jobs.append(job)
            return true
        }
        if accepted { wakeUp.signal() }
    }

    /// Runs `body` on this thread and returns its result to the awaiting task.
    func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            submit { continuation.resume(returning: body()) }
        }
    }

    /// Lets the thread finish the jobs already queued, then end.
    func stop() {
        queue.withLock { $0.stopped = true }
        wakeUp.signal()
    }

    private func runLoop() {
        while true {
            wakeUp.wait()
            let job = queue.withLock { queue in
                queue.jobs.isEmpty ? nil : queue.jobs.removeFirst()
            }
            // Only the stop signal finds the queue empty.
            guard let job else { return }
            autoreleasepool { job() }
        }
    }
}
