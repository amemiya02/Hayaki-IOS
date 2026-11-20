import CollectionStore
import DeckOptionsFeature
import HayakiAppearance
import PackagesFeature
import StudyFeature
import SwiftUI

/// A deck queued by an external study or options destination.
public struct DeckPresentation: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let deckID: Int64
    public let showsOptions: Bool

    public init(deckID: Int64, showsOptions: Bool) {
        self.deckID = deckID
        self.showsOptions = showsOptions
    }
}

/// The Decks section: every deck as a nested list with today's counts. Tapping
/// a deck starts studying it, full screen.
public struct DeckListScreen<SyncControl: View>: View {
    @State private var model: DeckListModel
    @State private var studying: StudyDeck?
    @State private var optionsDeck: DeckNode?
    @Binding private var presentation: DeckPresentation?
    @State private var selectedDeckID: DeckNode.ID?
    @AppStorage(DeckBackground.revisionKey) private var backgroundRevision = ""
    @State private var backgroundImage: CGImage?
    @Environment(\.scenePhase) private var scenePhase
    private let store: CollectionStore
    private let profileID: UUID?
    private let syncControl: SyncControl

    public init(
        store: CollectionStore,
        profileID: UUID? = nil,
        presentation: Binding<DeckPresentation?> = .constant(nil),
        @ViewBuilder syncControl: () -> SyncControl
    ) {
        self.store = store
        self.profileID = profileID
        self.syncControl = syncControl()
        _presentation = presentation
        _model = State(initialValue: DeckListModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { deckBackground }
                .navigationTitle(Text("Decks", bundle: .module))
                .toolbar {
                    // One glass capsule: sync, Add Note and a menu with the rest.
                    ToolbarItemGroup(placement: .primaryAction) {
                        syncControl
                        AddNoteButton()
                        optionsMenu
                    }
                }
                .deckManagement(model, profileID: profileID) { deck in
                    selectedDeckID = deck.id
                    studying = deck
                }
        }
        .packageSheets(store: store)
        .task { await model.run() }
        .task(id: backgroundRevision) {
            let image = await DeckBackground(collectionFolder: store.location.folder).image()
            if !Task.isCancelled { backgroundImage = image }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .onChange(of: selectedDeck?.id, initial: true) { _, id in
            selectedDeckID = id
        }
        .onChange(of: presentation, initial: true) { _, _ in openRequestedDeck() }
        .onChange(of: model.state) { _, _ in openRequestedDeck() }
        .sheet(item: $optionsDeck) { deck in
            if deck.isFiltered {
                FilteredDeckScreen(store: store, deckID: deck.id)
            } else {
                DeckOptionsScreen(store: store, deckID: deck.id)
            }
        }
        .studySession(of: $studying, store: store)
    }

    /// The `⋯` menu: importing and exporting, and creating decks.
    private var optionsMenu: some View {
        Menu {
            Section {
                ImportPackageButton()
                ExportPackageButton(store: store)
                SharedDecksLink()
            }
            Section {
                TextImportButton()
                TextExportButton(store: store)
            }
            Section {
                NewDeckButton()
                NewFilteredDeckButton()
            }
        } label: {
            Label {
                Text("Deck List Options", bundle: .module)
            } icon: {
                Image(systemName: "ellipsis")
            }
        }
        .accessibilityIdentifier("deck-list-options")
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
            .scrollContentBackground(.hidden)
            .refreshable { await model.refresh() }
            .environment(model)
        }
    }

    private var deckBackground: some View {
        GeometryReader { geometry in
            if let backgroundImage {
                Image(decorative: backgroundImage, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay(HayakiBackground(.grouped).opacity(0.65))
            } else {
                HayakiBackground(.grouped)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
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

    private func openRequestedDeck() {
        guard let request = presentation, model.state == .loaded else { return }
        presentation = nil
        guard let deck = model.deck(request.deckID) else { return }
        if request.showsOptions {
            optionsDeck = deck
        } else {
            study(deck)
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout())
        Button {
            study(deck)
        } label: {
            layout {
                HStack {
                    Text(verbatim: deck.name)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CountsView(counts: deck.counts)
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { numbers }
            VStack(alignment: .leading, spacing: 4) { numbers }
        }
        .font(.callout)
        .hayakiNumeric()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "\(counts.new) new, \(counts.learning) learning, \(counts.due) due",
            bundle: .module
        ))
    }

    private var numbers: some View {
        Group {
            count(counts.new, color: SemanticColor.new.color)
            count(counts.learning, color: SemanticColor.learning.color)
            count(counts.due, color: SemanticColor.due.color)
        }
    }

    private func count(_ value: Int, color: Color) -> some View {
        Text(value, format: .number)
            .foregroundStyle(value == 0 ? Color.secondary : color)
            .frame(minWidth: 24, alignment: .trailing)
    }
}


public extension DeckListScreen where SyncControl == EmptyView {
    init(
        store: CollectionStore,
        profileID: UUID? = nil,
        presentation: Binding<DeckPresentation?> = .constant(nil)
    ) {
        self.init(store: store, profileID: profileID, presentation: presentation) { EmptyView() }
    }
}
