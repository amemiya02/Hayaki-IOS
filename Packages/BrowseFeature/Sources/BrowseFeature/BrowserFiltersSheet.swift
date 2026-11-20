import SwiftUI

struct BrowserFiltersSheet: View {
    let model: CardBrowserModel
    @State private var query: String
    @State private var filters: [QuickFilter]
    @Environment(\.dismiss) private var dismiss

    init(model: CardBrowserModel) {
        self.model = model
        let draft = model.filterDraft
        _query = State(initialValue: draft.query)
        _filters = State(initialValue: draft.filters)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $query) {
                    Text("Anki Search", bundle: .module)
                }
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                choices(Text("Deck", bundle: .module), values: model.choices.decks, filter: QuickFilter.deck)
                choices(Text("Tag", bundle: .module), values: model.choices.tags, filter: QuickFilter.tag)
                choices(Text("Note Type", bundle: .module), values: model.choices.noteTypes, filter: QuickFilter.noteType)
                DisclosureGroup {
                    choice(.noFlag, Text("No Flag", bundle: .module))
                    choice(.anyFlag, Text("Any Flag", bundle: .module))
                    ForEach(CardRow.Flag.allCases, id: \.self) { flag in
                        choice(.flag(flag), model.flagName(flag))
                    }
                } label: {
                    Text("Flag", bundle: .module)
                }
                DisclosureGroup {
                    choice(.new, Text("New", bundle: .module))
                    choice(.learning, Text("Learning", bundle: .module))
                    choice(.review, Text("Review", bundle: .module))
                    choice(.buried, Text("Buried", bundle: .module))
                    choice(.suspended, Text("Suspended", bundle: .module))
                    choice(.dueToday, Text("Due Today", bundle: .module))
                    choice(.marked, Text("Marked", bundle: .module))
                } label: {
                    Text("Card State", bundle: .module)
                }
                Button {
                    filters.removeAll()
                } label: {
                    Text("Clear Filters", bundle: .module)
                }
                .disabled(filters.isEmpty)
            }
            .navigationTitle(Text("Filters", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let filters = filters
                        let query = query
                        dismiss()
                        Task { await model.applyFilters(filters, query: query) }
                    } label: { Text("Search", bundle: .module) }
                }
            }
        }
    }

    private func choices(_ title: Text, values: [String], filter: @escaping (String) -> QuickFilter) -> some View {
        DisclosureGroup {
            ForEach(values, id: \.self) { value in
                choice(filter(value), Text(verbatim: value))
            }
        } label: {
            title
        }
        .disabled(values.isEmpty)
    }

    private func choice(_ filter: QuickFilter, _ title: Text) -> some View {
        Toggle(isOn: Binding {
            filters.contains(filter)
        } set: { selected in
            if selected {
                filters.append(filter)
            } else {
                filters.removeAll { $0 == filter }
            }
        }) {
            title
        }
    }
}
