#if os(iOS)
import UIKit

/// A bounded iOS execution assertion for a sync or its background follow-up.
@MainActor
public final class SyncBackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    public var isValid: Bool { identifier != .invalid }

    public init(onExpiration: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Hayaki Sync") { [weak self] in
            onExpiration()
            self?.end()
        }
    }

    public func end() {
        guard isValid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
