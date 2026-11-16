import CollectionStore
import SwiftUI

/// How the Browse section appears in the tab bar and sidebar.
public enum BrowseSection {
    public static var title: Text { Text("Browse", bundle: .module) }
    public static let systemImage = "magnifyingglass"
}

/// The Browse section: every card of the collection, searchable with Anki's
/// search syntax and sortable, each opening its card detail.
public struct BrowseScreen: View {
    private let store: CollectionStore
    @State private var model: CardBrowserModel

    public init(store: CollectionStore) {
        self.store = store
        _model = State(initialValue: CardBrowserModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(BrowseSection.title)
                .navigationDestination(for: CardLink.self) { link in
                    CardDetailScreen(store: store, cardID: link.cardID)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        SortMenu(model: model)
                    }
                }
        }
        .searchable(
            text: $model.searchText,
            prompt: Text("Anki search, such as deck:Spanish", bundle: .module)
        )
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        // Like Anki, search when the learner submits, not on every keystroke:
        // half-typed searches are often not valid yet.
        .onSubmit(of: .search) {
            Task { await model.search() }
        }
        .onChange(of: model.searchText) { _, text in
            // Clearing the field shows every card again.
            if text.isEmpty { Task { await model.search() } }
        }
        .task { await model.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .invalidSearch(let message):
            ContentUnavailableView {
                Label {
                    Text("Invalid Search", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.magnifyingglass")
                }
            } description: {
                Text(message)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Could Not Show Cards", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(message)
            } actions: {
                Button {
                    Task { await model.search() }
                } label: {
                    Text("Try Again", bundle: .module)
                }
            }
        case .loaded where model.cardIDs.isEmpty:
            if model.searchedText.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Cards", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.on.rectangle.slash")
                    }
                } description: {
                    Text("Cards you add or import appear here.", bundle: .module)
                }
            } else {
                ContentUnavailableView.search(text: model.searchedText)
            }
        case .loaded:
            List(model.cardIDs, id: \.self) { cardID in
                NavigationLink(value: CardLink(cardID: cardID)) {
                    CardRowView(model: model, cardID: cardID)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.search() }
        }
    }
}

/// A card to show in the card detail.
struct CardLink: Hashable {
    let cardID: Int64
}

/// The sort order menu: the column, then ascending or descending.
private struct SortMenu: View {
    let model: CardBrowserModel

    var body: some View {
        Menu {
            // The column list is long, so it is a submenu showing the
            // current column; the direction stays one tap away.
            Picker(selection: column) {
                ForEach(model.sortColumns) { column in
                    Text(column.label).tag(column.id)
                }
            } label: {
                Text("Sort By", bundle: .module)
            }
            .pickerStyle(.menu)
            Picker(selection: reverse) {
                Text("Ascending", bundle: .module).tag(false)
                Text("Descending", bundle: .module).tag(true)
            } label: {
                Text("Order", bundle: .module)
            }
        } label: {
            Label {
                Text("Sort", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        .disabled(model.sortColumns.isEmpty)
    }

    private var column: Binding<String> {
        Binding {
            model.sort.column
        } set: { id in
            guard let column = model.sortColumns.first(where: { $0.id == id }) else { return }
            Task { await model.sortBy(column) }
        }
    }

    private var reverse: Binding<Bool> {
        Binding {
            model.sort.reverse
        } set: { reverse in
            var sort = model.sort
            sort.reverse = reverse
            Task { await model.setSort(sort) }
        }
    }
}

/// One card in the list. Its text is fetched from the core when the row
/// appears, so only the rows on screen are fetched.
private struct CardRowView: View {
    let model: CardBrowserModel
    let cardID: Int64

    var body: some View {
        Group {
            if let row = model.row(for: cardID) {
                CardRowContent(row: row)
            } else {
                // Placeholder of a row's height while it is fetched.
                CardRowContent(row: nil)
                    .redacted(reason: .placeholder)
            }
        }
        .task(id: RowVersion(cardID: cardID, generation: model.generation)) {
            await model.loadRow(cardID)
        }
    }

    private struct RowVersion: Hashable {
        let cardID: Int64
        let generation: Int
    }
}

private struct CardRowContent: View {
    let row: CardRow?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: question)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(verbatim: row?.deck ?? "Deck name")
                        .lineLimit(1)
                    Text(verbatim: "·")
                        .accessibilityHidden(true)
                    Text(verbatim: row?.due ?? "Due date")
                        .lineLimit(1)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let row, let mark = MarkBadge(mark: row.mark) {
                mark
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var question: String {
        guard let row else { return "Question of the card" }
        return row.question.isEmpty ? "–" : row.question
    }
}

/// A small symbol for a flagged, marked, suspended or buried card.
struct MarkBadge: View {
    let symbol: String
    let color: Color
    let label: Text

    init?(mark: CardRow.Mark) {
        switch mark {
        case .none:
            return nil
        case .flag(let flag):
            symbol = "flag.fill"
            color = flag.color
            label = flag.label
        case .marked:
            symbol = "star.fill"
            color = .purple
            label = Text("Marked", bundle: .module)
        case .suspended:
            symbol = "pause.circle.fill"
            color = .yellow
            label = Text("Suspended", bundle: .module)
        case .buried:
            symbol = "moon.zzz.fill"
            color = .brown
            label = Text("Buried", bundle: .module)
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }
}

extension CardRow.Flag {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .turquoise: .teal
        case .purple: .purple
        }
    }

    var label: Text {
        switch self {
        case .red: Text("Red flag", bundle: .module)
        case .orange: Text("Orange flag", bundle: .module)
        case .green: Text("Green flag", bundle: .module)
        case .blue: Text("Blue flag", bundle: .module)
        case .pink: Text("Pink flag", bundle: .module)
        case .turquoise: Text("Turquoise flag", bundle: .module)
        case .purple: Text("Purple flag", bundle: .module)
        }
    }
}
