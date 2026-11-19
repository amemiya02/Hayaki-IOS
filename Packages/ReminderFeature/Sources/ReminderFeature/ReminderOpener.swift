import Foundation
import Observation
import UserNotifications

/// Notices when the learner opens a reminder, so the app can bring them to the
/// deck list.
@MainActor
@Observable
public final class ReminderOpener {
    public static let shared = ReminderOpener()

    /// The learner opened a reminder and the deck list has not been shown for
    /// it yet.
    public var deckListRequested = false
    public var deckRequested: DeckReminderDestination?

    @ObservationIgnored private var delegate: NotificationDelegate?

    public init() {}

    /// Becomes the system notification centre's delegate. Call it before the
    /// app finishes launching, so opening a reminder that launched the app is
    /// not missed.
    public func install() {
        let delegate = NotificationDelegate(opener: self)
        self.delegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// The learner opened the notification with this identifier.
    public func opened(notificationIdentifier identifier: String) {
        if let target = DeckReminderDestination(identifier: identifier) {
            deckRequested = target
        } else if ScheduledReminder.isReminder(identifier: identifier), !identifier.hasPrefix(DeckReminderDestination.prefix) {
            deckListRequested = true
        }
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let opener: ReminderOpener

    init(opener: ReminderOpener) {
        self.opener = opener
    }

    // The completion-handler forms, not the async ones: UIKit insists that
    // the completion runs on the main thread, and the async forms' generated
    // completion ran on a background thread and crashed the app when a
    // reminder was opened.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            opener.opened(notificationIdentifier: identifier)
            completionHandler()
        }
    }

    /// A reminder due while Hayaki is open still shows, as a banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler([.banner, .list, .sound])
        }
    }
}
