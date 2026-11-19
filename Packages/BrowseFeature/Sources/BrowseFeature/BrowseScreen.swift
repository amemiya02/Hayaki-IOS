import CollectionStore
import DecksFeature
import NoteEditorFeature
import PackagesFeature
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
    /// Whether the learner is selecting cards to act on them together.
    @State private var isSelecting = false
    @State private var isMoving = false
    @State private var conversion: ConversionSelection?
    @State private var sheet: BrowseSheet?
    @State private var actionPrompt: BrowserActionPrompt?
    @State private var inspectedCard: CardLink?
    @AppStorage("browseTruncatesRows") private var truncatesRows = true
    /// What a deletion the learner asked for would delete, while it waits
    /// for confirmation.
    @State private var deletion: DeletionSummary?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    public init(store: CollectionStore, initialSearch: String = "") {
        self.store = store
        let model = CardBrowserModel(store: store)
        model.searchText = initialSearch
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationDestination(for: CardLink.self) { link in
                    CardInfoScreen(store: store, cardID: link.cardID)
                }
                .navigationDestination(item: $inspectedCard) { link in
                    CardInfoScreen(store: store, cardID: link.cardID)
                }
                .toolbar { toolbar }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !isSelecting { modePicker }
                }
                .selectingCards(isSelecting)
                .safeAreaInset(edge: .bottom) {
                    if let completed = model.completedAction {
                        UndoBanner(model: model, completed: completed)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.default, value: model.completedAction)
                .task(id: model.completedAction) {
                    // The undo offer goes away after a while, unless
                    // VoiceOver is on (reaching it may take longer).
                    guard model.completedAction != nil, !voiceOverEnabled else { return }
                    try? await Task.sleep(for: .seconds(10))
                    if !Task.isCancelled { model.dismissCompletedAction() }
                }
                .sheet(item: $sheet) { sheet in
                    sheetContent(sheet)
                }
                .sheet(item: $actionPrompt) { prompt in
                    BrowserActionSheet(prompt: prompt, model: model)
                }
                .sheet(isPresented: $isMoving) {
                    MoveCardsSheet(model: model)
                }
                .sheet(item: $conversion) { selection in
                    ChangeNoteTypeScreen(store: store, noteIDs: selection.noteIDs) {
                        model.clearSelection()
                        isSelecting = false
                        await model.refreshResults()
                    }
                }
                // An alert, as in Decks: a dialog would point at the list's
                // edge, next to the sidebar on iPad.
                .alert(
                    Text("Delete \(deletion?.noteCount ?? 0) Notes?", bundle: .module),
                    isPresented: isConfirmingDeletion,
                    presenting: deletion
                ) { _ in
                    Button(role: .destructive) {
                        Task { await model.perform(.delete) }
                    } label: {
                        Text("Delete", bundle: .module)
                    }
                    Button(role: .cancel) {} label: {
                        Text("Cancel", bundle: .module)
                    }
                } message: { summary in
                    Text("Deleting a card deletes its note, with the note's other cards: \(summary.cardCount) cards in all.", bundle: .module)
                }
                .alert(
                    Text("Could Not Change Cards", bundle: .module),
                    isPresented: hasFailure
                ) {
                    Button {} label: { Text("OK", bundle: .module) }
                } message: {
                    Text(model.failure ?? "")
                }
                .onChange(of: model.rowIDs.isEmpty) { _, isEmpty in
                    if isEmpty { isSelecting = false }
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

    private var title: Text {
        isSelecting ? Text("\(model.selection.count) Selected", bundle: .module) : BrowseSection.title
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                if model.selection.count == model.rowIDs.count {
                    Button {
                        model.clearSelection()
                    } label: {
                        Text("Deselect All", bundle: .module)
                    }
                } else {
                    Button {
                        model.selectAll()
                    } label: {
                        Text("Select All", bundle: .module)
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    isSelecting = false
                    model.clearSelection()
                } label: {
                    Text("Done", bundle: .module)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                BulkActionMenu(
                    model: model,
                    isMoving: $isMoving,
                    deletion: $deletion,
                    prompt: $actionPrompt,
                    onEdit: { openFirstSelection(asInfo: false) },
                    onInfo: { openFirstSelection(asInfo: true) },
                    onPreview: { preview(selectedOnly: true) },
                    onExport: export,
                    onChangeNoteType: changeNoteType
                )
                .disabled(model.selection.isEmpty || model.isPerformingAction)
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    sheet = .filters
                } label: {
                    Label {
                        Text("Filters", bundle: .module)
                    } icon: { Image(systemName: "line.3.horizontal.decrease") }
                }
                configurationMenu
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSelecting = true
                } label: {
                    Text("Select", bundle: .module)
                }
                .disabled(model.rowIDs.isEmpty)
            }
        }
    }

    private struct ConversionSelection: Identifiable {
        let noteIDs: [Int64]
        var id: [Int64] { noteIDs }
    }

    private var modePicker: some View {
        Picker(selection: Binding {
            model.mode
        } set: { mode in
            Task { await model.setMode(mode) }
        }) {
            Text("Cards", bundle: .module).tag(CardBrowserModel.Mode.cards)
            Text("Notes", bundle: .module).tag(CardBrowserModel.Mode.notes)
        } label: {
            Text("Browse Mode", bundle: .module)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("browse-mode")
        .frame(maxWidth: 440)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var configurationMenu: some View {
        Menu {
            BrowserUndoMenuAction(model: model)
            SortMenu(model: model)
            Button {
                sheet = .columns
            } label: {
                Label {
                    Text("Columns", bundle: .module)
                } icon: { Image(systemName: "tablecells") }
            }
            .disabled(model.availableColumns.isEmpty)
            Button {
                sheet = .savedSearches
            } label: {
                Label {
                    Text("Saved Searches", bundle: .module)
                } icon: { Image(systemName: "bookmark") }
            }
            Button {
                sheet = .flags
            } label: {
                Label {
                    Text("Rename Flags", bundle: .module)
                } icon: { Image(systemName: "flag") }
            }
            Toggle(isOn: $truncatesRows) { Text("Truncate Rows", bundle: .module) }
            Divider()
            Button {
                preview(selectedOnly: false)
            } label: {
                Label {
                    Text("Preview", bundle: .module)
                } icon: { Image(systemName: "eye") }
            }
            .disabled(model.rowIDs.isEmpty)
            Button {
                sheet = .filteredDeck(model.searchedText)
            } label: {
                Label {
                    Text("New Filtered Deck", bundle: .module)
                } icon: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
            .disabled(model.state != .loaded)
            Button {
                actionPrompt = .replace
            } label: {
                Label {
                    Text("Find and Replace", bundle: .module)
                } icon: { Image(systemName: "text.magnifyingglass") }
            }
        } label: {
            Label {
                Text("Browse Options", bundle: .module)
            } icon: { Image(systemName: "ellipsis.circle") }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: BrowseSheet) -> some View {
        switch sheet {
        case .filters: BrowserFiltersSheet(model: model)
        case .columns: BrowserColumnsSheet(model: model)
        case .savedSearches: BrowserSavedSearchesSheet(model: model)
        case .flags: BrowserFlagLabelsSheet(model: model)
        case .filteredDeck(let search): FilteredDeckScreen(store: store, initialSearch: search)
        case .editing(let cardID): NoteEditorScreen(store: store, editingCardID: cardID)
        case .preview(let cardIDs): BrowserPreviewScreen(store: store, cardIDs: cardIDs)
        case .textExport(let selection): TextExportScreen(store: store, selection: selection)
        case .packageExport(let selection): PackageExportScreen(store: store, selection: selection)
        }
    }

    private func openFirstSelection(asInfo: Bool) {
        guard let row = model.rowIDs.first(where: model.selection.contains) else { return }
        open(row, asInfo: asInfo)
    }

    private func open(_ rowID: Int64, asInfo: Bool) {
        Task {
            guard let cardID = await model.cardID(forRow: rowID) else { return }
            if asInfo {
                inspectedCard = CardLink(cardID: cardID)
            } else {
                sheet = .editing(cardID)
            }
        }
    }

    private func changeNoteType() {
        Task {
            if let noteIDs = await model.selectedNoteIDs(), !noteIDs.isEmpty {
                conversion = ConversionSelection(noteIDs: noteIDs)
            }
        }
    }

    private func preview(selectedOnly: Bool) {
        Task {
            let ids = await model.previewCardIDs(selectedOnly: selectedOnly)
            if !ids.isEmpty { sheet = .preview(ids) }
        }
    }

    private func export(asPackage: Bool) {
        let ids = model.rowIDs.filter { model.selection.contains($0) }
        guard !ids.isEmpty else { return }
        let selection = model.mode == .cards ? ExportSelection.cards(ids) : .notes(ids)
        sheet = asPackage ? .packageExport(selection) : .textExport(selection)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding {
            deletion != nil
        } set: { isShown in
            if !isShown { deletion = nil }
        }
    }

    private var hasFailure: Binding<Bool> {
        Binding {
            model.failure != nil
        } set: { isShown in
            if !isShown { model.failure = nil }
        }
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
        case .loaded where model.rowIDs.isEmpty:
            if model.searchedText.isEmpty {
                ContentUnavailableView {
                    Label {
                        if model.mode == .cards {
                            Text("No Cards", bundle: .module)
                        } else {
                            Text("No Notes", bundle: .module)
                        }
                    } icon: {
                        Image(systemName: "rectangle.on.rectangle.slash")
                    }
                } description: {
                    if model.mode == .cards {
                        Text("Cards you add or import appear here.", bundle: .module)
                    } else {
                        Text("Notes you add or import appear here.", bundle: .module)
                    }
                }
            } else {
                ContentUnavailableView.search(text: model.searchedText)
            }
        case .loaded:
            List(model.rowIDs, id: \.self, selection: isSelecting ? $model.selection : nil) { rowID in
                row(rowID)
            }
            .listStyle(.plain)
            .refreshable { await model.refreshResults() }
        }
    }
    @ViewBuilder
    private func row(_ rowID: Int64) -> some View {
        let row = CardRowView(model: model, cardID: rowID, truncates: truncatesRows)
        if isSelecting {
            row.tag(rowID)
        } else {
            Group {
                if model.mode == .cards {
                    NavigationLink(value: CardLink(cardID: rowID)) { row }
                } else {
                    Button {
                        open(rowID, asInfo: false)
                    } label: { row }
                    .buttonStyle(.plain)
                }
            }
            .contextMenu {
                Button { open(rowID, asInfo: false) } label: {
                    Text("Edit Note", bundle: .module)
                }
                Button { open(rowID, asInfo: true) } label: {
                    Text("Card Info", bundle: .module)
                }
                Button {
                    model.selection = [rowID]
                    isSelecting = true
                } label: {
                    Text("Select", bundle: .module)
                }
            }
        }
    }
}

private enum BrowseSheet: Identifiable {
    case filters, columns, savedSearches, flags, editing(Int64), preview([Int64])
    case textExport(ExportSelection), packageExport(ExportSelection), filteredDeck(String)

    var id: Int {
        switch self {
        case .filters: 0
        case .columns: 1
        case .savedSearches: 2
        case .editing: 3
        case .preview: 4
        case .textExport: 5
        case .packageExport: 6
        case .flags: 7
        case .filteredDeck: 8
        }
    }
}

/// A card to show in the card detail.
struct CardLink: Hashable {
    let cardID: Int64
}

private extension View {
    /// While selecting, the list shows selection circles. (The package also
    /// builds for macOS so its tests run on the Mac.)
    @ViewBuilder
    func selectingCards(_ isSelecting: Bool) -> some View {
        #if os(iOS)
        environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        #else
        self
        #endif
    }
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

/// Rows load the visible columns from the core in pages.
private struct CardRowView: View {
    let model: CardBrowserModel
    let cardID: Int64
    let truncates: Bool

    var body: some View {
        let row = model.row(for: cardID)
        CardRowContent(row: row, columns: model.visibleColumns, truncates: truncates, flagLabel: flagLabel(row))
            .redacted(reason: row == nil ? .placeholder : [])
            .task(id: RowVersion(cardID: cardID, generation: model.generation)) {
                await model.loadRow(cardID)
            }
    }

    private func flagLabel(_ row: CardRow?) -> Text? {
        if case .flag(let flag)? = row?.mark { model.flagName(flag) } else { nil }
    }

    private struct RowVersion: Hashable {
        let cardID: Int64
        let generation: Int
    }
}

private struct CardRowContent: View {
    let row: CardRow?
    let columns: [BrowserColumn]
    let truncates: Bool
    let flagLabel: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let first = columns.first {
                    Text(verbatim: value(first))
                        .lineLimit(truncates ? 2 : nil)
                        .accessibilityLabel(Text(verbatim: "\(first.label), \(value(first))"))
                }
                Spacer(minLength: 0)
                if let row, let mark = MarkBadge(mark: row.mark, flagLabel: flagLabel) {
                    mark
                }
            }
            if columns.count > 1 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], alignment: .leading) {
                    ForEach(Array(columns.dropFirst())) { column in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: column.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(truncates ? 1 : nil)
                            Text(verbatim: value(column))
                                .font(.subheadline)
                                .lineLimit(truncates ? 1 : nil)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func value(_ column: BrowserColumn) -> String {
        guard let row else { return column.label }
        let value = row.cells[column.id] ?? ""
        return value.isEmpty ? "–" : value
    }
}

/// A small symbol for a flagged, marked, suspended or buried card.
struct MarkBadge: View {
    let symbol: String
    let color: Color
    let label: Text

    init?(mark: CardRow.Mark, flagLabel: Text? = nil) {
        switch mark {
        case .none:
            return nil
        case .flag(let flag):
            symbol = "flag.fill"
            color = flag.color
            label = flagLabel ?? flag.label
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
