import XCTest

/// Deck options in the assembled app: opened from a deck's context menu,
/// mistyped steps rejected, and a new daily limit shown in the deck list once
/// saved.
///
/// The app starts from a throwaway copy of the fixture collection package
/// (see `UITestLaunch` in AppShell). Screens are attached to the test results
/// for review.
@MainActor
final class DeckOptionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        let package = try XCTUnwrap(
            Bundle(for: DeckOptionsUITests.self).url(forResource: "collection", withExtension: "colpkg"),
            "The fixture collection package is missing from the UI test bundle"
        )
        app = XCUIApplication()
        // English labels below, whatever the simulator's language.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = package.path
        app.launch()
    }

    func testChangingADecksNewCardLimit() throws {
        let geography = deckRow("Geography")
        XCTAssertTrue(geography.waitForExistence(timeout: 60), "The deck list shows Geography")
        XCTAssertFalse(geography.label.contains("1 new,"), geography.label)

        geography.press(forDuration: 1.2)
        let options = app.buttons["Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 10), "The deck's menu offers its options")
        attachScreen("1 deck menu")
        options.tap()

        let newCards = app.textFields["new-cards-per-day"]
        XCTAssertTrue(newCards.waitForExistence(timeout: 20), "Deck options show the daily limits")
        // Every deck of the fixture uses the Default preset.
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Used by")).firstMatch.exists,
            "The preset says that other decks share it"
        )
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Nothing to save yet")
        attachScreen("2 deck options")

        // Mistyped learning steps are rejected, and Save is unavailable.
        let steps = app.textFields["learning-steps"]
        replaceText(of: steps, with: "1m nope")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "“nope” is not a step")).firstMatch
                .waitForExistence(timeout: 5),
            "The mistake is named"
        )
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        attachScreen("3 invalid steps")
        replaceText(of: steps, with: "1m 10m")

        replaceText(of: newCards, with: "1")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()

        // Saved: the sheet closes and the deck shows at most one new card.
        XCTAssertTrue(newCards.waitForNonExistence(timeout: 20), "The sheet closes once saved")
        let updated = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Geography", "1 new,")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 20), deckRow("Geography").label)
        attachScreen("4 deck list after")
    }

    private func deckRow(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// Replaces a field's text: taps at its trailing end and deletes what is there.
    private func replaceText(of field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        field.typeText(text)
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
