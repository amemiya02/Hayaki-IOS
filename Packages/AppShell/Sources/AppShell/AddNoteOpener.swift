import Observation
import StudyFeature
import SwiftUI

/// Notices when the learner asks to add a note from outside the app (the
/// Home Screen quick action, or the App Shortcut from Spotlight and Siri), so
/// the app can open the note editor once the active profile's collection is
/// showing.
@MainActor
@Observable
public final class AddNoteOpener {
    public static let shared = AddNoteOpener()

    /// The type of the Add Note Home Screen quick action, as declared under
    /// `UIApplicationShortcutItems` in the app's Info.plist.
    public static let quickActionType = "io.github.amemiya02.hayaki.add-note"

    /// The learner asked to add a note and the editor has not opened for it yet.
    public private(set) var isRequested = false

    public init() {}

    /// Opens the note editor as soon as the app can show it.
    public func request() {
        isRequested = true
    }

    /// Handles a Home Screen quick action. Returns whether it was one of
    /// Hayaki's.
    @discardableResult
    public func open(quickActionType type: String) -> Bool {
        guard type == Self.quickActionType else { return false }
        request()
        return true
    }

    /// Clears the request, returning whether there was one.
    public func takeRequest() -> Bool {
        defer { isRequested = false }
        return isRequested
    }
}

extension View {
    /// Opens the note editor through the environment's `addNote` action when
    /// `opener` has a request. Apply it inside `addNoteAction(store:)`, so the
    /// action is in the environment.
    func openingAddNoteRequests(from opener: AddNoteOpener) -> some View {
        modifier(AddNoteRequestHandler(opener: opener))
    }
}

private struct AddNoteRequestHandler: ViewModifier {
    let opener: AddNoteOpener
    @Environment(\.addNote) private var addNote

    func body(content: Content) -> some View {
        content
            .onChange(of: opener.isRequested, initial: true) { _, requested in
                guard requested, let addNote, opener.takeRequest() else { return }
                addNote()
            }
    }
}
