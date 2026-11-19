import Foundation
import StudyFeature
import Testing

@Suite("Card preview controls")
struct PreviewControlsTests {
    @Test("Preview uses Android keyboard defaults and saves independent replacements")
    func previewBindings() throws {
        let suite = "PreviewControlsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var controls = PreviewControls.load(from: defaults)

        #expect(controls.command(for: .key("arrowleft")) == .previous)
        #expect(controls.command(for: .key("arrowright")) == .next)
        #expect(controls.command(for: .key("*", modifiers: [.shift])) == .mark)
        #expect(controls.command(for: .key("e")) == .edit)
        #expect(controls.command(for: .key("b")) == .answerOnly)
        #expect(controls.command(for: .key("r")) == .replayMedia)
        #expect(controls.command(for: .key("7", modifiers: [.control])) == .flagPurple)
        #expect(controls.command(for: .key("4")) == nil)

        controls.bind(nil, to: .key("r"))
        controls.bind(.next, to: .controller("buttonA"))
        controls.bind(.previous, to: .gesture(.swipeRight))
        controls.bind(.replayMedia, to: .gesture(.doubleTap))
        controls.bind(.answerOnly, to: .controller("buttonA"))
        controls.save(to: defaults)
        let reopened = PreviewControls.load(from: defaults)
        #expect(reopened.command(for: .key("r")) == nil)
        #expect(reopened.command(for: .controller("buttonA")) == .answerOnly)
        #expect(reopened.command(for: .gesture(.swipeRight)) == .previous)
        #expect(reopened.command(for: .gesture(.doubleTap)) == .replayMedia)
        #expect(ReviewerPreferences.load(from: defaults).command(for: .key("r"), on: .question) == .replayMedia)
    }
}
