import Foundation
import ReminderFeature

/// Stands in for the system's notification centre, the one boundary the
/// reminder tests substitute: it keeps the pending reminders in memory and
/// answers the permission request the way the test says the learner did.
@MainActor
final class RecordingNotificationCentre: NotificationCentre {
    private var currentPermission: NotificationPermission
    private let learnerAllows: Bool
    private var pending: [String: ScheduledReminder] = [:]
    private(set) var permissionRequests = 0

    /// - Parameters:
    ///   - permission: Whether the learner has already answered the request.
    ///   - learnerAllows: How the learner answers the request when asked.
    init(permission: NotificationPermission = .notDetermined, learnerAllows: Bool = true) {
        currentPermission = permission
        self.learnerAllows = learnerAllows
    }

    func permission() async -> NotificationPermission {
        currentPermission
    }

    func requestPermission() async throws -> Bool {
        permissionRequests += 1
        if currentPermission == .notDetermined {
            currentPermission = learnerAllows ? .allowed : .denied
        }
        return currentPermission == .allowed
    }

    func pendingReminders() async -> [ScheduledReminder] {
        snapshot
    }

    /// The pending reminders, soonest first, read without waiting.
    var snapshot: [ScheduledReminder] {
        pending.values.sorted { $0.delivery < $1.delivery }
    }

    func add(_ reminder: ScheduledReminder) async throws {
        pending[reminder.identifier] = reminder
    }

    func removeReminders(withIdentifiers identifiers: [String]) async {
        for identifier in identifiers {
            pending[identifier] = nil
        }
    }

    /// The learner turns notifications for the app on or off in the Settings app.
    func learnerChangesPermission(to permission: NotificationPermission) {
        currentPermission = permission
    }
}
