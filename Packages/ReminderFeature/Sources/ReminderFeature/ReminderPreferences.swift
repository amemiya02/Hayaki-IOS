import Foundation

/// The learner's reminder choices. They belong to this device, not to the
/// collection, so they live in the app's user defaults rather than in the
/// collection's config, and a sync never carries them to another device.
struct ReminderPreferences: Equatable {
    var isOn = false
    /// The time of day, in the learner's current time zone.
    var hour = 9
    var minute = 0

    enum Key {
        static let isOn = "reminder.isOn"
        static let hour = "reminder.hour"
        static let minute = "reminder.minute"
    }

    init() {}

    init(from defaults: UserDefaults) {
        isOn = defaults.bool(forKey: Key.isOn)
        if defaults.object(forKey: Key.hour) != nil {
            hour = defaults.integer(forKey: Key.hour)
            minute = defaults.integer(forKey: Key.minute)
        }
    }

    func save(to defaults: UserDefaults) {
        defaults.set(isOn, forKey: Key.isOn)
        defaults.set(hour, forKey: Key.hour)
        defaults.set(minute, forKey: Key.minute)
    }
}
