import CollectionStore
import Foundation
import Observation

/// The reminder screen: turning the daily reminder on and off, choosing its
/// time, and what the next reminder will say.
@MainActor
@Observable
public final class ReminderModel {
    public private(set) var isOn: Bool
    /// Today at the chosen time of day.
    public private(set) var time: Date
    /// The learner refused notifications, so the reminder cannot be delivered
    /// until they allow them in the Settings app.
    public private(set) var notificationsRefused = false
    /// The next reminder to be delivered, if any.
    public private(set) var nextReminder: ScheduledReminder?

    @ObservationIgnored private let centre: any NotificationCentre
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let schedule: ReminderSchedule
    @ObservationIgnored private let store: CollectionStore

    public init(
        store: CollectionStore,
        centre: any NotificationCentre = SystemNotificationCentre(),
        defaults: UserDefaults = .standard,
        profileID: UUID? = nil
    ) {
        self.store = store
        self.centre = centre
        self.defaults = defaults
        schedule = ReminderSchedule(store: store, centre: centre, defaults: defaults, profileID: profileID)
        let preferences = ReminderPreferences(from: defaults)
        isOn = preferences.isOn
        time = Self.today(at: preferences)
    }

    /// Turns the reminder on or off. Turning it on asks for permission to send
    /// notifications if the learner has not been asked; if they refuse, the
    /// reminder stays off and `notificationsRefused` says why.
    public func setOn(_ on: Bool) async {
        isOn = on
        if on {
            let allowed = (try? await centre.requestPermission()) ?? false
            notificationsRefused = !allowed
            guard allowed else {
                isOn = false
                return
            }
        }
        var preferences = ReminderPreferences(from: defaults)
        preferences.isOn = on
        preferences.save(to: defaults)
        await rescheduled()
    }

    /// Chooses the time of day; only its hour and minute count.
    public func setTime(_ time: Date) async {
        var preferences = ReminderPreferences(from: defaults)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        preferences.hour = parts.hour ?? preferences.hour
        preferences.minute = parts.minute ?? preferences.minute
        preferences.save(to: defaults)
        self.time = Self.today(at: preferences)
        await rescheduled()
    }

    /// Shows the reminder's state, then keeps the next reminder current
    /// whenever the collection changes, until the calling task is cancelled.
    /// The reminder screen runs this in its `.task`.
    public func run() async {
        let changes = store.changes()
        await refreshPermission()
        await rescheduled()
        for await _ in changes {
            await rescheduled()
        }
    }

    /// Notices that the learner allowed or refused notifications in the
    /// Settings app meanwhile.
    public func refreshPermission() async {
        let permission = await centre.permission()
        if isOn {
            notificationsRefused = permission != .allowed
        } else if notificationsRefused {
            // Shown since the learner tried to turn the reminder on; it stays
            // until they allow notifications.
            notificationsRefused = permission == .denied
        }
    }

    private func rescheduled() async {
        await schedule.update()
        nextReminder = await centre.pendingReminders().first { !$0.identifier.hasPrefix(DeckReminderDestination.prefix) }
    }

    private static func today(at preferences: ReminderPreferences) -> Date {
        Calendar.current.date(
            bySettingHour: preferences.hour,
            minute: preferences.minute,
            second: 0,
            of: Date.now
        ) ?? Date.now
    }
}
