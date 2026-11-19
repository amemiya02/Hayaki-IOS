import XCTest

@MainActor
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        let package = try XCTUnwrap(
            Bundle(for: NavigationUITests.self).url(forResource: "collection", withExtension: "colpkg")
        )
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = package.path
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()
    }

    func testStudySelectionSurvivesSectionSwitchesAndImportPicker() {
        let vocabulary = deckRow("Vocabulary")
        XCTAssertTrue(vocabulary.waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["due-today"].exists)
        XCTAssertTrue(app.staticTexts["studied-today"].exists)
        vocabulary.tap()

        let showAnswer = app.buttons["show-answer"]
        XCTAssertTrue(showAnswer.waitForExistence(timeout: 20))
        app.buttons["Close"].tap()

        let study = app.buttons["study-selected-deck"]
        XCTAssertTrue(study.waitForExistence(timeout: 10))
        XCTAssertEqual(study.label, "Study Now · Vocabulary")

        select("Browse")
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 10))
        select("Stats")
        XCTAssertTrue(app.navigationBars["Statistics"].waitForExistence(timeout: 10))
        select("More")
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 10))
        select("Decks")
        XCTAssertTrue(study.waitForExistence(timeout: 10))
        XCTAssertEqual(study.label, "Study Now · Vocabulary")

        app.navigationBars["Decks"].buttons["Import a Package…"].tap()
        app.cancelFilesPicker()
        XCTAssertTrue(study.waitForExistence(timeout: 10))
        XCTAssertEqual(study.label, "Study Now · Vocabulary")
        attachScreen("Decks after returning from More and Files")

        study.tap()
        XCTAssertTrue(showAnswer.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Vocabulary"].exists)
    }

    func testNestedDeckCanBeCreatedAndRenamedFromADeckMenu() {
        let parent = deckRow("Languages")
        XCTAssertTrue(parent.waitForExistence(timeout: 60))
        parent.press(forDuration: 1.2)
        let createInside = app.buttons["New Deck Inside"]
        XCTAssertTrue(createInside.waitForExistence(timeout: 10))
        createInside.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Phrases")
        app.buttons["Create"].tap()

        let child = deckRow("Phrases")
        XCTAssertTrue(child.waitForExistence(timeout: 15))
        child.press(forDuration: 1.2)
        app.buttons["Rename"].tap()
        let rename = app.alerts["Rename Deck"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        let renamed = rename.textFields.firstMatch
        renamed.tap()
        renamed.typeText(" and idioms")
        rename.buttons["Rename"].tap()
        XCTAssertTrue(deckRow("Phrases and idioms").waitForExistence(timeout: 10))
        attachScreen("Nested deck after rename")
    }

    func testBrowsePreviewNavigatesAndEditsTheShownCard() {
        select("Browse")
        let browseOptions = app.buttons["Browse Options"]
        XCTAssertTrue(browseOptions.waitForExistence(timeout: 15))
        browseOptions.tap()
        let previewAction = app.buttons["Preview"]
        XCTAssertTrue(previewAction.waitForExistence(timeout: 10))
        previewAction.tap()

        let question = app.buttons["Show Answer"]
        let answer = app.buttons["Show Question"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertTrue(question.isEnabled)
        app.buttons["Next Card"].tap()
        XCTAssertTrue(answer.waitForExistence(timeout: 5))

        let options = app.buttons["Preview Options"]
        options.tap()
        app.buttons["Mark Note"].tap()
        options.tap()
        XCTAssertTrue(app.buttons["Unmark Note"].exists)
        app.buttons["Edit Note"].tap()
        XCTAssertTrue(app.navigationBars["Edit Note"].waitForExistence(timeout: 10))
        app.navigationBars["Edit Note"].buttons["Close"].tap()
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        app.buttons["Previous Card"].tap()
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        attachScreen("Browse preview with the selected card")
    }

    private func select(_ section: String) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let entry = app.staticTexts[section].firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10), "The iPad sidebar shows \(section)")
            entry.tap()
        } else {
            let tab = app.tabBars.buttons[section]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "The iPhone tab bar shows \(section)")
            tab.tap()
        }
    }

    private func deckRow(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
