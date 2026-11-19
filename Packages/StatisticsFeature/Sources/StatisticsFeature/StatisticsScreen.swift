import CollectionStore
import SwiftUI

/// The Statistics section: charts of the learner's studying for one deck or
/// the whole collection, over a chosen period.
public struct StatisticsScreen: View {
    @State private var model: StatisticsModel

    public init(store: CollectionStore) {
        _model = State(initialValue: StatisticsModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(StatisticsSection.title)
        }
        // Restarted for every new deck or period, so the charts follow it.
        .task(id: model.selection) { await model.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed(let message):
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
        case .loaded:
            List {
                selectionSection
                if let graphs = model.graphs {
                    charts(graphs)
                }
            }
            .refreshable { await model.refresh() }
        }
    }

    private var selectionSection: some View {
        Section {
            Picker(selection: $model.scope) {
                Text("Whole Collection", bundle: .module)
                    .tag(StatisticsScope.collection)
                ForEach(model.decks) { deck in
                    Text(deck.displayName)
                        .tag(StatisticsScope.deck(id: deck.id))
                }
            } label: {
                Text("Deck", bundle: .module)
            }
            Picker(selection: $model.period) {
                ForEach(StatisticsPeriod.allCases, id: \.self) { period in
                    Text(period.title).tag(period)
                }
            } label: {
                Text("Period", bundle: .module)
            }
            .pickerStyle(.segmented)
        }
    }

    /// Every chart, in order. A new chart adds its section here.
    @ViewBuilder
    private func charts(_ graphs: StatisticsGraphs) -> some View {
        let today = graphs.today
        let cardCounts = graphs.cardCounts
        let ratings = graphs.ratings
        let reviews = graphs.reviewDays
        if today.isEmpty && cardCounts.isEmpty && ratings.isEmpty && reviews.isEmpty {
            Section {
                ContentUnavailableView {
                    Label {
                        Text("No Statistics Yet", bundle: .module)
                    } icon: {
                        Image(systemName: StatisticsSection.systemImage)
                    }
                } description: {
                    if model.scope == .collection {
                        Text("Add cards and study them to see statistics here.", bundle: .module)
                    } else {
                        Text("This deck has no cards and no reviews yet.", bundle: .module)
                    }
                }
            }
        } else {
            TodaySection(today: today)
            ReviewHistorySection(days: reviews, earliestDay: graphs.period.earliestReviewDay)
            CardCountsSection(counts: cardCounts)
            RatingsSection(ratings: ratings)
        }
    }
}
