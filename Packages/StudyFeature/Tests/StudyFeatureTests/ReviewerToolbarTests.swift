import Foundation
@testable import StudyFeature
import Testing

@Suite("Reviewer toolbar")
struct ReviewerToolbarTests {
    private func decode(_ json: String) throws -> ReviewerPreferences {
        try JSONDecoder().decode(ReviewerPreferences.self, from: Data(json.utf8))
    }

    @Test("Saved top, bottom and hidden positions become Buttons in Bar or Menu Only")
    func migratesLegacyPosition() throws {
        #expect(try decode("{}").toolbarStyle == .buttonsInBar)
        #expect(try decode(#"{"toolbarPosition":"top"}"#).toolbarStyle == .buttonsInBar)
        #expect(try decode(#"{"toolbarPosition":"bottom"}"#).toolbarStyle == .buttonsInBar)
        #expect(try decode(#"{"toolbarPosition":"hidden"}"#).toolbarStyle == .menuOnly)
    }

    @Test("A saved style wins over a leftover position and survives saving")
    func savedStyleRoundTrips() throws {
        let saved = try decode(#"{"toolbarPosition":"hidden","toolbarStyle":"buttonsInBar"}"#)
        #expect(saved.toolbarStyle == .buttonsInBar)

        var preferences = ReviewerPreferences()
        preferences.toolbarStyle = .menuOnly
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any]
        #expect(object?["toolbarStyle"] as? String == "menuOnly")
        #expect(object?["toolbarPosition"] == nil)
        #expect(try JSONDecoder().decode(ReviewerPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }

    @Test("Buttons in Bar shows Undo in the bar and keeps Add Note in the menu")
    func buttonsInBarLayout() {
        let layout = ReviewerPreferences().toolbarLayout { _ in true }
        #expect(layout.bar == [.undo])
        #expect(layout.menu.contains(.addNote))
        #expect(!layout.menu.contains(.undo))
        #expect(!layout.menu.contains(.browse), "Actions the learner hid stay hidden")
    }

    @Test("Menu Only moves every bar action into the menu, in order")
    func menuOnlyLayout() {
        var preferences = ReviewerPreferences()
        preferences.toolbarStyle = .menuOnly
        preferences.toolbarVisibility[.flag] = .toolbar
        let layout = preferences.toolbarLayout { _ in true }
        #expect(layout.bar.isEmpty)
        #expect(Array(layout.menu.prefix(3)) == [.undo, .redo, .flag])
        #expect(layout.menu.contains(.addNote))
    }

    @Test("Unavailable actions are left out of both the bar and the menu")
    func unavailableActions() {
        let layout = ReviewerPreferences().toolbarLayout { $0 != .undo && $0 != .addNote }
        #expect(layout.bar.isEmpty)
        #expect(!layout.menu.contains(.addNote))
    }
}
