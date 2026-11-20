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
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isWide: Bool { horizontalSizeClass == .regular }
    #else
    private let isWide = true
    #endif
    @Environment(\.hayakiTheme) private var theme

    public init(store: CollectionStore) {
        let model = StatisticsModel(store: store, selectCurrentDeckOnFirstLoad: true)
        model.period = .year
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    periodPicker
                    if case .search = model.scope {
                        searchField
                    }
                    switch model.state {
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    case .failed(let message):
                        failure(message)
                    case .loaded:
                        if let graphs = model.graphs {
                            charts(graphs)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            // Cards scrolling under the tab bar fade out instead of showing through it.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .hayakiBackground(.grouped)
            .navigationTitle(StatisticsSection.title)
            .navigationSubtitle(scopeName)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        scopePicker
                        Divider()
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
        .alert(Text("Could Not Export Statistics", bundle: .module), isPresented: Binding {
            reportError != nil
        } set: { visible in
            if !visible { reportError = nil }
        }) {
            Button(role: .cancel) { reportError = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(reportError ?? "")
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

    /// The deck, the whole collection or a custom search, chosen from the `⋯` menu.
    private var scopePicker: some View {
        Picker(selection: $model.scope) {
            Text("Whole Collection", bundle: .module)
                .tag(StatisticsScope.collection)
            ForEach(model.decks) { deck in
                Text(deck.displayName).tag(StatisticsScope.deck(id: deck.id))
            }
            Text("Custom Search", bundle: .module).tag(StatisticsScope.search(appliedSearch))
        } label: {
            Label {
                Text("Deck or Search", bundle: .module, comment: "Statistics menu: chooses which cards the statistics cover.")
            } icon: {
                Image(systemName: "rectangle.stack")
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("statistics-scope")
    }

    /// What the statistics cover, shown under the title.
    private var scopeName: Text {
        switch model.scope {
        case .collection:
            Text("Whole Collection", bundle: .module)
        case .deck(let id):
            Text(verbatim: model.decks.first { $0.id == id }?.displayName ?? "")
        case .search(let query):
            query.isEmpty ? Text("Custom Search", bundle: .module) : Text(verbatim: query)
        }
    }

    private var periodPicker: some View {
        Picker(selection: $model.period) {
            ForEach(StatisticsPeriod.allCases, id: \.self) { period in
                Text(period.title).tag(period)
            }
        } label: {
            Text("Period", bundle: .module, comment: "Statistics: how far back the charts look.")
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("statistics-period")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: $draftSearch, prompt: Text("Anki search expression", bundle: .module)) {
                Text("Search", bundle: .module)
            }
            .autocorrectionDisabled()
            .onSubmit(applySearch)
            Button(action: applySearch) {
                Text("Apply Search", bundle: .module)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
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
        } else {
            ForEach(sections: TodaySection(graphs: graphs)) { section in
                StatisticsCard(section: section)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(sections: graphCards(graphs, cardCounts: cardCounts)) { section in
                    StatisticsCard(section: section)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func graphCards(_ graphs: StatisticsGraphs, cardCounts: CardCounts) -> some View {
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

    /// One column of cards on iPhone, two on iPad.
    private var columns: [GridItem] {
        let count = isWide ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: count)
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
