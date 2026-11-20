import AppIntents
import AppShell

/// Opens Hayaki on the note editor for the active profile, as the `+`
/// buttons do. Offered in Spotlight, Siri and Shortcuts through
/// `HayakiShortcuts`.
struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Note"
    static let description = IntentDescription("Opens the note editor to add a note to your collection.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AddNoteOpener.shared.request()
        return .result()
    }
}

struct HayakiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddNoteIntent(),
            phrases: [
                "Add a note in \(.applicationName)",
                "Add a \(.applicationName) note",
                "New note in \(.applicationName)",
            ],
            shortTitle: "Add Note",
            systemImageName: "plus"
        )
    }
}
