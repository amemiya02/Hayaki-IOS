import XCTest

/// The Home Screen Add Note quick action. SpringBoard's long-press menu is too
/// unreliable to drive from a UI test, so the app is launched as the quick
/// action would launch it (`HAYAKI_UI_TEST_QUICK_ACTION`).
@MainActor
final class AddNoteShortcutUITests: XCTestCase {
    func testAddNoteQuickActionOpensTheNoteEditorOnLaunch() throws {
        continueAfterFailure = false
        let package = try XCTUnwrap(
            Bundle(for: AddNoteShortcutUITests.self).url(forResource: "collection", withExtension: "colpkg")
        )
        let app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = package.path
        app.launchEnvironment["HAYAKI_UI_TEST_QUICK_ACTION"] = "io.github.amemiya02.hayaki.add-note"
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()

        let editor = app.navigationBars["Add Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        editor.buttons["Close"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Decks"].waitForExistence(timeout: 10))
    }
}
