import XCTest

/// Cards with media, maths and typed answers in the assembled app, drawn in
/// the study screen's web view from the fixture collection package.
///
/// The fixture's Spanish cards hold the image (el sol) and the audio
/// (adiós), its Geography deck the MathJax cloze and its Vocabulary deck the
/// typed answers. The Spanish cards are made due today at launch
/// (`HAYAKI_UI_TEST_DUE_TODAY`, see `UITestLaunch` in AppShell), as the
/// fixture's scheduling would otherwise keep the image card for another day.
/// Screens are attached to the test results for review.
@MainActor
final class CardContentUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        let package = try XCTUnwrap(
            Bundle(for: CardContentUITests.self).url(forResource: "collection", withExtension: "colpkg"),
            "The fixture collection package is missing from the UI test bundle"
        )
        app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = package.path
        app.launchEnvironment["HAYAKI_UI_TEST_DUE_TODAY"] = "\"deck:Languages::Spanish\""
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func testImageAudioAndMaths() throws {
        app.launch()
        openDeck("Languages")
        var sawImage = false
        var sawAudio = false
        for _ in 0..<4 {
            let question = webText(containing: "")
            XCTAssertTrue(question.waitForExistence(timeout: 60), "The question is drawn")
            showAnswer()
            XCTAssertTrue(spanishAnswer.waitForExistence(timeout: 30), "The answer is drawn")
            if webText(containing: "the sun").exists {
                // The image comes from the media folder through the card
                // URL scheme, at a size that fits the screen.
                let image = app.webViews.images.firstMatch
                XCTAssertTrue(image.waitForExistence(timeout: 20), "The image is drawn")
                XCTAssertGreaterThan(image.frame.width, 20)
                XCTAssertLessThanOrEqual(image.frame.maxX, app.frame.maxX)
                attachScreen("card with an image")
                sawImage = true
            } else if webText(containing: "goodbye").exists {
                let replay = app.webViews.buttons["Play Audio"].firstMatch
                XCTAssertTrue(replay.waitForExistence(timeout: 20), "The audio has a replay button")
                attachScreen("card with audio")
                replay.tap()
                sawAudio = true
            }
            rate("easy")
            // The next card's question, without the last answer.
            _ = spanishAnswer.waitForNonExistence(timeout: 30)
            if sawImage && sawAudio { break }
        }
        XCTAssertTrue(sawImage, "Studied the card with the image")
        XCTAssertTrue(sawAudio, "Studied the card with audio")

        closeStudy()
        openDeck("Geography")
        var sawMaths = false
        for _ in 0..<3 {
            XCTAssertTrue(webText(containing: "").waitForExistence(timeout: 60), "The question is drawn")
            if webText(containing: "circle").exists {
                showAnswer()
                // MathJax, bundled with the app, has replaced the TeX.
                let tex = webText(containing: #"\pi"#)
                XCTAssertTrue(tex.waitForNonExistence(timeout: 30), "MathJax typesets the maths")
                XCTAssertTrue(webText(containing: "π").waitForExistence(timeout: 30), "The maths is drawn")
                attachScreen("card with maths")
                sawMaths = true
                break
            }
            showAnswer()
            rate("easy")
        }
        XCTAssertTrue(sawMaths, "Studied the card with maths")
    }

    func testTypingTheAnswer() throws {
        app.launch()
        openDeck("Vocabulary")
        let field = app.webViews.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 60), "A typed-answer card shows a text field")
        let isJapan = webText(containing: "Japan").exists
        field.tap()
        field.typeText(isJapan ? "Tokio" : "Jupiter")
        attachScreen("typing")
        field.typeText("\n")
        XCTAssertTrue(app.buttons["rating-good"].waitForExistence(timeout: 20), "Return shows the answer")
        // The core's comparison shows the expected answer.
        XCTAssertTrue(webText(containing: isJapan ? "Tokyo" : "Jupiter").waitForExistence(timeout: 20))
        attachScreen("comparison")
    }

    func testALongCardScrolls() throws {
        // At the largest text size the image card is taller than the screen.
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openDeck("Languages")
        for _ in 0..<4 {
            XCTAssertTrue(webText(containing: "").waitForExistence(timeout: 60), "The question is drawn")
            showAnswer()
            XCTAssertTrue(spanishAnswer.waitForExistence(timeout: 30), "The answer is drawn")
            if webText(containing: "the sun").exists {
                break
            }
            rate("easy")
            // The next card's question, without the last answer.
            _ = spanishAnswer.waitForNonExistence(timeout: 30)
        }
        let image = app.webViews.images.firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        attachScreen("long card top")
        let card = app.webViews.firstMatch
        card.swipeUp(velocity: .slow)
        card.swipeUp(velocity: .slow)
        attachScreen("long card scrolled")
        // Scrolled to its end, the card's last line sits above the buttons.
        XCTAssertLessThanOrEqual(image.frame.maxY, app.buttons["rating-good"].frame.minY + 1)
    }

    func testAShortCardDoesNotScrollUnderTheAnswerBar() throws {
        app.launch()
        openDeck("Languages")
        // A card without the image fits above the answer bar.
        var answer = spanishAnswer
        for _ in 0..<4 {
            showAnswer()
            answer = spanishAnswer
            XCTAssertTrue(answer.waitForExistence(timeout: 30), "The answer is drawn")
            if !webText(containing: "the sun").exists { break }
            rate("easy")
            _ = answer.waitForNonExistence(timeout: 30)
        }
        XCTAssertFalse(webText(containing: "the sun").exists)
        let top = answer.frame.minY
        app.webViews.firstMatch.swipeUp(velocity: .slow)
        // Allow a rubber-band settle before measuring.
        sleep(1)
        XCTAssertEqual(answer.frame.minY, top, accuracy: 1, "A card that fits does not scroll")
    }

    // MARK: Helpers

    /// The back of any of the fixture's Spanish cards.
    private var spanishAnswer: XCUIElement {
        let backs = ["the sun", "goodbye", "thank you", "please"]
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: backs.map {
            NSPredicate(format: "label CONTAINS %@", $0)
        })
        return app.webViews.staticTexts.matching(predicate).firstMatch
    }

    private func webText(containing text: String) -> XCUIElement {
        let predicate = text.isEmpty
            ? NSPredicate(format: "label != ''")
            : NSPredicate(format: "label CONTAINS %@", text)
        return app.webViews.staticTexts.matching(predicate).firstMatch
    }

    private func showAnswer() {
        let button = app.buttons["show-answer"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(app.buttons["rating-easy"].waitForExistence(timeout: 20))
    }

    private func rate(_ rating: String) {
        app.buttons["rating-\(rating)"].tap()
    }

    private func closeStudy() {
        app.buttons["Close"].firstMatch.tap()
    }

    private func openDeck(_ name: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        // At accessibility text sizes the Today card fills the first screen,
        // so the deck rows sit below it.
        XCTAssertTrue(app.buttons["study-all"].waitForExistence(timeout: 60), "The deck list is shown")
        for _ in 0..<6 where !(row.exists && row.isHittable) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The deck list shows \(name)")
        row.tap()
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
