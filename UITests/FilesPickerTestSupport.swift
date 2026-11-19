import XCTest

@MainActor
extension XCUIApplication {
    func cancelFilesPicker(file: StaticString = #filePath, line: UInt = #line) {
        let dismiss = buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Cancel", "Close")
        ).firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 30), "Files shows its dismissal control", file: file, line: line)
        XCTAssertTrue(dismiss.isHittable, file: file, line: line)
        dismiss.tap()
    }
}
