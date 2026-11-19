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
        let centre = UNUserNotificationCenter.current()
        centre.setNotificationCategories([DeckReminderActions.category])
        centre.delegate = delegate
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
        let request = response.notification.request
        let identifier = request.identifier
        let action = response.actionIdentifier
        let title = request.content.title
        let body = request.content.body
        Task { @MainActor in
            if action == UNNotificationDefaultActionIdentifier {
                opener.opened(notificationIdentifier: identifier)
            } else if let snooze = DeckReminderActions.Snooze(rawValue: action),
                      let target = DeckReminderDestination(identifier: identifier) {
                await DeckReminderActions.snooze(snooze, target: target, title: title, body: body)
            }
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


enum DeckReminderActions {
    static let categoryID = "hayaki.deck-reminder"

    enum Snooze: String {
        case fiveMinutes = "hayaki.snooze.five-minutes"
        case oneHour = "hayaki.snooze.one-hour"

        var seconds: TimeInterval {
            switch self {
            case .fiveMinutes: 5 * 60
            case .oneHour: 60 * 60
            }
        }
    }

    static var category: UNNotificationCategory {
        let fiveMinutes = UNNotificationAction(
            identifier: Snooze.fiveMinutes.rawValue,
            title: String(localized: "Snooze 5 Minutes", bundle: .module)
        )
        let oneHour = UNNotificationAction(
            identifier: Snooze.oneHour.rawValue,
            title: String(localized: "Snooze 1 Hour", bundle: .module)
        )
        return UNNotificationCategory(identifier: categoryID, actions: [fiveMinutes, oneHour], intentIdentifiers: [])
    }

    static func snooze(
        _ delay: Snooze, target: DeckReminderDestination, title: String, body: String,
        in centre: any NotificationCentre = SystemNotificationCentre()
    ) async {
        let pending = await centre.pendingReminders()
        if pending.count >= 64,
           let farthest = pending.reversed().first(where: {
               DeckReminderDestination(identifier: $0.identifier)?.isSnoozed == false
           }) {
            await centre.removeReminders(withIdentifiers: [farthest.identifier])
        }
        let id = target.identifierStem + "snoozed-" + UUID().uuidString
        try? await centre.add(ScheduledReminder(
            identifier: id, delivery: .now.addingTimeInterval(delay.seconds), title: title, body: body
        ))
    }
}
