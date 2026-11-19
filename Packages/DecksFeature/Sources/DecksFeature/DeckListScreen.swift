import CollectionStore
import PackagesFeature
import StudyFeature
import SwiftUI

/// The Decks section: every deck as a nested list with today's counts. Tapping
/// a deck starts studying it, full screen.
public struct DeckListScreen: View {
    @State private var model: DeckListModel
    @State private var studying: StudyDeck?
    @State private var selectedDeckID: DeckNode.ID?
    @Environment(\.scenePhase) private var scenePhase
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
                    ToolbarItem(placement: .primaryAction) {
                        ExportPackageButton(store: store)
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        SharedDecksLink()
                    }
                }
                .deckManagement(model)
        }
        .task { await model.run() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .onChange(of: selectedDeck?.id, initial: true) { _, id in
            selectedDeckID = id
        }
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
        case .loaded where model.hasNoCards && !model.hasOwnDecks:
            ContentUnavailableView {
                Label {
                    Text("No Cards Yet", bundle: .module)
                } icon: {
                    Image(systemName: "rectangle.stack")
                }
            } description: {
                Text("Import a deck package (.apkg) or a collection package (.colpkg) from Hayaki, Anki or AnkiDroid.", bundle: .module)
            } actions: {
                VStack {
                    SharedDecksLink()
                        .buttonStyle(.borderedProminent)
                    ImportPackageButton()
                    NewDeckButton()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .loaded:
            let selection = selectedDeck?.id
            List {
                TodayDeckSummary(due: model.dueToday, studied: model.studiedToday, deck: deckToStudy, onStudy: study)
                ForEach(model.decks) { deck in
                    DeckRows(deck: deck, selectedDeckID: selection, study: study)
                }
            }
            .refreshable { await model.refresh() }
            .environment(model)
        }
    }

    private var selectedDeck: DeckNode? {
        // Keep the selection when an import brings in a different current
        // deck. Fall back to the core when the chosen deck no longer exists.
        selectedDeckID.flatMap(model.deck) ?? model.currentDeckID.flatMap(model.deck)
    }

    private var deckToStudy: DeckNode? {
        if let selectedDeck, !selectedDeck.counts.isEmpty { return selectedDeck }
        return model.decks.first { !$0.counts.isEmpty }
    }

    private func study(_ deck: DeckNode) {
        selectedDeckID = deck.id
        studying = StudyDeck(id: deck.id, name: deck.name)
    }
}

private struct TodayDeckSummary: View {
    let due: Int
    let studied: Int
    let deck: DeckNode?
    let onStudy: (DeckNode) -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if due == 0 {
                        Text("Nothing due today", bundle: .module)
                    } else {
                        Text("\(due) due today", bundle: .module)
                    }
                }
                .font(.headline.monospacedDigit())
                .accessibilityIdentifier("due-today")
                Text("\(studied) studied today", bundle: .module)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("studied-today")
                if let deck {
                    Button {
                        onStudy(deck)
                    } label: {
                        Text("Study Now · \(deck.name)", bundle: .module)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
                    .accessibilityIdentifier("study-selected-deck")
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// A deck and, below it, its child decks, which can be collapsed.
private struct DeckRows: View {
    let deck: DeckNode
    let selectedDeckID: DeckNode.ID?
    let study: (DeckNode) -> Void
    @Environment(DeckListModel.self) private var model

    var body: some View {
        if deck.children.isEmpty {
            row
                .deckActions(for: deck)
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(deck.children) { child in
                    DeckRows(deck: child, selectedDeckID: selectedDeckID, study: study)
                }
            } label: {
                row
                    .deckActions(for: deck)
            }
        }
    }

    private var row: some View {
        DeckRow(deck: deck, isSelected: deck.id == selectedDeckID, study: study)
    }

    /// Whether the child decks show; the core remembers it for next time.
    private var isExpanded: Binding<Bool> {
        Binding {
            !deck.isCollapsed
        } set: { isExpanded in
            Task { try? await model.setCollapsed(!isExpanded, deck: deck.id) }
        }
    }
}

private struct DeckRow: View {
    let deck: DeckNode
    let isSelected: Bool
    let study: (DeckNode) -> Void

    var body: some View {
        Button {
            study(deck)
        } label: {
            HStack {
                Text(deck.name)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                Spacer()
                CountsView(counts: deck.counts)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
