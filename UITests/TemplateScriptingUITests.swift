import XCTest

@MainActor
final class TemplateScriptingUITests: XCTestCase {
    func testQueueRevealAndRateThroughTheTemplateBridge() throws {
        let app = try launchFixture()
        let deck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Template Scripts")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 30))
        deck.tap()

        let card = app.webViews.firstMatch
        XCTAssertTrue(card.staticTexts["Script queue: 1"].waitForExistence(timeout: 20))
        let scriptInput = card.textFields["Script input"]
        XCTAssertTrue(scriptInput.waitForExistence(timeout: 10))
        card.buttons["Script Focus"].tap()
        scriptInput.typeText("hello")
        XCTAssertEqual(scriptInput.value as? String, "hello")

        card.buttons["Script Reveal"].tap()
        XCTAssertTrue(card.staticTexts["Script answer: true"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["rating-easy"].exists)
        card.buttons["Script Rate"].tap()
        XCTAssertTrue(app.staticTexts["All Done for Today"].waitForExistence(timeout: 20))
    }

    private func launchFixture() throws -> XCUIApplication {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "template-scripts", withExtension: "colpkg"))
        let app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = fixture.path
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }
}
