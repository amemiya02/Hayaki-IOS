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
    private let profileID: UUID?

    /// Updates run one after another, across every schedule in the app, so a
    /// slower update can never re-add reminders a later one removed.
    private static var lastUpdate: Task<Void, Never>?

    public init(
        store: CollectionStore,
        centre: any NotificationCentre,
        defaults: UserDefaults = .standard,
        days: Int = ReminderSchedule.defaultDays,
        calendar: Calendar = .current,
        profileID: UUID? = nil
    ) {
        self.store = store
        self.centre = centre
        self.defaults = defaults
        self.days = days
        self.calendar = calendar
        self.profileID = profileID
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
        guard store.allowsNewProfileWork else { return }
        let preferences = ReminderPreferences(from: defaults)
        let pending = await centre.pendingReminders()
        guard await centre.permission() == .allowed else {
            await centre.removeReminders(withIdentifiers: pending.map(\.identifier))
            return
        }

        let wanted: [ScheduledReminder]
        do {
            wanted = try await reminders(for: preferences, from: .now)
        } catch {
            // The collection may be changing during sync or import.
            return
        }
        guard store.allowsNewProfileWork else { return }

        let retained = pending.filter { reminder in
            guard let target = DeckReminderDestination(identifier: reminder.identifier) else { return false }
            return target.profileID != profileID
        }
        // Keep the daily reminder's slots and give the remaining system
        // slots to the soonest deck reminders across all profiles.
        let combined = wanted + retained
        let daily = combined.filter { !$0.identifier.hasPrefix(DeckReminderDestination.prefix) }
        let decks = combined.filter { $0.identifier.hasPrefix(DeckReminderDestination.prefix) }
            .sorted { ($0.delivery, $0.identifier) < ($1.delivery, $1.identifier) }
        let selection = Array(daily.prefix(64)) + Array(decks.prefix(max(0, 64 - daily.count)))
        let selectedIDs = Set(selection.map(\.identifier))
        await centre.removeReminders(withIdentifiers: pending.map(\.identifier).filter { !selectedIDs.contains($0) })
        let previous = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        for reminder in selection where previous[reminder.identifier] != reminder {
            try? await centre.add(reminder)
        }
    }

    private func reminders(for preferences: ReminderPreferences, from now: Date) async throws(CoreError) -> [ScheduledReminder] {
        var deliveries: [Date: [DeckReminder]] = [:]
        let daily = Set(preferences.isOn ? moments(hour: preferences.hour, minute: preferences.minute, after: now) : [])
        var reviewedToday: Set<Int64> = []
        var nextDay: Int64 = 0
        if let profileID {
            let rules = DeckReminder.load(profileID: profileID, from: defaults).filter(\.enabled)
            if !rules.isEmpty {
                let names = try await store.core.getDeckNames(.with { $0.includeFiltered = true }).entries
                let namesByID = Dictionary(uniqueKeysWithValues: names.map { ($0.id, $0.name) })
                let liveRules = rules.filter { namesByID[$0.deckID] != nil }
                for rule in liveRules {
                    for date in moments(hour: rule.hour, minute: rule.minute, after: now) {
                        deliveries[date, default: []].append(rule)
                    }
                }
                if liveRules.contains(where: \.onlyWithoutReviews) {
                    nextDay = try await store.core.schedTimingToday().nextDayAt
                    for id in Set(liveRules.filter(\.onlyWithoutReviews).map(\.deckID)) {
                        guard let name = namesByID[id] else { continue }
                        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
                            .replacingOccurrences(of: "*", with: "\\*")
                            .replacingOccurrences(of: "_", with: "\\_")
                        let search = "rated:1 \"deck:\(escaped)\""
                        if try await !store.core.searchCards(.with { $0.search = search }).ids.isEmpty {
                            reviewedToday.insert(id)
                        }
                    }
                }
            }
        }

        var reminders: [ScheduledReminder] = []
        var deckReminderCount = 0
        for date in daily.union(deliveries.keys).sorted() {
            let rules = deckReminderCount < 64 ? deliveries[date] ?? [] : []
            guard !rules.isEmpty || daily.contains(date) else { continue }
            let timestamp = Int64(date.timeIntervalSince1970)
            let root = try await store.core.deckTree(.with { $0.now = timestamp })
            let day = Self.dayFormat.string(from: date)

            if daily.contains(date), let body = ReminderText.body(for: StudyCounts.sum(root.children)) {
                reminders.append(ScheduledReminder(
                    identifier: ScheduledReminder.identifierPrefix + day,
                    delivery: date, title: ReminderText.title, body: body
                ))
            }
            guard let profileID else { continue }
            for rule in rules where deckReminderCount < 64 {
                guard !rule.onlyWithoutReviews || timestamp >= nextDay || !reviewedToday.contains(rule.deckID),
                      let deck = Self.deck(withID: rule.deckID, in: root.children)
                else { continue }
                let considered = (rule.countNew ? Int(deck.newCount) : 0)
                    + (rule.countLearning ? Int(deck.learnCount) : 0)
                    + (rule.countReview ? Int(deck.reviewCount) : 0)
                guard considered >= rule.minimumCards else { continue }
                let body = ReminderText.body(for: StudyCounts.sum([deck])) ?? ReminderText.noCards
                let identifier = DeckReminderDestination.profilePrefix(profileID) + "\(deck.deckID).\(rule.id.uuidString).\(day)"
                reminders.append(ScheduledReminder(identifier: identifier, delivery: date, title: deck.name, body: body))
                deckReminderCount += 1
            }
        }
        return reminders
    }

    private static func deck(withID id: Int64, in decks: [Anki_Decks_DeckTreeNode]) -> Anki_Decks_DeckTreeNode? {
        for deck in decks {
            if deck.deckID == id { return deck }
            if let child = self.deck(withID: id, in: deck.children) { return child }
        }
        return nil
    }

    private func moments(hour: Int, minute: Int, after now: Date) -> [Date] {
        let time = DateComponents(hour: hour, minute: minute)
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

    static func sum(_ decks: [Anki_Decks_DeckTreeNode]) -> StudyCounts {
        // Each top-level deck's counts already include its child decks.
        decks.reduce(into: StudyCounts()) { counts, deck in
            counts.due += Int(deck.reviewCount) + Int(deck.learnCount)
            counts.new += Int(deck.newCount)
        }
    }
}
