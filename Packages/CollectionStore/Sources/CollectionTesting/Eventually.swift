import Foundation

/// The condition did not become true in time.
public struct TimedOut: Error, CustomStringConvertible {
    public let description: String
}

/// Waits until `condition` is true, checking it every few milliseconds on the
/// caller's actor, for example until a model that refreshes in the background
/// shows what a learner should now see. Throws `TimedOut` after `timeout`.
public func eventually(
    timeout: Duration = .seconds(5),
    _ what: String = "condition",
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            throw TimedOut(description: "\(what) was still false after \(timeout)")
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
