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
    private(set) var loadedSelection: Selection?
    public private(set) var preferences = StatisticsPreferences(.with {
        $0.cardCountsSeparateInactive = true
        $0.futureDueShowBacklog = true
    })
    public var preferenceError: String?

    public var scope: StatisticsScope = .collection
    public var period: StatisticsPeriod = .month
    public var selection: Selection { Selection(scope: scope, period: period) }

    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private var selectCurrentDeckOnFirstLoad: Bool
    @ObservationIgnored private var loadedRevision: UInt64?
    @ObservationIgnored private var nextStudyDay = Date.distantPast
    @ObservationIgnored private var ongoingRefresh: (
        selection: Selection, revision: UInt64, task: Task<Void, Never>
    )?
    @ObservationIgnored private var preferenceWrite: Task<Void, Never>?
    @ObservationIgnored private var preferenceVersion = 0

    /// Changes after which the statistics or the deck choices may differ.
    private static let relevantChanges: CollectionChange = [.card, .deck, .config, .deckConfig, .studyQueues, .note, .tag, .notetype, .noteText]

    public init(store: CollectionStore, selectCurrentDeckOnFirstLoad: Bool = false) {
        self.store = store
        self.selectCurrentDeckOnFirstLoad = selectCurrentDeckOnFirstLoad
    }

    /// Updates just one graph option, preserving changes made by other clients.
    public func setPreference(_ change: StatisticsPreferences.Change) async {
        let previous = preferenceWrite
        preferenceVersion += 1
        let write = Task { @MainActor [weak self, store] in
            await previous?.value
            do {
                var current = try await store.core.getGraphPreferences()
                change.apply(to: &current)
                try await store.core.setGraphPreferences(current)
                self?.preferences = StatisticsPreferences(current)
                store.signal(.config)
            } catch {
                self?.preferenceError = (error as? CoreError)?.message ?? error.localizedDescription
            }
        }
        preferenceWrite = write
        await write.value
    }

    /// Reads the decks and the graphs data for the current selection.
    public func refresh() async {
        guard !Task.isCancelled else { return }
        let requested = selection
        let revision = store.changeRevision
        if let ongoingRefresh, ongoingRefresh.selection == requested, ongoingRefresh.revision == revision {
            await ongoingRefresh.task.value
            return
        }

        // A tab switch cancels the view's task. Keep one calculation for
        // this selection so a quick return can await the same result.
        ongoingRefresh?.task.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.load(requested, revision: revision)
            if !Task.isCancelled { self.ongoingRefresh = nil }
        }
        ongoingRefresh = (requested, revision, task)
        await task.value
    }

    private func load(_ requested: Selection, revision: UInt64) async {
        guard !Task.isCancelled, requested == selection else { return }
        let preferenceVersion = self.preferenceVersion
        do {
            let decks = try await store.core.getDeckNames(.with {
                $0.skipEmptyDefault = true
                $0.includeFiltered = true
            }).entries
                .map { StatisticsDeck(id: $0.id, fullName: $0.name) }
                .sorted { $0.fullName.split(separator: "::").lexicographicallyPrecedes($1.fullName.split(separator: "::")) }

            var scope = requested.scope
            if selectCurrentDeckOnFirstLoad && scope == .collection,
               let current = try? await store.core.getCurrentDeck(),
               decks.contains(where: { $0.id == current.id }) {
                scope = .deck(id: current.id)
            }
            guard !Task.isCancelled, requested == selection else { return }
            selectCurrentDeckOnFirstLoad = false
            self.decks = decks

            // A deck that no longer exists falls back to the whole collection.
            var search = ""
            switch scope {
            case .collection:
                break
            case .deck(let id):
                if let deck = decks.first(where: { $0.id == id }) {
                    search = try await store.core.buildSearchString(.with { $0.deck = deck.fullName }).val
                } else {
                    scope = .collection
                }
            case .search(let query):
                search = query
            }
            guard !Task.isCancelled, requested == selection else { return }
            let response = try await store.core.graphs(.with {
                $0.search = search
                $0.days = requested.period.days
            })
            guard !Task.isCancelled, requested == selection else { return }

            let timing = try await store.core.schedTimingToday()
            let preferences = try await store.core.getGraphPreferences()
            let calendar = Calendar.statisticsCalendar
            let cutoff = Date(timeIntervalSince1970: TimeInterval(timing.nextDayAt))
            let today = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: cutoff)) ?? cutoff

            // A newer selection's load has taken over.
            guard !Task.isCancelled, requested == selection else { return }
            if preferenceVersion == self.preferenceVersion {
                self.preferences = StatisticsPreferences(preferences)
            }
            graphs = StatisticsGraphs(response: response, period: requested.period, studyDate: today)
            loadedRevision = revision
            loadedSelection = Selection(scope: scope, period: requested.period)
            nextStudyDay = cutoff
            state = .loaded
            if scope != self.scope { self.scope = scope }
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
        await refreshIfNeeded()
        for await change in changes where !change.isDisjoint(with: Self.relevantChanges) {
            await refreshIfNeeded()
        }
    }

    func refreshIfNeeded() async {
        if state == .loaded, loadedSelection == selection,
           loadedRevision == store.changeRevision, Date.now < nextStudyDay {
            return
        }
        await refresh()
    }
}
