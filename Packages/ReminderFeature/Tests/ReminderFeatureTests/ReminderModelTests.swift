import CollectionStore
import CollectionTesting
import Foundation
@testable import ReminderFeature
import Testing

@MainActor
@Suite("Daily reminder", .timeLimit(.minutes(1)))
struct ReminderModelTests {
    @Test("Turning the reminder on schedules it daily at the chosen time, saying how many cards are due")
    func turningOn() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.makeDueToday(store.addBasicNotes(count: 3, toDeck: spanish))
            let centre = RecordingNotificationCentre()
            let model = ReminderModel(store: store, centre: centre, defaults: .throwaway())

            let inAnHour = Date.now.addingTimeInterval(3600)
            await model.setTime(inAnHour)
            await model.setOn(true)

            #expect(model.isOn)
            #expect(await centre.permissionRequests == 1)
            let reminders = await centre.pendingReminders()
            let first = try #require(reminders.first)
            #expect(first.delivery.isSameMinute(as: inAnHour))
            #expect(first.title == "Time to Study")
            #expect(first.body == "3 cards are due.")
            // One for each of the following days too, at the same time.
            #expect(reminders.count > 1)
            for (earlier, later) in zip(reminders, reminders.dropFirst()) {
                #expect(Calendar.current.dateComponents([.day], from: earlier.delivery, to: later.delivery).day == 1)
                #expect(later.delivery.hourAndMinute == inAnHour.hourAndMinute)
            }
        }
    }

    @Test("When the chosen time has passed today, the first reminder comes tomorrow")
    func timePassedToday() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.makeDueToday(store.addBasicNotes(count: 1, toDeck: spanish))
            let centre = RecordingNotificationCentre()
            let model = ReminderModel(store: store, centre: centre, defaults: .throwaway())

            let anHourAgo = Date.now.addingTimeInterval(-3600)
            await model.setTime(anHourAgo)
            await model.setOn(true)

            let first = try #require(await centre.pendingReminders().first)
            #expect(first.delivery.isSameMinute(as: anHourAgo.addingTimeInterval(24 * 3600)))
            #expect(first.body == "1 card is due.")
            #expect(model.nextReminder == first)
        }
    }

    @Test("A refusal of permission keeps the reminder off and explains how to allow it")
    func permissionRefused() async throws {
        try await withTemporaryCollection { store in
            try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: store.addDeck(named: "Spanish")))
            let centre = RecordingNotificationCentre(learnerAllows: false)
            let defaults = UserDefaults.throwaway()
            let model = ReminderModel(store: store, centre: centre, defaults: defaults)

            await model.setOn(true)

            #expect(!model.isOn)
            #expect(model.notificationsRefused)
            #expect(await centre.pendingReminders().isEmpty)
            // Seen again later, the screen still shows it off.
            #expect(!ReminderModel(store: store, centre: centre, defaults: defaults).isOn)

            // The learner allows notifications in the Settings app and comes back.
            centre.learnerChangesPermission(to: .allowed)
            await model.refreshPermission()
            #expect(!model.notificationsRefused)
            await model.setOn(true)
            #expect(model.isOn)
            #expect(await centre.pendingReminders().first?.body == "2 cards are due.")
        }
    }

    @Test("Choosing another time moves every reminder to it")
    func changingTime() async throws {
        try await withTemporaryCollection { store in
            try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: store.addDeck(named: "Spanish")))
            let centre = RecordingNotificationCentre()
            let model = ReminderModel(store: store, centre: centre, defaults: .throwaway())
            await model.setTime(Date.now.addingTimeInterval(3600))
            await model.setOn(true)
            let before = await centre.pendingReminders()

            let inTwoHours = Date.now.addingTimeInterval(2 * 3600)
            await model.setTime(inTwoHours)

            let after = await centre.pendingReminders()
            #expect(after.count == before.count)
            #expect(after.allSatisfy { $0.delivery.hourAndMinute == inTwoHours.hourAndMinute })
            #expect(after.first?.delivery.isSameMinute(as: inTwoHours) == true)
            #expect(after.first?.body == "2 cards are due.")
        }
    }

    @Test("Turning the reminder off removes every pending reminder")
    func turningOff() async throws {
        try await withTemporaryCollection { store in
            try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: store.addDeck(named: "Spanish")))
            let centre = RecordingNotificationCentre()
            let defaults = UserDefaults.throwaway()
            let model = ReminderModel(store: store, centre: centre, defaults: defaults)
            await model.setOn(true)
            #expect(await !centre.pendingReminders().isEmpty)

            await model.setOn(false)

            #expect(!model.isOn)
            #expect(model.nextReminder == nil)
            #expect(await centre.pendingReminders().isEmpty)

            // Nothing comes back when the collection changes or the app
            // returns to the foreground.
            let schedule = ReminderSchedule(store: store, centre: centre, defaults: defaults)
            try await store.makeDueToday(store.addBasicNotes(count: 1, toDeck: store.addDeck(named: "French")))
            await schedule.update()
            #expect(await centre.pendingReminders().isEmpty)
        }
    }

    @Test("The reminders count new cards within the daily limit, and a day with nothing to study has none")
    func newCardsAndEmptyDays() async throws {
        try await withTemporaryCollection { store in
            let centre = RecordingNotificationCentre()
            let model = ReminderModel(store: store, centre: centre, defaults: .throwaway())
            await model.setOn(true)
            #expect(model.isOn)
            #expect(await centre.pendingReminders().isEmpty, "an empty collection has nothing to study")

            // 25 new cards; the default preset introduces 20 a day.
            try await store.addBasicNotes(count: 25, toDeck: store.addDeck(named: "Spanish"))
            await model.setOn(true)

            let bodies = await centre.pendingReminders().map(\.body)
            #expect(bodies.first == "20 new cards are ready to learn.")
        }
    }

    @Test("Each day's reminder counts the cards that will be due that day")
    func laterDaysCountCardsFallingDue() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: spanish))
            try await store.makeDue(inDays: 3, store.addBasicNotes(count: 1, toDeck: spanish))
            let centre = RecordingNotificationCentre()
            let model = ReminderModel(store: store, centre: centre, defaults: .throwaway())

            await model.setOn(true)

            // Days before the third card falls due say 2; from then on, 3.
            let bodies = await centre.pendingReminders().map(\.body)
            #expect(bodies.first == "2 cards are due.")
            #expect(bodies.last == "3 cards are due.")
            #expect(bodies == bodies.sorted(), "the count never goes down while nothing is studied")
            #expect(bodies.filter { $0 == "2 cards are due." }.count >= 2)
        }
    }

    @Test("Studying updates what the reminders say")
    func studyingUpdatesTheCount() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.makeDueToday(store.addBasicNotes(count: 3, toDeck: spanish))
            let centre = RecordingNotificationCentre()
            let defaults = UserDefaults.throwaway()
            let model = ReminderModel(store: store, centre: centre, defaults: defaults)
            await model.setTime(Date.now.addingTimeInterval(3600))
            await model.setOn(true)
            #expect(await centre.pendingReminders().first?.body == "3 cards are due.")

            // The app keeps the reminders current while it runs.
            let schedule = ReminderSchedule(store: store, centre: centre, defaults: defaults)
            let app = Task { await schedule.keepCurrent(settling: .zero) }
            defer { app.cancel() }

            try await store.answerNextCard(inDeck: spanish, rating: .easy)
            try await eventually("the reminder counts one card fewer") {
                centre.snapshot.first?.body == "2 cards are due."
            }
        }
    }

    @Test("The reminder's choices are kept for the next time")
    func choicesPersist() async throws {
        try await withTemporaryCollection { store in
            let centre = RecordingNotificationCentre()
            let defaults = UserDefaults.throwaway()
            let model = ReminderModel(store: store, centre: centre, defaults: defaults)
            #expect(!model.isOn)
            let evening = try #require(Calendar.current.date(bySettingHour: 20, minute: 30, second: 0, of: .now))
            await model.setTime(evening)
            await model.setOn(true)

            let later = ReminderModel(store: store, centre: centre, defaults: defaults)
            #expect(later.isOn)
            #expect(later.time.hourAndMinute == evening.hourAndMinute)
        }
    }

    @Test("Opening a reminder asks for the deck list; other notifications do not")
    func openingAReminder() async throws {
        try await withTemporaryCollection { store in
            try await store.makeDueToday(store.addBasicNotes(count: 1, toDeck: store.addDeck(named: "Spanish")))
            let centre = RecordingNotificationCentre()
            let model = ReminderModel(store: store, centre: centre, defaults: .throwaway())
            await model.setOn(true)
            let reminder = try #require(await centre.pendingReminders().first)

            let opener = ReminderOpener()
            opener.opened(notificationIdentifier: "something.else")
            #expect(!opener.deckListRequested)
            opener.opened(notificationIdentifier: reminder.identifier)
            #expect(opener.deckListRequested)
        }
    }
}

extension UserDefaults {
    /// Empty defaults of their own, so tests never read or change the app's.
    static func throwaway() -> UserDefaults {
        let name = "hayaki-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

extension Date {
    var hourAndMinute: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: self)
    }

    func isSameMinute(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .minute)
    }
}

@MainActor
@Test("A deck reminder counts only its deck and carries the profile and deck on launch")
func deckReminderOpensItsDeck() async throws {
    try await withTemporaryCollection { store in
        let target = try await store.addDeck(named: "Spanish")
        let other = try await store.addDeck(named: "Japanese")
        try await store.makeDueToday(store.addBasicNotes(count: 2, toDeck: target))
        try await store.makeDueToday(store.addBasicNotes(count: 4, toDeck: other))
        let centre = RecordingNotificationCentre()
        let defaults = UserDefaults.throwaway()
        let profile = UUID()
        let model = DeckReminderModel(store: store, profileID: profile, centre: centre, defaults: defaults)
        let time = Calendar.current.dateComponents([.hour, .minute], from: .now.addingTimeInterval(3600))
        let rule = DeckReminder(deckID: target, hour: try #require(time.hour), minute: try #require(time.minute))

        await model.save(rule)

        let reminder = try #require(await centre.pendingReminders().first)
        #expect(reminder.title == "Spanish")
        #expect(reminder.body == "2 cards are due.")
        let opener = ReminderOpener()
        opener.opened(notificationIdentifier: reminder.identifier)
        #expect(opener.deckRequested?.profileID == profile)
        #expect(opener.deckRequested?.deckID == target)

        await model.delete(rule.id)
        #expect(await centre.pendingReminders().isEmpty)
    }
}


@MainActor
@Test("A denied deck reminder is kept, then scheduled with its threshold when permission is allowed")
func deniedDeckReminderAndThreshold() async throws {
    try await withTemporaryCollection { store in
        let deck = try await store.addDeck(named: "Spanish")
        try await store.addBasicNotes(count: 3, toDeck: deck)
        let centre = RecordingNotificationCentre(learnerAllows: false)
        let defaults = UserDefaults.throwaway()
        let profile = UUID()
        let model = DeckReminderModel(store: store, profileID: profile, centre: centre, defaults: defaults)
        let time = Date.now.addingTimeInterval(3600).hourAndMinute
        var rule = DeckReminder(deckID: deck, hour: try #require(time.hour), minute: try #require(time.minute))
        rule.minimumCards = 2
        rule.countNew = false

        await model.save(rule)
        #expect(model.notificationsRefused)
        #expect(await centre.pendingReminders().isEmpty)
        #expect(DeckReminderModel(store: store, profileID: profile, centre: centre, defaults: defaults).rules == [rule])

        centre.learnerChangesPermission(to: .allowed)
        await model.refresh()
        #expect(!model.notificationsRefused)
        await model.save(rule)
        #expect(await centre.pendingReminders().isEmpty, "excluded new cards do not contribute toward the minimum")

        rule.countNew = true
        await model.save(rule)
        let first = try #require(await centre.pendingReminders().first)
        #expect(first.body == "3 new cards are ready to learn.")
    }
}

@MainActor
@Test("A snooze keeps the reminder's destination and disappears when the reminder is deleted")
func snoozingDeckReminder() async throws {
    try await withTemporaryCollection { store in
        let deck = try await store.addDeck(named: "Japanese")
        try await store.addBasicNotes(count: 2, toDeck: deck)
        let centre = RecordingNotificationCentre(permission: .allowed)
        let defaults = UserDefaults.throwaway()
        let profile = UUID()
        let model = DeckReminderModel(store: store, profileID: profile, centre: centre, defaults: defaults)
        let time = Date.now.addingTimeInterval(3600).hourAndMinute
        let rule = DeckReminder(deckID: deck, hour: try #require(time.hour), minute: try #require(time.minute))
        await model.save(rule)
        let reminder = try #require(await centre.pendingReminders().first)
        let target = try #require(DeckReminderDestination(identifier: reminder.identifier))
        let beforeSnooze = Date.now

        await DeckReminderActions.snooze(.fiveMinutes, target: target, title: reminder.title, body: reminder.body, in: centre)

        let snoozed = try #require(await centre.pendingReminders().first)
        let opener = ReminderOpener()
        opener.opened(notificationIdentifier: snoozed.identifier)
        #expect(opener.deckRequested?.profileID == profile)
        #expect(opener.deckRequested?.deckID == deck)
        #expect(abs(snoozed.delivery.timeIntervalSince(beforeSnooze) - 300) < 5)

        await model.save(rule)
        #expect(await centre.pendingReminders().contains(snoozed))
        await model.delete(rule.id)
        #expect(await centre.pendingReminders().isEmpty)
    }
}
