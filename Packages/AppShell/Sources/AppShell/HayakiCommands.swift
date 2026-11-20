import StudyFeature
import SwiftUI

/// The app's menu commands: Add Note (Command-N) and the Study menu with the
/// reviewer's keyboard shortcuts. Listing them here puts every shortcut in the
/// iPad menu bar and the shortcut overlay shown while holding Command.
public struct HayakiCommands: Commands {
    public init() {}

    public var body: some Commands {
        AddNoteCommands()
        StudyCommands()
    }
}
