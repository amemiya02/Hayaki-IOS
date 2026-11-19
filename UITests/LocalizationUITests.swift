import XCTest

@MainActor
final class LocalizationUITests: XCTestCase {
    private struct Interface {
        let language: String
        let locale: String
        let showAnswer: String
        let good: String
        let minuteSuffix: String
        let studyActions: String
        let editNote: String
        let noteType: String
    }

    private let english = Interface(
        language: "en", locale: "en_US", showAnswer: "Show Answer", good: "Good", minuteSuffix: "m",
        studyActions: "Study Actions", editNote: "Edit Note", noteType: "Note Type"
    )

    func testEnglishAfterRelaunch() throws {
        try verify(english)
    }

    func testJapaneseAfterRelaunch() throws {
        try verify(.init(
            language: "ja", locale: "ja_JP", showAnswer: "解答を表示", good: "正解", minuteSuffix: "分",
            studyActions: "学習操作", editNote: "ノートを編集", noteType: "ノートタイプ"
        ))
    }

    func testSimplifiedChineseAfterRelaunch() throws {
        try verify(.init(
            language: "zh-Hans", locale: "zh_CN", showAnswer: "显示答案", good: "良好", minuteSuffix: "分",
            studyActions: "学习操作", editNote: "编辑笔记", noteType: "笔记类型"
        ))
    }

    func testUnsupportedArabicUsesEnglishAndLongDeckCountsRemainReadableInRTL() throws {
        let app = try app(byLaunching: .init(
            language: "ar", locale: "ar_SA", showAnswer: english.showAnswer, good: english.good,
            minuteSuffix: english.minuteSuffix,
            studyActions: english.studyActions, editNote: english.editNote, noteType: english.noteType
        ), rightToLeft: true)

        let row = deck(named: "Geography", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        let countsStart = try XCTUnwrap(row.label.range(of: #"[0-9٠-٩]+ new"#, options: .regularExpression))
        let counts = String(row.label[countsStart.lowerBound...])
        XCTAssertTrue(counts.contains("due"), counts)
        row.press(forDuration: 1.2)
        app.buttons["Rename"].tap()
        let rename = app.alerts["Rename Deck"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        let suffix = String(repeating: " with a very long name", count: 6)
        rename.textFields.firstMatch.tap()
        rename.textFields.firstMatch.typeText(suffix)
        rename.buttons["Rename"].tap()
        let longRow = deck(named: "Geography" + suffix, in: app)
        XCTAssertTrue(longRow.waitForExistence(timeout: 15))
        XCTAssertTrue(longRow.label.contains(counts), longRow.label)
        XCTAssertTrue(longRow.label.contains("due"), longRow.label)
        attach("RTL deck row", in: app)

        try verifyStudyAndEditor(english, in: app, row: longRow, rightToLeft: true)
    }

    private func verify(_ language: Interface) throws {
        let app = try app(byLaunching: language)
        let row = deck(named: "Geography", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        try verifyStudyAndEditor(language, in: app, row: row)
    }

    private func app(byLaunching language: Interface, rightToLeft: Bool = false) throws -> XCUIApplication {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "collection", withExtension: "colpkg"))
        let app = XCUIApplication()
        app.launchEnvironment["HAYAKI_UI_TEST_COLLECTION_PACKAGE"] = fixture.path
        app.launchArguments += ["-AppleLanguages", "(\(language.language))", "-AppleLocale", language.locale]
        if rightToLeft {
            app.launchArguments += ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
        }
        app.launch()
        return app
    }

    private func verifyStudyAndEditor(
        _ language: Interface, in app: XCUIApplication, row: XCUIElement, rightToLeft: Bool = false
    ) throws {
        row.tap()
        let showAnswer = app.buttons["show-answer"]
        XCTAssertTrue(showAnswer.waitForExistence(timeout: 30))
        XCTAssertEqual(showAnswer.label, language.showAnswer)
        showAnswer.tap()

        let again = app.buttons["rating-again"]
        let good = app.buttons["rating-good"]
        XCTAssertTrue(good.waitForExistence(timeout: 15))
        XCTAssertEqual(good.label, language.good)
        let interval = try XCTUnwrap(again.value as? String)
        XCTAssertTrue(interval.hasSuffix(language.minuteSuffix), interval)
        XCTAssertEqual(again.frame.midX > good.frame.midX, rightToLeft)
        attach("Reviewer", in: app)

        app.buttons[language.studyActions].tap()
        let edit = app.buttons[language.editNote]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(app.navigationBars[language.editNote].waitForExistence(timeout: 15))
        let noteType = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR label BEGINSWITH %@", language.noteType, language.noteType + ","
        )).firstMatch
        XCTAssertTrue(noteType.exists)
        XCTAssertTrue(app.descendants(matching: .any)["note-field-0"].firstMatch.exists)
        attach("Note editor", in: app)
    }

    private func deck(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func attach(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
