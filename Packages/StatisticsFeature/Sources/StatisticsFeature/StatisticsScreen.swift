import CollectionStore
import SwiftUI

/// Native statistics for the chosen deck, collection, or Anki search.
public struct StatisticsScreen: View {
    @State private var model: StatisticsModel
    @State private var draftSearch = ""
    @State private var appliedSearch = ""

    public init(store: CollectionStore) {
        let model = StatisticsModel(store: store, selectCurrentDeckOnFirstLoad: true)
        model.period = .year
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            List {
                selectionSection
                switch model.state {
                case .loading:
                    ProgressView()
                case .failed(let message):
                    failure(message)
                case .loaded:
                    if let graphs = model.graphs {
                        charts(graphs)
                    }
                }
            }
            .navigationTitle(StatisticsSection.title)
            .refreshable { await model.refresh() }
        }
        .task(id: model.selection) { await model.run() }
        .alert(Text("Could Not Save Statistics Preference", bundle: .module), isPresented: Binding {
            model.preferenceError != nil
        } set: { visible in
            if !visible { model.preferenceError = nil }
        }) {
            Button(role: .cancel) { model.preferenceError = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(model.preferenceError ?? "")
        }
    }

    private var selectionSection: some View {
        Section {
            Picker(selection: $model.scope) {
                Text("Whole Collection", bundle: .module)
                    .tag(StatisticsScope.collection)
                ForEach(model.decks) { deck in
                    Text(deck.displayName).tag(StatisticsScope.deck(id: deck.id))
                }
                Text("Custom Search", bundle: .module).tag(StatisticsScope.search(appliedSearch))
            } label: {
                Text("Scope", bundle: .module)
            }
            if case .search = model.scope {
                TextField(text: $draftSearch, prompt: Text("Anki search expression", bundle: .module)) {
                    Text("Search", bundle: .module)
                }
                .autocorrectionDisabled()
                .onSubmit(applySearch)
                Button(action: applySearch) {
                    Text("Apply Search", bundle: .module)
                }
            }
            Picker(selection: $model.period) {
                Text("1 Year", bundle: .module).tag(StatisticsPeriod.year)
                Text("All History", bundle: .module).tag(StatisticsPeriod.allTime)
            } label: {
                Text("Review History", bundle: .module)
            }
            .pickerStyle(.segmented)
        }
    }

    private func applySearch() {
        appliedSearch = draftSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        model.scope = .search(appliedSearch)
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label {
                Text("Could Not Show Statistics", bundle: .module)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text(message)
        } actions: {
            Button {
                Task { await model.refresh() }
            } label: {
                Text("Try Again", bundle: .module)
            }
        }
    }

    @ViewBuilder
    private func charts(_ graphs: StatisticsGraphs) -> some View {
        let today = graphs.today
        let cardCounts = graphs.cardCounts(separateInactive: model.preferences.separateInactive)
        let reviews = graphs.reviewDays
        if today.isEmpty && cardCounts.isEmpty && reviews.isEmpty && graphs.ratings.isEmpty {
            Section {
                ContentUnavailableView {
                    Label {
                        Text("No Statistics Yet", bundle: .module)
                    } icon: {
                        Image(systemName: StatisticsSection.systemImage)
                    }
                } description: {
                    switch model.scope {
                    case .collection:
                        Text("Add cards and study them to see statistics here.", bundle: .module)
                    case .deck:
                        Text("This deck has no cards and no reviews yet.", bundle: .module)
                    case .search:
                        Text("No cards or reviews match this search.", bundle: .module)
                    }
                }
            }
        } else {
            TodaySection(today: today)
            ForecastSection(graphs: graphs, includeBacklog: preference(\.includeBacklog, StatisticsPreferences.Change.includeBacklog))
            CalendarSection(graphs: graphs, firstWeekday: preference(\.firstWeekday, StatisticsPreferences.Change.firstWeekday))
            ReviewHistorySection(graphs: graphs)
            CardCountsSection(counts: cardCounts, separateInactive: preference(\.separateInactive, StatisticsPreferences.Change.separateInactive))
            ForEach(graphs.distributions, id: \.kind) { distribution in
                DistributionSection(data: distribution)
            }
            TrueRetentionSection(retention: graphs.trueRetention)
            HourlySection(graphs: graphs)
            RatingsSection(graphs: graphs)
            AddedSection(graphs: graphs)
        }
    }

    private func preference<Value>(
        _ keyPath: KeyPath<StatisticsPreferences, Value>,
        _ change: @escaping (Value) -> StatisticsPreferences.Change
    ) -> Binding<Value> {
        Binding {
            model.preferences[keyPath: keyPath]
        } set: { value in
            let update = change(value)
            Task { await model.setPreference(update) }
        }
    }
}
