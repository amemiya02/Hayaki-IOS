import CollectionStore
import PackagesFeature
import StudyFeature
import SwiftUI

/// The Decks section: every deck as a nested list with today's counts. Tapping
/// a deck starts studying it, full screen.
public struct DeckListScreen: View {
    @State private var model: DeckListModel
    @State private var studying: StudyDeck?
    private let store: CollectionStore

    public init(store: CollectionStore) {
        self.store = store
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
        .studySession(of: $studying, store: store)
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
                    DeckRows(deck: deck) { studying = StudyDeck(id: $0.id, name: $0.name) }
                }
            }
            .refreshable { await model.refresh() }
        }
    }
}

/// A deck and, below it, its child decks, which can be collapsed.
private struct DeckRows: View {
    let deck: DeckNode
    let study: (DeckNode) -> Void
    @State private var isExpanded: Bool

    init(deck: DeckNode, study: @escaping (DeckNode) -> Void) {
        self.deck = deck
        self.study = study
        _isExpanded = State(initialValue: !deck.isCollapsed)
    }

    var body: some View {
        if deck.children.isEmpty {
            DeckRow(deck: deck, study: study)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(deck.children) { child in
                    DeckRows(deck: child, study: study)
                }
            } label: {
                DeckRow(deck: deck, study: study)
            }
        }
    }
}

private struct DeckRow: View {
    let deck: DeckNode
    let study: (DeckNode) -> Void

    var body: some View {
        Button {
            study(deck)
        } label: {
            HStack {
                Text(deck.name)
                Spacer()
                CountsView(counts: deck.counts)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Studies this deck.", bundle: .module))
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
