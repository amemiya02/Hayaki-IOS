import Foundation
import UserNotifications

/// Whether the learner lets Hayaki send notifications.
public enum NotificationPermission: Sendable, Equatable {
    /// The learner has not been asked yet.
    case notDetermined
    case allowed
    /// The learner refused, now or earlier, and can only change that in the
    /// Settings app.
    case denied
}

/// One reminder waiting to be delivered: a single, non-repeating local
/// notification at a fixed moment.
public struct ScheduledReminder: Sendable, Equatable {
    public let identifier: String
    public let delivery: Date
    public let title: String
    public let body: String

    public init(identifier: String, delivery: Date, title: String, body: String) {
        self.identifier = identifier
        self.delivery = delivery
        self.title = title
        self.body = body
    }

    /// Every reminder's identifier starts with this, so Hayaki's reminders can
    /// be told apart from any other notification it might schedule.
    public static let identifierPrefix = "hayaki.reminder."

    public static func isReminder(identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }
}

/// The part of the system's notification centre the reminder uses. The app
/// uses `SystemNotificationCentre`; tests substitute their own, since the
/// system's cannot run in a test process on the Mac.
public protocol NotificationCentre: Sendable {
    func permission() async -> NotificationPermission
    /// Asks the learner for permission if they have not been asked yet, and
    /// returns whether notifications are allowed.
    func requestPermission() async throws -> Bool
    /// Hayaki's pending reminders, soonest first.
    func pendingReminders() async -> [ScheduledReminder]
    /// Schedules a reminder, replacing a pending one with the same identifier.
    func add(_ reminder: ScheduledReminder) async throws
    func removeReminders(withIdentifiers identifiers: [String]) async
}

/// The system's notification centre. Only local notifications are used:
/// nothing here needs a paid Apple Developer membership or a push entitlement.
public struct SystemNotificationCentre: NotificationCentre {
    public init() {}

    private var centre: UNUserNotificationCenter { .current() }

    public func permission() async -> NotificationPermission {
        switch await centre.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .denied
        }
    }

    public func requestPermission() async throws -> Bool {
        try await centre.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func pendingReminders() async -> [ScheduledReminder] {
        await centre.pendingNotificationRequests()
            .filter { ScheduledReminder.isReminder(identifier: $0.identifier) }
            .compactMap { request in
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let delivery = trigger.nextTriggerDate()
                else { return nil }
                return ScheduledReminder(
                    identifier: request.identifier,
                    delivery: delivery,
                    title: request.content.title,
                    body: request.content.body
                )
            }
            .sorted { $0.delivery < $1.delivery }
    }

    public func add(_ reminder: ScheduledReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = "hayaki.reminder"
        if DeckReminderDestination(identifier: reminder.identifier) != nil {
            content.categoryIdentifier = DeckReminderActions.categoryID
        }
        // A calendar trigger for one moment: year to minute, no repeat. The
        // moment is in the learner's time zone at the time of scheduling.
        let moment = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.delivery
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: moment, repeats: false)
        try await centre.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }

    public func removeReminders(withIdentifiers identifiers: [String]) async {
        centre.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
