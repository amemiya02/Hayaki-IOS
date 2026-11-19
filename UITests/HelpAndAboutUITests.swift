import XCTest

@MainActor
final class HelpAndAboutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        let package = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "collection", withExtension: "colpkg")
        )
        app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = package.path
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launch()

        let helpTab = app.tabBars.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "More", "Settings")).firstMatch
        XCTAssertTrue(helpTab.waitForExistence(timeout: 30))
        helpTab.tap()
    }

    func testAboutIdentifiesThisBuildAndOpensItsChangelog() {
        openMoreLink("About")
        XCTAssertTrue(app.staticTexts["0.1.0"].exists)
        XCTAssertTrue(app.staticTexts["26.09.4"].exists)
        XCTAssertTrue(app.staticTexts["6.6.2"].exists)
        XCTAssertTrue(app.staticTexts["Build Date"].exists)
        let copy = app.buttons["Copy Debug Information"]
        reveal(copy)
        copy.tap()
        let copied = app.alerts["Debug Information Copied"]
        XCTAssertTrue(copied.waitForExistence(timeout: 5))
        copied.buttons["OK"].tap()
        reveal(element("github.com/amemiya02/Hayaki-IOS"))
        reveal(element("AGPL-3.0-or-later"))
        reveal(element("AnkiDroid"))
        XCTAssertTrue(element("Anki").exists)
        screenshot("About")

        let changelog = app.buttons["Changelog"]
        for _ in 0..<3 where !changelog.isHittable { app.swipeDown() }
        changelog.tap()
        XCTAssertTrue(app.navigationBars["Changelog"].exists)
        XCTAssertTrue(app.staticTexts["0.1.0"].exists)
        screenshot("Changelog")
    }

    func testGuideOpensTheRealExportChoices() {
        openMoreLink("Transfer Guide")
        XCTAssertTrue(app.staticTexts["A deck package (.apkg) merges into the receiving collection."].exists)
        XCTAssertTrue(app.staticTexts["A collection package (.colpkg) replaces the receiving collection."].exists)
        screenshot("Transfer Guide")

        let export = app.buttons["TransferGuideExport"]
        reveal(export)
        export.tap()
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Collection Package"].exists || app.staticTexts["Collection Package"].exists)
        XCTAssertTrue(app.buttons["Deck Package"].exists || app.staticTexts["Deck Package"].exists)
    }

    func testGuideOpensTheSystemFilePicker() {
        openMoreLink("Transfer Guide")
        let importPackage = app.buttons["TransferGuideImport"]
        reveal(importPackage)
        importPackage.tap()

        app.cancelFilesPicker()
        XCTAssertTrue(app.navigationBars["Transfer Guide"].waitForExistence(timeout: 10))
    }

    func testGuideExplainsBothSyncDestinationsAndOpensSyncSettings() {
        openMoreLink("Transfer Guide")
        let sync = app.buttons["sync-settings"]
        reveal(sync)
        XCTAssertTrue(element("In Sync Destination, choose AnkiWeb and sign in with your AnkiWeb email address and password.").exists)
        XCTAssertTrue(element("For your own server, choose Self-Hosted. Enter its address and sign in with the user name and password for that server.").exists)
        screenshot("Sync choices in Transfer Guide")
        sync.tap()
        XCTAssertTrue(app.navigationBars["Sync"].waitForExistence(timeout: 10))
    }

    func testHelpPointsToManualsAndHayakiIssues() {
        openMoreLink("Help")
        XCTAssertTrue(element("Desktop Anki Manual").exists)
        XCTAssertTrue(element("AnkiDroid Manual").exists)
        XCTAssertTrue(element("Anki Forums").exists)
        XCTAssertTrue(element("Report a Hayaki Issue").exists)
        screenshot("Help")
    }

    private func openMoreLink(_ label: String) {
        let link = app.buttons[label]
        reveal(link)
        link.tap()
        XCTAssertTrue(app.navigationBars[label].waitForExistence(timeout: 15))
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
