import SwiftUI

struct BrowserSavedSearchesSheet: View {
    let model: CardBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                if model.state == .loaded, !model.searchedText.isEmpty {
                    Section {
                        TextField(text: $name) {
                            Text("Search Name", bundle: .module)
                        }
                        Button {
                            let name = trimmedName
                            Task {
                                await model.saveSearch(named: name)
                                if model.failure == nil { self.name = "" }
                            }
                        } label: {
                            Text("Save Current Search", bundle: .module)
                        }
                        .disabled(trimmedName.isEmpty || model.savedSearches.contains { $0.name == trimmedName })
                    }
                }
                Section {
                    if model.savedSearches.isEmpty {
                        Text("No Saved Searches", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.savedSearches) { search in
                        Button {
                            dismiss()
                            Task { await model.openSavedSearch(search) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: search.name)
                                Text(verbatim: search.query)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let names = offsets.map { model.savedSearches[$0].name }
                        Task {
                            for name in names { await model.removeSavedSearch(named: name) }
                        }
                    }
                }
            }
            .navigationTitle(Text("Saved Searches", bundle: .module))
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .automatic) { EditButton() }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            .task { await model.loadSavedSearches() }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}
