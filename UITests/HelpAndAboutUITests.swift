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
        app.buttons["About"].tap()
        XCTAssertTrue(app.staticTexts["0.1.0"].exists)
        XCTAssertTrue(app.staticTexts["26.09.4"].exists)
        XCTAssertTrue(element("github.com/amemiya02/Hayaki-IOS").exists)
        XCTAssertTrue(element("AGPL-3.0-or-later").exists)
        reveal(element("Amgi"))
        XCTAssertTrue(element("Anki").exists)
        XCTAssertTrue(element("AnkiDroid").exists)
        screenshot("About")

        let changelog = app.buttons["Changelog"]
        for _ in 0..<3 where !changelog.isHittable { app.swipeDown() }
        changelog.tap()
        XCTAssertTrue(app.navigationBars["Changelog"].exists)
        XCTAssertTrue(app.staticTexts["0.1.0"].exists)
        screenshot("Changelog")
    }

    func testGuideOpensTheRealExportChoices() {
        app.buttons["Transfer Guide"].tap()
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
        app.buttons["Transfer Guide"].tap()
        let importPackage = app.buttons["TransferGuideImport"]
        reveal(importPackage)
        importPackage.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Transfer Guide"].waitForExistence(timeout: 10))
    }

    func testGuideExplainsBothSyncDestinationsAndOpensSyncSettings() {
        app.buttons["Transfer Guide"].tap()
        let sync = app.buttons["sync-settings"]
        reveal(sync)
        XCTAssertTrue(element("In Sync Destination, choose AnkiWeb and sign in with your AnkiWeb email address and password.").exists)
        XCTAssertTrue(element("For your own server, choose Self-Hosted. Enter its address and sign in with the user name and password for that server.").exists)
        screenshot("Sync choices in Transfer Guide")
        sync.tap()
        XCTAssertTrue(app.navigationBars["Sync"].waitForExistence(timeout: 10))
    }

    func testHelpPointsToManualsAndHayakiIssues() {
        app.buttons["Help"].tap()
        XCTAssertTrue(element("Desktop Anki Manual").exists)
        XCTAssertTrue(element("AnkiDroid Manual").exists)
        XCTAssertTrue(element("Anki Forums").exists)
        XCTAssertTrue(element("Report a Hayaki Issue").exists)
        screenshot("Help")
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
