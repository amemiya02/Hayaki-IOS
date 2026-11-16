import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

/// Keeps the pending reminders in line with the learner's choices and the
/// collection.
///
/// How the due count stays truthful: a local notification's text is fixed when
/// it is scheduled; nothing runs in the app when it is delivered. So rather
/// than one repeating notification, whose text would repeat yesterday's count
/// forever, the schedule holds one single notification for each of the next
/// `days` days, each saying what the core counts as due *at that moment*
/// (the deck tree computed for that time, so cards falling due on later days,
/// learning cards becoming due, and each day's new card limit are counted
/// as they will be). That count assumes no studying in between, which holds
/// because cards are only studied in Hayaki itself; whenever the collection
/// changes, the app returns to the foreground or moves to the background, the
/// whole schedule is computed again. A day with nothing to study gets no
/// reminder.
///
/// Limitations, stated plainly:
/// - Reviews done elsewhere (desktop Anki, AnkiDroid) are only known after a
///   sync; until then the counts are those of the collection on this device.
/// - If Hayaki is not opened for `days` days, the reminders run out and stop
///   until it is opened again. (iOS keeps at most 64 pending notifications per
///   app, which bounds the window.)
@MainActor
public final class ReminderSchedule {
    /// How many days ahead reminders are scheduled.
    public static let defaultDays = 30

    private let store: CollectionStore
    private let centre: any NotificationCentre
    private let defaults: UserDefaults
    private let days: Int
    private let calendar: Calendar

    /// Updates run one after another, across every schedule in the app, so a
    /// slower update can never re-add reminders a later one removed.
    private static var lastUpdate: Task<Void, Never>?

    public init(
        store: CollectionStore,
        centre: any NotificationCentre,
        defaults: UserDefaults = .standard,
        days: Int = ReminderSchedule.defaultDays,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.centre = centre
        self.defaults = defaults
        self.days = days
        self.calendar = calendar
    }

    /// Computes the reminders afresh from the learner's choices and the
    /// collection as it is now, and replaces the pending ones with them.
    public func update() async {
        let previous = Self.lastUpdate
        let update = Task {
            await previous?.value
            await self.replacePendingReminders()
        }
        Self.lastUpdate = update
        await update.value
    }

    /// Changes after which the counts may differ.
    private static let relevantChanges: CollectionChange = [.deck, .card, .config, .deckConfig, .studyQueues]

    /// Updates the reminders now, then again after every change to the
    /// collection that could alter the counts, until the calling task is
    /// cancelled. Changes that arrive within `settling` of one another (a
    /// learner answering card after card) lead to one update.
    public func keepCurrent(settling: Duration = .seconds(2)) async {
        let changes = store.changes()
        await update()
        for await change in changes where !change.isDisjoint(with: Self.relevantChanges) {
            guard settlingUpdate == nil else { continue }
            settlingUpdate = Task {
                try? await Task.sleep(for: settling)
                self.settlingUpdate = nil
                guard !Task.isCancelled else { return }
                await self.update()
            }
        }
        settlingUpdate?.cancel()
        settlingUpdate = nil
    }

    /// The update waiting for a burst of changes to settle.
    private var settlingUpdate: Task<Void, Never>?

    private func replacePendingReminders() async {
        let preferences = ReminderPreferences(from: defaults)
        let pending = await centre.pendingReminders().map(\.identifier)
        guard preferences.isOn, await centre.permission() == .allowed else {
            await centre.removeReminders(withIdentifiers: pending)
            return
        }
        let wanted: [ScheduledReminder]
        do {
            wanted = try await reminders(for: preferences, from: Date.now)
        } catch {
            // The collection could not be read (it may be being replaced);
            // keep what is scheduled until the next update.
            return
        }
        let wantedIdentifiers = Set(wanted.map(\.identifier))
        await centre.removeReminders(withIdentifiers: pending.filter { !wantedIdentifiers.contains($0) })
        for reminder in wanted {
            try? await centre.add(reminder)
        }
    }

    private func reminders(for preferences: ReminderPreferences, from now: Date) async throws(CoreError) -> [ScheduledReminder] {
        var reminders: [ScheduledReminder] = []
        for delivery in deliveries(at: preferences, after: now) {
            let counts = try await StudyCounts.at(delivery, in: store)
            guard let body = ReminderText.body(for: counts) else { continue }
            reminders.append(ScheduledReminder(
                identifier: ScheduledReminder.identifierPrefix + Self.dayFormat.string(from: delivery),
                delivery: delivery,
                title: ReminderText.title,
                body: body
            ))
        }
        return reminders
    }

    /// The next `days` moments at the chosen time of day, the first one after
    /// `now`.
    private func deliveries(at preferences: ReminderPreferences, after now: Date) -> [Date] {
        let time = DateComponents(hour: preferences.hour, minute: preferences.minute)
        var moments: [Date] = []
        var after = now
        while moments.count < days,
              let next = calendar.nextDate(after: after, matching: time, matchingPolicy: .nextTime) {
            moments.append(next)
            after = next
        }
        return moments
    }

    private static let dayFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format
    }()
}

/// How many cards there are to study at a given moment, over the whole
/// collection, after each deck's daily limits.
struct StudyCounts: Equatable {
    /// Cards due: review cards and learning cards.
    var due = 0
    var new = 0

    /// Asks the core for the deck tree as it will be at `moment`. The core
    /// computes the counts for the day `moment` falls in (by the collection's
    /// own day boundary), so cards due on later days and fresh daily limits
    /// are counted then.
    static func at(_ moment: Date, in store: CollectionStore) async throws(CoreError) -> StudyCounts {
        let root = try await store.core.deckTree(.with { $0.now = Int64(moment.timeIntervalSince1970) })
        // Each top-level deck's counts already include its child decks.
        return root.children.reduce(into: StudyCounts()) { counts, deck in
            counts.due += Int(deck.reviewCount + deck.learnCount)
            counts.new += Int(deck.newCount)
        }
    }
}
