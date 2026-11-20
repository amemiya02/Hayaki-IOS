import CollectionStore
import StudyFeature
import SwiftUI

public extension View {
    /// Lets every section of a tab view add a note: sets the `addNote`
    /// environment action that `AddNoteButton` uses, adds Command-N on a
    /// hardware keyboard, and shows the note editor as a sheet.
    /// Apply it to the app's `TabView`.
    func addNoteAction(store: CollectionStore) -> some View {
        modifier(AddNoteActionModifier(store: store))
            .studyNoteEditor { cardID in
                NoteEditorScreen(store: store, editingCardID: cardID)
            }
    }
}

private struct AddNoteActionModifier: ViewModifier {
    let store: CollectionStore
    @State private var isAdding = false

    func body(content: Content) -> some View {
        content
            .environment(\.addNote, AddNoteAction { isAdding = true })
            .background { keyboardShortcut }
            .sheet(isPresented: $isAdding) {
                NoteEditorScreen(store: store)
            }
    }

    /// Command-N from any section. The button is invisible: the visible
    /// entry points are the `+` buttons in Decks and Browse.
    private var keyboardShortcut: some View {
        Button {
            isAdding = true
        } label: {
            Text("Add Note", bundle: .module)
        }
        .keyboardShortcut("n", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
