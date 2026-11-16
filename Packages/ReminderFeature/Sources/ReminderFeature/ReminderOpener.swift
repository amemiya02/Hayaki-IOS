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
        if ScheduledReminder.isReminder(identifier: identifier) {
            deckListRequested = true
        }
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let opener: ReminderOpener

    init(opener: ReminderOpener) {
        self.opener = opener
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        await opener.opened(notificationIdentifier: identifier)
    }

    /// A reminder due while Hayaki is open still shows, as a banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
