import AnkiCore
import AnkiProto
import CollectionStore
import Foundation
import Observation

/// The Statistics screen: the core's graphs data for the chosen deck (or the
/// whole collection) and period, kept current while the screen is shown.
@MainActor
@Observable
public final class StatisticsModel {
    public enum State: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    /// What the statistics are shown for. Changing it and then calling
    /// `refresh()` (or restarting `run()`) loads the matching data.
    public struct Selection: Hashable, Sendable {
        public var scope: StatisticsScope
        public var period: StatisticsPeriod
    }

    public private(set) var state: State = .loading
    /// The decks the learner can choose from, parents before their children.
    public private(set) var decks: [StatisticsDeck] = []
    /// The data behind every chart for the selection last loaded.
    public private(set) var graphs: StatisticsGraphs?

    public var scope: StatisticsScope = .collection
    public var period: StatisticsPeriod = .month
    public var selection: Selection { Selection(scope: scope, period: period) }

    @ObservationIgnored private let store: CollectionStore

    /// Changes after which the statistics or the deck choices may differ.
    private static let relevantChanges: CollectionChange = [.card, .deck, .config, .deckConfig, .studyQueues]

    public init(store: CollectionStore) {
        self.store = store
    }

    /// Reads the decks and the graphs data for the current selection.
    public func refresh() async {
        let requested = selection
        do {
            let decks = try await store.core.getDeckNames(.with {
                $0.skipEmptyDefault = true
                $0.includeFiltered = true
            }).entries
                .map { StatisticsDeck(id: $0.id, fullName: $0.name) }
                .sorted { $0.fullName.split(separator: "::").lexicographicallyPrecedes($1.fullName.split(separator: "::")) }

            // A deck that no longer exists falls back to the whole collection.
            var scope = requested.scope
            var search = ""
            if case .deck(let id) = scope {
                if let deck = decks.first(where: { $0.id == id }) {
                    search = try await store.core.buildSearchString(.with { $0.deck = deck.fullName }).val
                } else {
                    scope = .collection
                }
            }
            let response = try await store.core.graphs(.with {
                $0.search = search
                $0.days = requested.period.days
            })

            let timing = try await store.core.schedTimingToday()
            let calendar = Calendar.statisticsCalendar
            let cutoff = Date(timeIntervalSince1970: TimeInterval(timing.nextDayAt))
            let today = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: cutoff)) ?? cutoff

            // A newer selection's load has taken over.
            guard !Task.isCancelled, requested == selection else { return }
            self.decks = decks
            if scope != self.scope { self.scope = scope }
            graphs = StatisticsGraphs(response: response, period: requested.period, studyDate: today)
            state = .loaded
        } catch {
            guard !Task.isCancelled, requested == selection else { return }
            state = .failed(message: error.message)
        }
    }

    /// Shows the statistics for the current selection, then keeps them
    /// current whenever the collection changes in a way that could alter
    /// them, until the calling task is cancelled. The screen runs this in a
    /// `.task` keyed on `selection`, so a new selection restarts it.
    public func run() async {
        // Subscribed before reading, so no change in between is missed.
        let changes = store.changes()
        await refresh()
        for await change in changes where !change.isDisjoint(with: Self.relevantChanges) {
            await refresh()
        }
    }
}
