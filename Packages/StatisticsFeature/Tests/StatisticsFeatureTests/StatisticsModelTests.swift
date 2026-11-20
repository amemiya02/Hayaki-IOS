import CollectionStore
import CollectionTesting
import Foundation
import StatisticsFeature
import Testing

@MainActor
@Suite("Statistics", .timeLimit(.minutes(1)))
struct StatisticsModelTests {
    @Test("An empty collection has nothing to chart and no decks to choose")
    func emptyCollection() async throws {
        try await withTemporaryCollection { store in
            let model = StatisticsModel(store: store)
            await model.refresh()

            #expect(model.state == .loaded)
            #expect(model.decks.isEmpty)
            let graphs = try #require(model.graphs)
            #expect(graphs.today.isEmpty)
            #expect(graphs.cardCounts.isEmpty)
            #expect(graphs.ratings.isEmpty)
        }
    }

    @Test("Today's summary counts today's reviews, their time, Again ratings and mature cards")
    func todaySummary() async throws {
        try await withTemporaryCollection { store in
            try await store.addSpanishWithKnownHistory()
            let model = StatisticsModel(store: store)
            await model.refresh()

            let today = try #require(model.graphs?.today)
            #expect(today.reviews == 3)
            #expect(today.time == .seconds(9))
            #expect(today.averageTime == .seconds(3))
            #expect(today.againCount == 1)
            #expect(today.correctFraction.map { ($0 * 100).rounded() } == 67)
            #expect(today.learningReviews == 1)
            #expect(today.reviewReviews == 2)
            #expect(today.relearningReviews == 0)
            #expect(today.filteredReviews == 0)
            #expect(today.matureReviews == 1)
            #expect(today.matureCorrect == 1)
        }
    }

    @Test("Review counts and study time follow the period and deck, and feed the calendar")
    func dailyReviews() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addSpanishWithKnownHistory()
            let spanishHistory = try await store.addBasicNotes(count: 1, toDeck: spanish)
            try await store.makeReviewCardsDueToday(spanishHistory, intervalDays: 40)
            try await store.review(spanishHistory[0], rating: .good, daysAgo: 37, seconds: 11)

            let other = try await store.addDeck(named: "Other")
            let otherCards = try await store.addBasicNotes(count: 1, toDeck: other)
            try await store.review(otherCards[0], rating: .good, daysAgo: 2, seconds: 7)

            let model = StatisticsModel(store: store)
            await model.refresh()
            let all = try #require(model.graphs)
            #expect(all.reviewDays.map(\.offset) == [-2, 0])
            #expect(all.reviewDays.map(\.count) == [1, 3])
            #expect(all.reviewDays.map(\.milliseconds) == [7_000, 9_000])

            model.scope = .deck(id: spanish)
            model.period = .threeMonths
            await model.refresh()
            let deck = try #require(model.graphs)
            #expect(deck.reviewDays.map(\.offset) == [-37, 0])
            #expect(deck.reviewDays.map(\.count) == [1, 3])
            #expect(deck.reviewDays.map(\.milliseconds) == [11_000, 9_000])
            #expect(deck.reviewDays.last?.entries.map(\.count) == [1, 0, 1, 1, 0])
        }
    }

    @Test("Forecast filters scheduled days and overdue cards, and calendar uses the same study days as reviews")
    func forecastAndCalendar() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let spanishCards = try await store.addBasicNotes(count: 6, toDeck: spanish)
            try await store.review(spanishCards[0], rating: .again, daysAgo: 2)
            try await store.makeDue(inDays: 1, [spanishCards[1]])
            try await store.makeDue(inDays: 45, [spanishCards[2]])
            try await store.makeOverdue(byDays: 2, [spanishCards[3]])
            try await store.makeDue(inDays: 4, [spanishCards[4]])
            try await store.suspend([spanishCards[4]])
            try await store.review(spanishCards[5], rating: .good)
            try await store.makeDue(inDays: 7, [spanishCards[0], spanishCards[5]])
            let other = try await store.addDeck(named: "Other")
            let otherCards = try await store.addBasicNotes(count: 1, toDeck: other)
            try await store.makeDue(inDays: 1, otherCards)

            let model = StatisticsModel(store: store)
            await model.refresh()
            #expect(model.graphs?.forecast().tomorrow == 2)

            model.scope = .deck(id: spanish)
            await model.refresh()
            let month = try #require(model.graphs)
            #expect(month.forecast().days.map(\.offset) == [1, 7])
            #expect(month.forecast().days.map(\.count) == [1, 2])
            #expect(month.forecast().hasBacklog)
            #expect(month.forecast(includeBacklog: true).days.map(\.offset) == [-2, 1, 7])
            #expect(month.forecast(includeBacklog: true).total == 4)

            let calendar = Calendar.statisticsCalendar
            let timing = try await store.core.schedTimingToday()
            let cutoff = Date(timeIntervalSince1970: TimeInterval(timing.nextDayAt))
            let expectedToday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: cutoff))
            let expectedEarlier = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: cutoff))
            #expect(month.activityDays().map(\.date) == [expectedEarlier, expectedToday].compactMap { $0 })
            #expect(month.activityDays().map(\.count) == [1, 1])
            let years = Set(month.activityDays().map { calendar.component(.year, from: $0.date) })
            let heatMapReviews = years.reduce(0) { total, year in
                total + month.calendarHeatMap(year: year, firstWeekday: .monday).totalReviews
            }
            #expect(heatMapReviews == month.reviewDays.reduce(0) { $0 + $1.count })

            model.period = .threeMonths
            await model.refresh()
            #expect(model.graphs?.forecast().days.map(\.offset) == [1, 7, 45])
        }
    }

    @Test("Scheduling charts use interval, hourly, added and true retention data from the collection")
    func schedulingCharts() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addSpanishWithKnownHistory()
            let cards = try await store.addBasicNotes(count: 2, toDeck: spanish)
            try await store.makeReviewCardsDueToday([cards[0]], intervalDays: 10)
            try await store.makeReviewCardsDueToday([cards[1]], intervalDays: 40)

            let model = StatisticsModel(store: store)
            model.scope = .deck(id: spanish)
            await model.refresh()
            let stats = try #require(model.graphs)

            #expect(stats.addedDays.map(\.offset) == [0])
            #expect(stats.addedDays.map(\.count) == [9])
            #expect(stats.hourlyReviews.count == 24)
            #expect(stats.hourlyReviews.reduce(0) { $0 + $1.count } == 3)
            #expect(stats.hourlyReviews.reduce(0) { $0 + $1.correct } == 2)
            let today = try #require(stats.trueRetention.first { $0.window == .today })
            #expect(today.young.passed == 1)
            #expect(today.young.failed == 0)
            #expect(today.mature.passed == 1)
            #expect(today.mature.failed == 0)
            #expect(today.combined.rate == 1)
            #expect(stats.distributions.map(\.kind) == [.intervals, .ease])
            let intervals = try #require(stats.distributions.first)
            #expect(intervals.total == 4)
            #expect(intervals.buckets.contains { $0.value == 10 && $0.count >= 1 })
            #expect(intervals.buckets.contains { $0.value == 40 && $0.count >= 1 })
        }
    }

    @Test("FSRS replaces ease with stability, difficulty and retrievability distributions")
    func fsrsDistributions() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "FSRS")
            let cards = try await store.addBasicNotes(count: 2, toDeck: deck)
            try await store.makeReviewCardsDueToday([cards[0]], intervalDays: 5)
            try await store.modify(.setConfigJson(.with {
                $0.key = "fsrs"
                $0.valueJson = Data("true".utf8)
            }))
            var card = try await store.core.getCard(.with { $0.cid = cards[0] })
            card.memoryState = .with {
                $0.stability = 9
                $0.difficulty = 5.5
            }
            let reviewedCard = card
            try await store.modify(.updateCards(.with { $0.cards = [reviewedCard] }))

            let model = StatisticsModel(store: store)
            model.scope = .deck(id: deck)
            await model.refresh()
            let graphs = try #require(model.graphs)
            #expect(graphs.distributions.map(\.kind) == [.intervals, .stability, .difficulty, .retrievability])
            let stability = try #require(graphs.distributions.first { $0.kind == .stability })
            #expect(stability.buckets.map(\.value) == [9])
            #expect(stability.buckets.map(\.count) == [1])
            let difficulty = try #require(graphs.distributions.first { $0.kind == .difficulty })
            #expect(difficulty.buckets.map(\.value) == [50])
            #expect(difficulty.typicalValue == 50)
            let retrievability = try #require(graphs.distributions.first { $0.kind == .retrievability })
            #expect(retrievability.total == 1)
            #expect(retrievability.estimatedRememberedCards == retrievability.estimatedRememberedNotes)
            let remembered = try #require(retrievability.estimatedRememberedCards)
            #expect(remembered > 0 && remembered <= 1)
        }
    }

    @Test("Anki search expressions filter charts and can be corrected after an error")
    func searchScope() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Languages::Spanish")
            let cards = try await store.addBasicNotes(count: 2, toDeck: deck)
            let tagged = try await store.core.getCard(.with { $0.cid = cards[0] }).noteID
            try await store.modify(.addNoteTags(.with { $0.noteIds = [tagged]; $0.tags = "included" }))
            try await store.review(cards[0], rating: .good)

            let model = StatisticsModel(store: store)
            model.scope = .search(#"deck:"Languages::Spanish" tag:included"#)
            await model.refresh()
            #expect(model.graphs?.cardCounts.total == 1)
            #expect(model.graphs?.reviewDays.map(\.count) == [1])

            model.scope = .search("(")
            await model.refresh()
            guard case .failed = model.state else {
                Issue.record("A malformed search should show an error")
                return
            }
            model.scope = .deck(id: deck)
            await model.refresh()
            #expect(model.state == .loaded)
            #expect(model.graphs?.cardCounts.total == 2)
        }
    }

    @Test("Calendar weekday, inactive cards and forecast backlog preferences are saved in the collection")
    func chartPreferences() async throws {
        try await withTemporaryCollection { store in
            try await store.addSpanishWithKnownHistory()
            let model = StatisticsModel(store: store)
            await model.refresh()
            #expect(model.graphs?.cardCounts.count(.suspended) == 1)

            await model.setPreference(.firstWeekday(.friday))
            await model.setPreference(.includeBacklog(false))
            await model.setPreference(.separateInactive(false))

            let reopened = StatisticsModel(store: store)
            await reopened.refresh()
            #expect(reopened.preferences.firstWeekday == .friday)
            #expect(reopened.preferences.includeBacklog == false)
            #expect(reopened.preferences.separateInactive == false)
            let combined = try #require(reopened.graphs?.cardCounts(separateInactive: false))
            #expect(combined.count(.new) == 4)
            #expect(combined.count(.suspended) == 0)
            #expect(combined.count(.buried) == 0)
            #expect(combined.total == 7)
        }
    }

    @Test("Card counts divide the cards between new, learning, young, mature, suspended and buried")
    func cardCounts() async throws {
        try await withTemporaryCollection { store in
            try await store.addSpanishWithKnownHistory()
            let model = StatisticsModel(store: store)
            await model.refresh()

            let counts = try #require(model.graphs?.cardCounts)
            #expect(counts.summary == [
                "New: 2", "Learning: 1", "Relearning: 0", "Young: 1", "Mature: 1", "Suspended: 1", "Buried: 1",
            ])
            #expect(counts.total == 7)
            #expect(counts.fraction(.new) == 2.0 / 7.0)
        }
    }

    @Test("Ratings count how often each rating was chosen, by the kind of card reviewed")
    func ratings() async throws {
        try await withTemporaryCollection { store in
            try await store.addSpanishWithKnownHistory()
            let model = StatisticsModel(store: store)
            await model.refresh()

            let ratings = try #require(model.graphs?.ratings)
            #expect(ratings.summary == [
                "Learning: Again 1, Hard 0, Good 0, Easy 0",
                "Young: Again 0, Hard 1, Good 0, Easy 0",
                "Mature: Again 0, Hard 0, Good 1, Easy 0",
            ])
            #expect(ratings.count(.again) == 1)
            #expect(ratings.total == 3)
            #expect(ratings.fraction(.good) == 1.0 / 3.0)
            #expect(ratings.correctFraction(of: .learning) == 0)
            #expect(ratings.correctFraction(of: .mature) == 1)
        }
    }

    @Test("Choosing a period counts only the ratings chosen in it")
    func periods() async throws {
        try await withTemporaryCollection { store in
            // Three mature cards, each reviewed once: 45, 200 and 400 days ago.
            let history = try await store.addDeck(named: "History")
            let cards = try await store.addBasicNotes(count: 3, toDeck: history)
            try await store.makeReviewCardsDueToday(cards, intervalDays: 40)
            try await store.review(cards[0], rating: .easy, daysAgo: 45)
            try await store.review(cards[1], rating: .hard, daysAgo: 200)
            try await store.review(cards[2], rating: .again, daysAgo: 400)

            let model = StatisticsModel(store: store)
            var shown: [StatisticsPeriod: [String]] = [:]
            for period in StatisticsPeriod.allCases {
                model.period = period
                await model.refresh()
                shown[period] = model.graphs?.ratings.ratingTotals
            }

            #expect(shown[.month] == ["Again 0", "Hard 0", "Good 0", "Easy 0"])
            #expect(shown[.threeMonths] == ["Again 0", "Hard 0", "Good 0", "Easy 1"])
            #expect(shown[.year] == ["Again 0", "Hard 1", "Good 0", "Easy 1"])
            #expect(shown[.allTime] == ["Again 1", "Hard 1", "Good 0", "Easy 1"])
            // Nothing was studied today, whatever the period.
            #expect(model.graphs?.today.isEmpty == true)
        }
    }

    @Test("Choosing a deck shows only its cards and reviews, including its child decks'")
    func deckScope() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Languages::Spanish")
            let geography = try await store.addDeck(named: "Geography")
            try await store.addBasicNotes(count: 3, toDeck: spanish)
            try await store.addBasicNotes(count: 2, toDeck: geography)
            try await store.answerNextCard(inDeck: spanish, rating: .good)
            try await store.answerNextCard(inDeck: geography, rating: .again)
            try await store.answerNextCard(inDeck: geography, rating: .again)
            let languages = try await store.deckID(named: "Languages")

            let model = StatisticsModel(store: store)
            await model.refresh()
            #expect(model.decks.map(\.displayName) == ["Geography", "Languages", "Languages › Spanish"])
            #expect(model.graphs?.cardCounts.total == 5)
            #expect(model.graphs?.today.reviews == 3)
            #expect(model.graphs?.ratings.ratingTotals == ["Again 2", "Hard 0", "Good 1", "Easy 0"])

            model.scope = .deck(id: languages)
            await model.refresh()
            #expect(model.graphs?.cardCounts.total == 3)
            #expect(model.graphs?.today.reviews == 1)
            #expect(model.graphs?.ratings.ratingTotals == ["Again 0", "Hard 0", "Good 1", "Easy 0"])

            model.scope = .deck(id: geography)
            await model.refresh()
            #expect(model.graphs?.cardCounts.total == 2)
            #expect(model.graphs?.today.reviews == 2)
            #expect(model.graphs?.ratings.ratingTotals == ["Again 2", "Hard 0", "Good 0", "Easy 0"])
        }
    }

    @Test("A deck with cards but no reviews has card counts and nothing else")
    func deckWithoutReviews() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            let geography = try await store.addDeck(named: "Geography")
            try await store.addBasicNotes(count: 2, toDeck: spanish)
            try await store.addBasicNotes(count: 1, toDeck: geography)
            try await store.answerNextCard(inDeck: geography, rating: .good)

            let model = StatisticsModel(store: store)
            model.scope = .deck(id: spanish)
            await model.refresh()

            let graphs = try #require(model.graphs)
            #expect(graphs.today.isEmpty)
            #expect(graphs.ratings.isEmpty)
            #expect(graphs.cardCounts.summary.first == "New: 2")
            #expect(graphs.cardCounts.total == 2)
        }
    }

    @Test("The study streak counts consecutive days with reviews, up to today or yesterday")
    func studyStreak() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Streak")
            let cards = try await store.addBasicNotes(count: 4, toDeck: deck)
            try await store.makeReviewCardsDueToday(cards, intervalDays: 10)
            try await store.review(cards[0], rating: .good, daysAgo: 1, seconds: 5)
            try await store.review(cards[1], rating: .good, daysAgo: 2, seconds: 5)
            try await store.review(cards[2], rating: .good, daysAgo: 4, seconds: 5)

            let model = StatisticsModel(store: store)
            await model.refresh()
            // Not studied yet today: the streak still runs through yesterday.
            #expect(model.graphs?.studyStreak == StudyStreak(days: 2, isAtLeast: false))

            try await store.review(cards[3], rating: .good)
            await model.refresh()
            #expect(model.graphs?.studyStreak == StudyStreak(days: 3, isAtLeast: false))
        }
    }

    @Test("A streak that reaches the start of the period is shown as at least that long")
    func studyStreakBeyondPeriod() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Streak")
            let cards = try await store.addBasicNotes(count: 35, toDeck: deck)
            try await store.makeReviewCardsDueToday(cards, intervalDays: 60)
            for (daysAgo, card) in cards.enumerated() {
                try await store.review(card, rating: .good, daysAgo: daysAgo, seconds: 2)
            }

            let model = StatisticsModel(store: store)
            model.period = .month
            await model.refresh()
            let month = try #require(model.graphs?.studyStreak)
            #expect(month.isAtLeast)
            #expect(month.days == 31)

            model.period = .allTime
            await model.refresh()
            #expect(model.graphs?.studyStreak == StudyStreak(days: 35, isAtLeast: false))
        }
    }

    @Test("While shown, the statistics update after studying, and a deleted deck falls back to the whole collection")
    func refreshesAfterChanges() async throws {
        try await withTemporaryCollection { store in
            let spanish = try await store.addDeck(named: "Spanish")
            try await store.addBasicNotes(count: 2, toDeck: spanish)
            try await store.addBasicNotes(count: 1, toDeck: store.addDeck(named: "Geography"))

            let model = StatisticsModel(store: store)
            model.scope = .deck(id: spanish)
            let shown = Task { await model.run() }
            defer { shown.cancel() }
            try await eventually("the statistics loaded") { model.graphs?.cardCounts.total == 2 }

            try await store.answerNextCard(inDeck: spanish, rating: .again)
            try await eventually("the review shown") {
                model.graphs?.today.reviews == 1 && model.graphs?.ratings.count(.again) == 1
            }

            try await store.modify(.removeDecks(.with { $0.dids = [spanish] }))
            try await eventually("the whole collection shown") {
                model.scope == .collection && model.graphs?.cardCounts.total == 1
            }
            #expect(model.decks.map(\.displayName) == ["Geography"])
        }
    }
}

extension CollectionStore {
    /// A "Spanish" deck with a known history, all of it from today:
    /// - two cards never studied;
    /// - a new card rated Again, so now in learning;
    /// - a young card (interval 5 days) rated Hard;
    /// - a mature card (interval 40 days) rated Good;
    /// - a suspended card and a buried card, never studied.
    /// Each review took 3 seconds.
    @discardableResult
    func addSpanishWithKnownHistory() async throws -> Int64 {
        let spanish = try await addDeck(named: "Spanish")
        let cards = try await addBasicNotes(count: 7, toDeck: spanish)
        try await makeReviewCardsDueToday([cards[3]], intervalDays: 5)
        try await makeReviewCardsDueToday([cards[4]], intervalDays: 40)
        try await suspend([cards[5]])
        try await bury([cards[6]])
        try await review(cards[2], rating: .again)
        try await review(cards[3], rating: .hard)
        try await review(cards[4], rating: .good)
        return spanish
    }
}

extension CardCounts {
    /// The counts as a learner reads them, one line per state.
    var summary: [String] {
        entries.map { "\($0.state.title): \($0.count)" }
    }
}

extension RatingCounts {
    /// One line per kind of card, with the count for each rating.
    var summary: [String] {
        ReviewedCardKind.allCases.map { kind in
            "\(kind.title): " + Rating.allCases.map { "\($0.title) \(count($0, for: kind))" }.joined(separator: ", ")
        }
    }

    /// How often each rating was chosen, over every kind of card.
    var ratingTotals: [String] {
        Rating.allCases.map { "\($0.title) \(count($0))" }
    }
}
