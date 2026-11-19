import XCTest

@MainActor
final class ProfilesUITests: XCTestCase {
    func testAddSwitchAndReopenProfile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_EMPTY_COLLECTION"] = UUID().uuidString
        app.launch()

        startEmpty(app)
        openProfiles(app)

        let addProfile = app.buttons["add-profile"]
        XCTAssertTrue(addProfile.waitForExistence(timeout: 10))
        addProfile.tap()
        let nameField = app.textFields["profile-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("French")
        app.buttons["Save"].tap()

        let french = app.buttons["French"]
        XCTAssertTrue(french.waitForExistence(timeout: 10))
        french.tap()
        let confirm = app.alerts["Switch Profile?"].buttons["Switch Profile"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        startEmpty(app)

        app.terminate()
        app.launch()
        openProfiles(app)
        XCTAssertTrue(french.waitForExistence(timeout: 10))
        XCTAssertTrue(french.isSelected)
    }

    private func startEmpty(_ app: XCUIApplication) {
        let button = app.buttons["Start Empty"]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.tap()
    }

    private func openProfiles(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["More"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        let settings = app.descendants(matching: .any)["profiles-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Profiles"].waitForExistence(timeout: 10))
    }
}
