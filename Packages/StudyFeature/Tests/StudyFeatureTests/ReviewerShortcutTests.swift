import StudyFeature
import SwiftUI
import Testing

@Suite("Reviewer keyboard shortcuts")
struct ReviewerShortcutTests {
    @Test("The question side lists Show Answer once, on Space")
    func questionSide() {
        let shortcuts = ReviewerPreferences().keyboardShortcuts(on: .question)
        let showAnswer = shortcuts.filter { $0.command == .showAnswer }
        #expect(showAnswer.map(\.key) == [ReviewerKey("space")])
        #expect(!shortcuts.contains { $0.command == .rateGood })
    }

    @Test("The answer side lists the four ratings on 1 to 4")
    func answerRatings() {
        let shortcuts = ReviewerPreferences().keyboardShortcuts(on: .answer)
        let ratings = shortcuts.filter { [.rateAgain, .rateHard, .rateGood, .rateEasy].contains($0.command) }
        #expect(ratings.map(\.command) == [.rateAgain, .rateHard, .rateGood, .rateEasy])
        #expect(ratings.map(\.key) == ["1", "2", "3", "4"].map { ReviewerKey($0) })
    }

    @Test("A command bound to several keys shows the simplest, preferring Command over Control")
    func preferredKey() {
        let shortcuts = ReviewerPreferences().keyboardShortcuts(on: .answer)
        #expect(shortcuts.first { $0.command == .undo }?.key == ReviewerKey("z", modifiers: [.command]))
        #expect(shortcuts.first { $0.command == .mark }?.key == ReviewerKey("*"))
        #expect(shortcuts.first { $0.command == .toggleRedFlag }?.key == ReviewerKey("1", modifiers: [.control]))
    }

    @Test("Each key appears at most once, and custom bindings are listed")
    func customBindings() {
        var preferences = ReviewerPreferences()
        preferences.bind(.cardInfo, to: .key("arrowright"), on: .answer)
        preferences.bind(.deckOptions, to: .controller("buttonA"), on: .answer)
        let shortcuts = preferences.keyboardShortcuts(on: .answer)
        #expect(shortcuts.contains { $0.command == .cardInfo && $0.key == ReviewerKey("arrowright") })
        #expect(!shortcuts.contains { $0.command == .deckOptions })
        #expect(Set(shortcuts.map(\.key)).count == shortcuts.count)
    }

    @Test("Reviewer keys map to the system key equivalents")
    func keyEquivalents() {
        #expect(ReviewerKey("space").keyEquivalent == .space)
        #expect(ReviewerKey("return").keyEquivalent == .return)
        #expect(ReviewerKey("arrowleft").keyEquivalent == .leftArrow)
        #expect(ReviewerKey("backspace").keyEquivalent == .delete)
        #expect(ReviewerKey("e").keyEquivalent == KeyEquivalent("e"))
        #expect(ReviewerKey("f13").keyEquivalent == nil)
        #expect(ReviewerKey("z", modifiers: [.shift, .command]).eventModifiers == [.shift, .command])
    }
}
