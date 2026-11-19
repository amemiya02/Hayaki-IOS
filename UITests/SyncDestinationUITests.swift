import XCTest

@MainActor
final class SyncDestinationUITests: XCTestCase {
    func testAnkiWebDefaultAndSelfHostedAddressField() throws {
        continueAfterFailure = false
        let package = try XCTUnwrap(
            Bundle(for: SyncDestinationUITests.self).url(forResource: "collection", withExtension: "colpkg")
        )
        let app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = package.path
        app.launch()

        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 60))
        more.tap()
        let sync = app.buttons["sync-settings"]
        XCTAssertTrue(sync.waitForExistence(timeout: 10))
        sync.tap()

        let destination = app.descendants(matching: .any).matching(identifier: "sync-destination").firstMatch
        if !destination.waitForExistence(timeout: 10), app.buttons["Sign Out"].exists {
            throw XCTSkip("This simulator already has a sync account.")
        }
        XCTAssertTrue(destination.exists)
        let destinationText = [destination.label, destination.value as? String ?? ""].joined(separator: " ")
        XCTAssertTrue(destinationText.contains("AnkiWeb") || app.staticTexts["AnkiWeb"].exists)

        let address = app.textFields["server-address"]
        XCTAssertFalse(address.exists)
        destination.tap()
        app.buttons["Self-Hosted"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5))

        destination.tap()
        app.buttons["AnkiWeb"].tap()
        XCTAssertTrue(address.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.textFields["user-name"].exists)
        XCTAssertTrue(app.secureTextFields["password"].exists)
    }
}
