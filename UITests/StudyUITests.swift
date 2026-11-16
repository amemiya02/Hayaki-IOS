import XCTest

/// Studying in the assembled app: the deck list, the full-screen study screen
/// and the card drawn in its web view.
///
/// The app starts from a throwaway copy of the fixture collection package
/// (see `UITestLaunch` in AppShell), whose Geography deck has new Cloze
/// cards. Screens are attached to the test results for review.
@MainActor
final class StudyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        let package = try XCTUnwrap(
            Bundle(for: StudyUITests.self).url(forResource: "collection", withExtension: "colpkg"),
            "The fixture collection package is missing from the UI test bundle"
        )
        // On an iPad, landscape: the sidebar sits beside the deck list rather
        // than over it.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = package.path
        app.launch()
    }

    func testOpeningADeckRevealingAndRatingACard() throws {
        openDeck("Geography")
        let counts = app.descendants(matching: .any)["study-counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 20))
        let countsBefore = counts.label
        XCTAssertTrue(countsBefore.hasSuffix("due left"), countsBefore)
        // A Cloze card's question is drawn in the web view, with its deletion
        // hidden. Generous: the web view's first page load can take many
        // seconds on a busy machine.
        let hiddenDeletion = app.webViews.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "[...]")).firstMatch
        XCTAssertTrue(hiddenDeletion.waitForExistence(timeout: 60), "The question is drawn")
        attachScreen("1 question")

        app.buttons["show-answer"].tap()
        let good = app.buttons["rating-good"]
        XCTAssertTrue(good.waitForExistence(timeout: 10))
        // The answer side fills the deletion in.
        XCTAssertTrue(hiddenDeletion.waitForNonExistence(timeout: 30), "The answer is drawn")
        XCTAssertTrue(app.webViews.staticTexts.firstMatch.exists, "The answer is drawn")
        for rating in ["again", "hard", "good", "easy"] {
            XCTAssertTrue(app.buttons["rating-\(rating)"].exists)
            XCTAssertFalse(app.buttons["rating-\(rating)"].value as? String ?? "" == "", "\(rating) shows an interval")
        }
        attachScreen("2 answer")

        good.tap()
        // The session moves on: the next question, and the counts drop.
        XCTAssertTrue(app.buttons["show-answer"].waitForExistence(timeout: 10))
        XCTAssertNotEqual(counts.label, countsBefore)
        attachScreen("3 next question")
    }

    func testStudyingADeckToTheEnd() throws {
        openDeck("Geography")
        let allDone = app.staticTexts["All Done for Today"]
        var reviews = 0
        // Easy takes each card out of today's study, so the deck runs out.
        while !allDone.waitForExistence(timeout: 3) {
            XCTAssertTrue(app.buttons["show-answer"].waitForExistence(timeout: 20))
            app.buttons["show-answer"].tap()
            XCTAssertTrue(app.buttons["rating-easy"].waitForExistence(timeout: 10))
            app.buttons["rating-easy"].tap()
            reviews += 1
            XCTAssertLessThan(reviews, 6, "The session should end")
        }
        XCTAssertGreaterThan(reviews, 0)
        let summary = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "You reviewed \(reviews) card"))
        XCTAssertTrue(summary.firstMatch.exists)
        attachScreen("4 summary")

        app.buttons["Done"].tap()
        let geography = deckRow("Geography")
        XCTAssertTrue(geography.waitForExistence(timeout: 10))
        // The deck list shows the finished deck's current counts.
        XCTAssertTrue(geography.label.contains("0 new, 0 learning, 0 due"), geography.label)
        attachScreen("5 deck list after")

        geography.tap()
        XCTAssertTrue(app.staticTexts["This deck has nothing left to study today."].waitForExistence(timeout: 10))
        attachScreen("6 nothing left")
    }

    private func deckRow(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func openDeck(_ name: String) {
        let row = deckRow(name)
        XCTAssertTrue(row.waitForExistence(timeout: 60), "The deck list shows \(name)")
        attachScreen("0 deck list")
        row.tap()
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
