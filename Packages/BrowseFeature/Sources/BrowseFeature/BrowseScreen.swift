import CollectionStore
import HayakiAppearance
import DecksFeature
import NoteEditorFeature
import PackagesFeature
import StudyFeature
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
    @State private var initialCardID: Int64?
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
    /// The row shown beside the list on iPad.
    @State private var focusedRow: Int64?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(store: CollectionStore, initialSearch: String = "", initialCardID: Int64? = nil) {
        self.store = store
        let model = CardBrowserModel(store: store)
        model.searchText = initialSearch
        _model = State(initialValue: model)
        _initialCardID = State(initialValue: initialCardID)
    }

    public var body: some View {
        Group {
            if showsDetailColumn {
                // iPad: the list, and the selected card's preview beside it.
                NavigationSplitView {
                    browseColumn
                        .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 520)
                } detail: {
                    BrowseDetailPane(store: store, model: model, rowID: focusedRow)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    browseColumn
                }
            }
        }
        .task { await model.run() }
    }

    private var showsDetailColumn: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    private var browseColumn: some View {
        browseLayout
                .navigationTitle(title)
                .navigationDestination(for: CardLink.self) { link in
                    CardInfoScreen(store: store, cardID: link.cardID)
                }
                .navigationDestination(item: $inspectedCard) { link in
                    CardInfoScreen(store: store, cardID: link.cardID)
                }
                .toolbar { toolbar }
                .selectingCards(isSelecting)
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
                .onChange(of: model.rowIDs.isEmpty) { _, isEmpty in
                    if isEmpty { isSelecting = false }
                }
                .onChange(of: model.rowIDs) { _, rowIDs in
                    if let focusedRow, !rowIDs.contains(focusedRow) { self.focusedRow = nil }
                }
    }

    private var browseLayout: some View {
        VStack(spacing: 0) {
            if !isSelecting { modePicker }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .inlineErrorBanner(failure)
            if let completed = model.completedAction {
                UndoBanner(model: model, completed: completed)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The system's default placement for a tab root.
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
            // One glass capsule: Add Note and a menu with the rest.
            ToolbarItemGroup(placement: .primaryAction) {
                AddNoteButton { sheet = .addNote }
                configurationMenu
            }
        }
    }

    private struct ConversionSelection: Identifiable {
        let noteIDs: [Int64]
        var id: [Int64] { noteIDs }
    }

    private var modePicker: some View {
        HStack {
            modeToggle
            if model.state == .loaded {
                resultCount
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: 440)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var resultCount: Text {
        switch model.mode {
        case .cards: Text("\(model.rowIDs.count) Cards", bundle: .module)
        case .notes: Text("\(model.rowIDs.count) Notes", bundle: .module)
        }
    }

    private var modeToggle: some View {
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
    }

    private var configurationMenu: some View {
        Menu {
            Button {
                isSelecting = true
            } label: {
                Label {
                    Text("Select", bundle: .module)
                } icon: { Image(systemName: "checkmark.circle") }
            }
            .disabled(model.rowIDs.isEmpty)
            BrowserUndoMenuAction(model: model)
            Divider()
            Button {
                sheet = .filters
            } label: {
                Label {
                    Text("Filters", bundle: .module)
                } icon: { Image(systemName: "line.3.horizontal.decrease") }
            }
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
            } icon: { Image(systemName: "ellipsis") }
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
        case .addNote: NoteEditorScreen(store: store)
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

    /// A bulk action that failed, shown as a banner above the results.
    private var failure: Binding<InlineError?> {
        Binding {
            model.failure.map { InlineError(title: Text("Could Not Change Cards", bundle: .module), message: $0) }
        } set: { error in
            if error == nil { model.failure = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            // The shape of the results while the search runs.
            List(0..<12, id: \.self) { _ in
                CardRowContent(row: nil, columns: model.visibleColumns, truncates: true, flagLabel: nil)
            }
            .hayakiScrollBackground()
            .listStyle(.plain)
            .scrollDisabled(true)
            .loadingPlaceholder()
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
            ScrollViewReader { scrolling in
                resultList
                .hayakiScrollBackground()
                .listStyle(.plain)
                .accessibilityIdentifier("browse-results")
                .refreshable { await model.refreshResults() }
                .task(id: model.generation) {
                    guard let cardID = initialCardID else { return }
                    let rowID = await model.rowID(forCard: cardID)
                    guard !Task.isCancelled else { return }
                    initialCardID = nil
                    if let rowID { scrolling.scrollTo(rowID, anchor: .center) }
                }
            }
        }
    }
    /// One list throughout, so entering or leaving selection keeps its scroll
    /// position. While selecting it selects many rows; beside a detail column
    /// (iPad) it selects the one row shown there; otherwise rows open.
    private var resultList: some View {
        List(model.rowIDs, id: \.self, selection: listSelection) { rowID in
            row(rowID)
                .accessibilityIdentifier(rowID == model.rowIDs.last ? "browse-last-result" : "browse-result")
        }
    }

    private var listSelection: Binding<Set<Int64>>? {
        if isSelecting { return $model.selection }
        guard showsDetailColumn else { return nil }
        return Binding {
            focusedRow.map { [$0] } ?? []
        } set: { rows in
            focusedRow = rows.first { $0 != focusedRow } ?? rows.first
        }
    }

    @ViewBuilder
    private func row(_ rowID: Int64) -> some View {
        let row = CardRowView(model: model, cardID: rowID, truncates: truncatesRows)
        if isSelecting {
            row.tag(rowID)
        } else if showsDetailColumn {
            row.tag(rowID)
                .contextMenu { rowMenu(rowID) }
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
            .contextMenu { rowMenu(rowID) }
        }
    }

    @ViewBuilder
    private func rowMenu(_ rowID: Int64) -> some View {
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

private enum BrowseSheet: Identifiable {
    case filters, columns, savedSearches, flags, editing(Int64), preview([Int64]), addNote
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
        case .addNote: 9
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
        // The learner's name for the flag, or "Red flag" and so on.
        guard let flag = row?.flag else { return nil }
        return model.flagNames[flag].map { Text(verbatim: $0) } ?? flag.label
    }

    private struct RowVersion: Hashable {
        let cardID: Int64
        let generation: Int
    }
}

/// A row: the sort field, then the deck and due date, then any other shown
/// columns. A flagged card has a bar of its flag's color along the leading
/// edge, and a suspended card is dimmed.
private struct CardRowContent: View {
    let row: CardRow?
    let columns: [BrowserColumn]
    let truncates: Bool
    let flagLabel: Text?
    @AppStorage(AppearanceSettings.browseMediaFilenamesKey) private var showsMediaFilenames = false
    @AppStorage(AppearanceSettings.browseTextScaleKey) private var textScale = 1.0
    @ScaledMetric(relativeTo: .body) private var primarySize = 17.0
    @ScaledMetric(relativeTo: .subheadline) private var secondarySize = 15.0
    @ScaledMetric(relativeTo: .footnote) private var detailSize = 13.0
    @ScaledMetric(relativeTo: .body) private var barWidth = 4.0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            flagBar
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: primaryText)
                    .font(.system(size: primarySize * textScale))
                    .lineLimit(truncates ? 2 : nil)
                if let secondaryText {
                    Text(verbatim: secondaryText)
                        .font(.system(size: secondarySize * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(truncates ? 1 : nil)
                }
                if !details.isEmpty {
                    Text(verbatim: details.joined(separator: "  ·  "))
                        .font(.system(size: detailSize * textScale))
                        .foregroundStyle(.tertiary)
                        .lineLimit(truncates ? 1 : nil)
                }
            }
            Spacer(minLength: 0)
            if let row, let badge = MarkBadge(mark: row.mark) {
                badge
            }
        }
        .padding(.vertical, 4)
        .opacity(row?.isDimmed == true ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(stateLabel ?? Text(verbatim: ""))
    }

    /// A rounded bar of the flag's color, or an empty space of the same width
    /// so every row's text lines up.
    private var flagBar: some View {
        RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(row?.flag?.color ?? .clear)
            .frame(width: barWidth)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    /// The flag or suspension, which the bar and dimming show, for VoiceOver.
    private var stateLabel: Text? {
        if let flagLabel { return flagLabel }
        if row?.isDimmed == true { return Text("Suspended", bundle: .module) }
        return nil
    }

    private var primaryText: String {
        // Placeholder text while the row loads, redacted by the caller.
        guard let row else { return "Loading card" }
        let text = row.displayText(for: CardRow.sortFieldColumn, showsMediaFilenames: showsMediaFilenames)
        return text.isEmpty ? (row.question.isEmpty ? "–" : row.question) : text
    }

    private var secondaryText: String? {
        guard let row else { return "Deck · due" }
        let parts = [row.deck, row.due].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var details: [String] {
        guard let row else { return [] }
        return row.detailColumns(columns).compactMap { column in
            let value = row.displayText(for: column.id, showsMediaFilenames: showsMediaFilenames)
            return value.isEmpty ? nil : "\(column.label): \(value)"
        }
    }
}

/// Beside the list on iPad: a preview of the selected card, from which the
/// learner can also edit its note.
private struct BrowseDetailPane: View {
    let store: CollectionStore
    let model: CardBrowserModel
    let rowID: Int64?
    @State private var cardID: Int64?

    var body: some View {
        Group {
            if let cardID {
                BrowserPreviewScreen(store: store, cardIDs: [cardID], isEmbedded: true)
                    .id(cardID)
            } else {
                ContentUnavailableView {
                    Label {
                        Text("No Card Selected", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.on.rectangle")
                    }
                } description: {
                    Text("Select a card to preview it here.", bundle: .module)
                }
            }
        }
        .task(id: rowID) {
            guard let rowID else {
                cardID = nil
                return
            }
            let resolved = await model.cardID(forRow: rowID)
            if !Task.isCancelled { cardID = resolved }
        }
    }
}

/// A small symbol for a marked or buried card. (A row shows a flag as a
/// colored bar and a suspended card dimmed instead.)
struct MarkBadge: View {
    let symbol: String
    let color: Color
    let label: Text

    init?(mark: CardRow.Mark) {
        switch mark {
        case .none, .flag, .suspended:
            return nil
        case .marked:
            symbol = "star.fill"
            color = .purple
            label = Text("Marked", bundle: .module)
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
