import AnkiCore
import SwiftUI

enum BrowserActionPrompt: String, Identifiable {
    case tags, dueDate, reset, reposition, grade, replace

    var id: Self { self }

    var title: Text {
        switch self {
        case .tags: Text("Edit Tags", bundle: .module)
        case .dueDate: Text("Set Due Date", bundle: .module)
        case .reset: Text("Reset Progress", bundle: .module)
        case .reposition: Text("Reposition", bundle: .module)
        case .grade: Text("Grade Now", bundle: .module)
        case .replace: Text("Find and Replace", bundle: .module)
        }
    }
}

struct BrowserActionSheet: View {
    let prompt: BrowserActionPrompt
    let model: CardBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var replacement = ""
    @State private var field = ""
    @State private var tagField = false
    @State private var fields: [String] = []
    @State private var removeTags = false
    @State private var start: UInt32 = 1
    @State private var step: UInt32 = 1
    @State private var restorePosition = true
    @State private var resetCounts = false
    @State private var randomize = false
    @State private var shiftExisting = false
    @State private var matchCase = false
    @State private var regex = false
    @State private var onlySelection: Bool
    @State private var startedWithSelection: Bool

    init(prompt: BrowserActionPrompt, model: CardBrowserModel) {
        self.prompt = prompt
        self.model = model
        let startedWithSelection = !model.selection.isEmpty
        _startedWithSelection = State(initialValue: startedWithSelection)
        _onlySelection = State(initialValue: startedWithSelection)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch prompt {
                case .tags:
                    Picker(selection: $removeTags) {
                        Text("Add", bundle: .module).tag(false)
                        Text("Remove", bundle: .module).tag(true)
                    } label: {
                        Text("Action", bundle: .module)
                    }
                    TextField(text: $text) {
                        Text("Tags", bundle: .module)
                    }
                    Text("Separate tags with spaces.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .dueDate:
                    TextField(text: $text) {
                        Text("Days from Today", bundle: .module)
                    }
                    Text("Enter a number of days or a range such as 3-7. Add ! to reset the interval.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .reset:
                    Toggle(isOn: $restorePosition) { Text("Restore Original Position", bundle: .module) }
                    Toggle(isOn: $resetCounts) { Text("Reset Review and Lapse Counts", bundle: .module) }
                case .reposition:
                    TextField(value: $start, format: .number.grouping(.never)) {
                        Text("Starting Position", bundle: .module)
                    }
                    TextField(value: $step, format: .number.grouping(.never)) {
                        Text("Step", bundle: .module)
                    }
                    Toggle(isOn: $randomize) { Text("Randomize Order", bundle: .module) }
                    Toggle(isOn: $shiftExisting) { Text("Shift Existing Cards", bundle: .module) }
                    Text("Only new cards outside filtered decks can be repositioned.", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .grade:
                    ForEach([CardDetail.Review.Rating.again, .hard, .good, .easy], id: \.rawValue) { rating in
                        Button { apply(.grade(rating)) } label: { rating.title }
                    }
                case .replace:
                    TextField(text: $text) { Text("Find", bundle: .module) }
                    TextField(text: $replacement) { Text("Replace With", bundle: .module) }
                    Picker(selection: $tagField) {
                        Text("Note Fields", bundle: .module).tag(false)
                        Text("Tags", bundle: .module).tag(true)
                    } label: { Text("Search In", bundle: .module) }
                    if !tagField {
                        Picker(selection: $field) {
                            Text("All Fields", bundle: .module).tag("")
                            ForEach(fields, id: \.self) { Text(verbatim: $0).tag($0) }
                        } label: { Text("Field", bundle: .module) }
                    }
                    Toggle(isOn: $regex) { Text("Regular Expression", bundle: .module) }
                    Toggle(isOn: $matchCase) { Text("Match Case", bundle: .module) }
                    if startedWithSelection {
                        Toggle(isOn: $onlySelection) { Text("Selected Notes Only", bundle: .module) }
                    } else {
                        Text("This action searches the entire collection.", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(prompt.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                if let action {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { apply(action) } label: { Text("Apply", bundle: .module) }
                            .disabled(isInvalid)
                    }
                }
            }
            .task { await loadDefaults() }
        }
    }

    private var action: BulkAction? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch prompt {
        case .tags: removeTags ? .removeTags(input) : .addTags(input)
        case .dueDate: .setDueDate(input)
        case .reset: .resetProgress(restorePosition: restorePosition, resetCounts: resetCounts)
        case .reposition: .reposition(start: start, step: step, randomize: randomize, shiftExisting: shiftExisting)
        case .grade: nil
        case .replace:
            .findAndReplace(search: text, replacement: replacement, field: tagField ? "" : field,
                tags: tagField, regex: regex, matchCase: matchCase, onlySelection: onlySelection)
        }
    }

    private var isInvalid: Bool {
        switch prompt {
        case .tags, .dueDate: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .replace: text.isEmpty || (onlySelection && model.selection.isEmpty)
        case .reposition: step == 0
        case .reset, .grade: false
        }
    }

    private func apply(_ action: BulkAction) {
        dismiss()
        Task { await model.perform(action) }
    }

    private func loadDefaults() async {
        let core = model.store.core
        switch prompt {
        case .dueDate:
            let previous = try? await core.getConfigString(.with { $0.key = .setDueBrowser }).val
            if text.isEmpty { text = previous ?? "" }
        case .reset:
            if let stored = try? await core.scheduleCardsAsNewDefaults(.with { $0.context = .browser }) {
                restorePosition = stored.restorePosition
                resetCounts = stored.resetCounts
            }
        case .reposition:
            if let stored = try? await core.repositionDefaults() {
                randomize = stored.random
                shiftExisting = stored.shift
            }
        case .replace:
            let names = (try? await core.getNotetypeNames().entries) ?? []
            var fetched: Set<String> = []
            for entry in names {
                if let columns = try? await core.getFieldNames(.with { $0.ntid = entry.id }).vals {
                    fetched.formUnion(columns)
                }
            }
            fields = fetched.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case .tags, .grade:
            break
        }
    }
}

extension CardDetail.Review.Rating {
    var title: Text {
        switch self {
        case .again: Text("Again", bundle: .module)
        case .hard: Text("Hard", bundle: .module)
        case .good: Text("Good", bundle: .module)
        case .easy: Text("Easy", bundle: .module)
        }
    }
}
