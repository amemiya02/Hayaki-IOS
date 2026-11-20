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
        XCTAssertTrue(app.buttons["study-all"].exists)
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

        app.navigationBars["Decks"].buttons["deck-list-options"].tap()
        let importPackage = app.buttons["Import a Package…"]
        XCTAssertTrue(importPackage.waitForExistence(timeout: 10))
        importPackage.tap()
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

    func testBrowseSearchAndLastResultClearTheToolbars() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This case verifies the iPhone tab and navigation bars.")
        }
        select("Browse")
        let navigation = app.navigationBars["Browse"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        let mode = app.segmentedControls["browse-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertTrue(mode.isHittable)
        let results = app.descendants(matching: .any)["browse-results"]
        XCTAssertTrue(results.waitForExistence(timeout: 10))

        // Search uses the system's default placement, which may tuck the
        // field under the title until the list is pulled down.
        let search = app.searchFields.firstMatch
        if !(search.exists && search.isHittable) {
            results.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(search.isHittable)
        XCTAssertFalse(search.frame.intersects(mode.frame))

        results.swipeUp(velocity: .fast)
        results.swipeUp(velocity: .fast)
        let lastResult = results.descendants(matching: .any)["browse-last-result"].firstMatch
        XCTAssertTrue(lastResult.waitForExistence(timeout: 10))
        XCTAssertTrue(lastResult.isHittable)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(lastResult.frame.maxY, tabBar.frame.minY + 1)
        // A search field at the bottom of the screen must not cover the
        // last result either.
        if search.exists, search.frame.minY > results.frame.midY {
            XCTAssertLessThanOrEqual(lastResult.frame.maxY, search.frame.minY + 1)
        }
        attachScreen("Browse search and last result clear of the toolbars")
    }

    func testTabRootsFollowTheToolbarRuleAndAddNoteOpensFromToolbarsAndKeyboard() {
        XCTAssertTrue(deckRow("Vocabulary").waitForExistence(timeout: 60))
        let decksBar = app.navigationBars["Decks"]
        XCTAssertTrue(decksBar.buttons["deck-sync"].exists)
        XCTAssertTrue(decksBar.buttons["deck-list-options"].exists)
        XCTAssertFalse(decksBar.buttons["Import a Package…"].exists)
        // Add Note is a toolbar button, not a bar above the tab bar.
        let addNoteOutsideBars = app.buttons.matching(NSPredicate(format: "label == %@", "Add Note")).allElementsBoundByIndex
            .filter { !decksBar.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.isHittable }
        XCTAssertTrue(addNoteOutsideBars.isEmpty)
        decksBar.buttons["add-note"].tap()
        closeAddNote()

        select("Browse")
        let browseBar = app.navigationBars["Browse"]
        XCTAssertTrue(browseBar.waitForExistence(timeout: 10))
        XCTAssertTrue(browseBar.buttons["Browse Options"].exists)
        browseBar.buttons["add-note"].tap()
        closeAddNote()

        select("Stats")
        let statsBar = app.navigationBars["Statistics"]
        XCTAssertTrue(statsBar.waitForExistence(timeout: 10))
        XCTAssertTrue(statsBar.buttons["statistics-options"].exists)
        app.typeKey("n", modifierFlags: .command)
        closeAddNote()

        select("More")
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 10))
        let syncRow = app.buttons["sync-settings"].firstMatch
        XCTAssertTrue(syncRow.waitForExistence(timeout: 10))
        syncRow.tap()
        let sync = app.navigationBars["Sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 10))
        // An inline title shares the back button's row.
        let title = sync.staticTexts["Sync"]
        let back = sync.buttons.firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(abs(title.frame.midY - back.frame.midY), 12)
        attachScreen("More → Sync with an inline title")
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

    private func closeAddNote() {
        let editor = app.navigationBars["Add Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.buttons["Close"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
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
