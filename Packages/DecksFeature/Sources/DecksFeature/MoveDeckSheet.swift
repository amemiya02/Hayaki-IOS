import AnkiCore
import SwiftUI

/// Lets the learner pick the deck to move a deck into, or the top level.
struct MoveDeckSheet: View {
    let model: DeckListModel
    let deck: DeckNode
    let onFailure: (CoreError) -> Void
    @State private var isMoving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    destination(nil) {
                        Label {
                            Text("Top Level", bundle: .module)
                        } icon: {
                            Image(systemName: "list.bullet.indent")
                        }
                    }
                }
                Section {
                    ForEach(model.parentChoices(excludingSubtreeOf: deck.id)) { choice in
                        destination(choice.id) {
                            Text(choice.name)
                                .padding(.leading, CGFloat(choice.depth) * 20)
                        }
                    }
                } header: {
                    Text("Decks", bundle: .module)
                }
            }
            .navigationTitle(Text("Move “\(deck.name)”", bundle: .module))
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
            }
            .disabled(isMoving)
        }
    }

    /// A row that moves the deck under `parentID` (nil: the top level), with
    /// a checkmark on where the deck is now.
    private func destination(_ parentID: DeckNode.ID?, @ViewBuilder label: () -> some View) -> some View {
        let isCurrent = model.parentID(of: deck.id) == parentID
        return Button {
            move(under: parentID)
        } label: {
            HStack {
                label()
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func move(under parentID: DeckNode.ID?) {
        guard model.parentID(of: deck.id) != parentID else {
            dismiss()
            return
        }
        isMoving = true
        Task {
            do throws(CoreError) {
                try await model.moveDeck(deck.id, under: parentID)
                dismiss()
            } catch {
                dismiss()
                onFailure(error)
            }
        }
    }
}
