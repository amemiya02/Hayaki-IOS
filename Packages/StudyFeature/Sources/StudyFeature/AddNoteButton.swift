import SwiftUI

/// Opens the note editor for adding a note. The app sets it on its tab view
/// (see `addNoteAction(store:)` in NoteEditorFeature), so screens that cannot
/// depend on the note editor can still offer Add Note.
public struct AddNoteAction: Sendable {
    let action: @MainActor @Sendable () -> Void

    public init(_ action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    @MainActor
    public func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry public var addNote: AddNoteAction?
}

/// The `+` toolbar button that adds a note. Without an explicit action it
/// uses the environment's `addNote`, and is disabled when there is none.
public struct AddNoteButton: View {
    @Environment(\.addNote) private var environmentAction
    private let action: (@MainActor () -> Void)?

    public init(action: (@MainActor () -> Void)? = nil) {
        self.action = action
    }

    public var body: some View {
        Button {
            if let action { action() } else { environmentAction?() }
        } label: {
            Label {
                Text("Add Note", bundle: .module)
            } icon: {
                Image(systemName: "plus")
            }
        }
        .disabled(action == nil && environmentAction == nil)
        .accessibilityIdentifier("add-note")
    }
}
