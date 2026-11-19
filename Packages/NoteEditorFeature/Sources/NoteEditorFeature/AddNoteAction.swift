import CollectionStore
import StudyFeature
import SwiftUI

public extension View {
    /// Puts an Add Note button below every section of a tab view (above the
    /// tab bar on iPhone, at the foot of the sidebar on iPad), with Command-N
    /// on a hardware keyboard, and shows the note editor as a sheet.
    /// Apply it to the app's `TabView`.
    func addNoteAction(store: CollectionStore) -> some View {
        modifier(AddNoteAction(store: store))
            .studyNoteEditor { cardID in
                NoteEditorScreen(store: store, editingCardID: cardID)
            }
    }
}

private struct AddNoteAction: ViewModifier {
    let store: CollectionStore
    @State private var isAdding = false

    func body(content: Content) -> some View {
        content
            .bottomAccessory { button }
            .sheet(isPresented: $isAdding) {
                NoteEditorScreen(store: store)
            }
    }

    private var button: some View {
        Button {
            isAdding = true
        } label: {
            Label {
                Text("Add Note", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

private extension View {
    /// The tab view's bottom accessory exists only on iOS; the package also
    /// builds for macOS so its tests run there.
    @ViewBuilder
    func bottomAccessory(@ViewBuilder _ accessory: () -> some View) -> some View {
        #if os(iOS)
        tabViewBottomAccessory(content: accessory)
        #else
        self
        #endif
    }
}
