import AnkiCore
import SwiftUI

/// Asks for a new deck's name and where it goes, then creates it.
struct NewDeckSheet: View {
    let model: DeckListModel
    let onFailure: (CoreError) -> Void
    @State private var name = ""
    @State private var parentID: DeckNode.ID?
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: DeckListModel, parentID: DeckNode.ID?, onFailure: @escaping (CoreError) -> Void) {
        self.model = model
        self.onFailure = onFailure
        _parentID = State(initialValue: parentID)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(text: $name) {
                    Text("Name", bundle: .module)
                }
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit(create)

                Picker(selection: $parentID) {
                    Text("None (Top Level)", bundle: .module)
                        .tag(DeckNode.ID?.none)
                    ForEach(model.parentChoices()) { choice in
                        Text(choice.fullName)
                            .tag(DeckNode.ID?.some(choice.id))
                    }
                } label: {
                    Text("Inside", bundle: .module)
                }
            }
            .navigationTitle(Text("New Deck", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: create) {
                        Text("Create", bundle: .module)
                    }
                    .disabled(DeckListModel.isBlank(name) || isSaving)
                }
            }
            .onAppear { isNameFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        guard !DeckListModel.isBlank(name), !isSaving else { return }
        isSaving = true
        Task {
            do throws(CoreError) {
                try await model.createDeck(named: name, inside: parentID)
                dismiss()
            } catch {
                dismiss()
                onFailure(error)
            }
        }
    }
}
