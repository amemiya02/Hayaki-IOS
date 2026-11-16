import CollectionStore
import PackagesFeature
import SwiftUI

/// The Decks section: every deck as a nested list with today's counts.
public struct DeckListScreen: View {
    @State private var model: DeckListModel

    public init(store: CollectionStore) {
        _model = State(initialValue: DeckListModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Decks", bundle: .module))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ImportPackageButton()
                    }
                }
        }
        .task { await model.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Could Not Show Decks", bundle: .module)
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
        case .loaded where model.hasNoCards:
            ContentUnavailableView {
                Label {
                    Text("No Cards Yet", bundle: .module)
                } icon: {
                    Image(systemName: "rectangle.stack")
                }
            } description: {
                Text("Bring your cards in from Anki or AnkiDroid by importing a collection package (.colpkg) or a deck package (.apkg).", bundle: .module)
            } actions: {
                ImportPackageButton()
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            List {
                ForEach(model.decks) { deck in
                    DeckRows(deck: deck)
                }
            }
            .refreshable { await model.refresh() }
        }
    }
}

/// A deck and, below it, its child decks, which can be collapsed.
private struct DeckRows: View {
    let deck: DeckNode
    @State private var isExpanded: Bool

    init(deck: DeckNode) {
        self.deck = deck
        _isExpanded = State(initialValue: !deck.isCollapsed)
    }

    var body: some View {
        if deck.children.isEmpty {
            DeckRow(deck: deck)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(deck.children) { child in
                    DeckRows(deck: child)
                }
            } label: {
                DeckRow(deck: deck)
            }
        }
    }
}

private struct DeckRow: View {
    let deck: DeckNode

    var body: some View {
        HStack {
            Text(deck.name)
            Spacer()
            CountsView(counts: deck.counts)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today's new, learning and due counts in Anki's colours: blue, red and green.
private struct CountsView: View {
    let counts: DeckCounts

    var body: some View {
        HStack(spacing: 12) {
            count(counts.new, color: .blue)
            count(counts.learning, color: .red)
            count(counts.due, color: .green)
        }
        .font(.callout.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(counts.new) new, \(counts.learning) learning, \(counts.due) due",
            bundle: .module
        ))
    }

    private func count(_ value: Int, color: Color) -> some View {
        Text(value, format: .number)
            .foregroundStyle(value == 0 ? Color.secondary : color)
            .frame(minWidth: 24, alignment: .trailing)
    }
}
