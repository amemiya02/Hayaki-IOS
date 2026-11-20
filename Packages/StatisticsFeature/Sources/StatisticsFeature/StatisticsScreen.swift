import CollectionStore
import HayakiAppearance
import SwiftUI

/// Native statistics for the chosen deck, collection, or Anki search.
public struct StatisticsScreen: View {
    @State private var model: StatisticsModel
    @State private var draftSearch = ""
    @State private var appliedSearch = ""
    @State private var report: StatisticsPDF?
    @State private var exportingReport = false
    @State private var reportError: String?
    @Environment(\.locale) private var locale

    public init(store: CollectionStore) {
        let model = StatisticsModel(store: store, selectCurrentDeckOnFirstLoad: true)
        model.period = .year
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            List {
                errorBanners
                selectionSection
                switch model.state {
                case .loading:
                    StatisticsPlaceholder()
                case .failed(let message):
                    failure(message)
                case .loaded:
                    if let graphs = model.graphs {
                        charts(graphs)
                    }
                }
            }
            .hayakiScrollBackground()
            .navigationTitle(StatisticsSection.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            if let graphs = exportableGraphs { exportPDF(graphs) }
                        } label: {
                            Label {
                                Text("Export Statistics PDF", bundle: .module)
                            } icon: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(exportableGraphs == nil)
                    } label: {
                        Label {
                            Text("Statistics Options", bundle: .module)
                        } icon: {
                            Image(systemName: "ellipsis")
                        }
                    }
                    .accessibilityIdentifier("statistics-options")
                }
            }
            .refreshable { await model.refresh() }
        }
        .fileExporter(
            isPresented: $exportingReport, document: report, contentTypes: [.pdf],
            defaultFilename: String(localized: "Hayaki Statistics", bundle: .module)
        ) { result in
            if case .failure(let error) = result { reportError = error.localizedDescription }
            report = nil
        } onCancellation: {
            report = nil
        }
        .task(id: model.selection) { await model.run() }
    }

    /// Problems that leave the statistics usable, as rows above the scope.
    @ViewBuilder
    private var errorBanners: some View {
        if let reportError {
            Section {
                InlineErrorBanner(title: Text("Could Not Export Statistics", bundle: .module), message: reportError) {
                    self.reportError = nil
                }
            }
        }
        if let preferenceError = model.preferenceError {
            Section {
                InlineErrorBanner(title: Text("Could Not Save Statistics Preference", bundle: .module), message: preferenceError) {
                    model.preferenceError = nil
                }
            }
        }
    }

    /// The graphs a PDF can be made from: loaded, and for the current selection.
    private var exportableGraphs: StatisticsGraphs? {
        guard case .loaded = model.state, model.loadedSelection == model.selection else { return nil }
        return model.graphs
    }

    private func exportPDF(_ graphs: StatisticsGraphs) {
        let scope: Text
        switch model.scope {
        case .collection:
            scope = Text("Whole Collection", bundle: .module)
        case .deck(let id):
            scope = Text(verbatim: model.decks.first { $0.id == id }?.displayName ?? "")
        case .search(let query):
            scope = Text(verbatim: query)
        }
        do {
            report = try StatisticsPDF.make(graphs: graphs, preferences: model.preferences, scope: scope, locale: locale)
            exportingReport = true
        } catch {
            reportError = error.localizedDescription
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

/// The shape of the statistics while the core computes them: a few titled
/// chart sections, as placeholder bars and blocks.
private struct StatisticsPlaceholder: View {
    private static let chartHeights: [CGFloat] = [72, 180, 140]

    var body: some View {
        ForEach(Self.chartHeights.indices, id: \.self) { index in
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // Never shown: redaction draws these as bars.
                    Text(verbatim: "Statistics section title")
                        .font(.headline)
                    Text(verbatim: "A short summary of the chart")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(height: Self.chartHeights[index])
                }
                .padding(.vertical, 4)
                .loadingPlaceholder()
                // VoiceOver hears one "in progress" element, not three.
                .accessibilityHidden(index > 0)
            }
        }
    }
}
