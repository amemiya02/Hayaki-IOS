import XCTest

@MainActor
final class WelcomeUITests: XCTestCase {
    func testFreshCollectionOffersEntryPathsAndRemembersStartingEmpty() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_EMPTY_COLLECTION"] = UUID().uuidString
        app.launch()

        let startEmpty = app.buttons["Start Empty"]
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 30), "A fresh collection opens Welcome")
        XCTAssertTrue(app.descendants(matching: .any)["shared-decks"].firstMatch.exists)

        app.buttons["Import a Package…"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Import opens the Files picker")
        cancel.tap()
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 10))

        app.buttons["shared-decks"].tap()
        XCTAssertTrue(app.navigationBars["Get Shared Decks"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Import Downloaded Deck"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 10))

        app.buttons["Set Up Sync"].tap()
        XCTAssertTrue(app.navigationBars["Sync"].waitForExistence(timeout: 10))
        app.navigationBars["Sync"].buttons.matching(NSPredicate(format: "label != %@", "Done")).firstMatch.tap()
        XCTAssertTrue(startEmpty.waitForExistence(timeout: 10))

        startEmpty.tap()
        XCTAssertTrue(app.staticTexts["No Cards Yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["shared-decks"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Import a Package…"].firstMatch.exists)
        XCTAssertTrue(app.buttons["New Deck"].firstMatch.exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No Cards Yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(startEmpty.exists)
    }
}
