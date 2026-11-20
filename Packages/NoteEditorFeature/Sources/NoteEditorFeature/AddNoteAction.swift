import CollectionStore
import StudyFeature
import SwiftUI

public extension View {
    /// Lets every section of a tab view add a note: sets the `addNote`
    /// environment action that `AddNoteButton` uses and the focused value
    /// behind `AddNoteCommands` (Command-N), and shows the note editor as a sheet.
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
            // Command-N from any section, through the app's File menu.
            .focusedSceneValue(\.addNote, AddNoteAction { isAdding = true })
            .sheet(isPresented: $isAdding) {
                NoteEditorScreen(store: store)
            }
    }
}
