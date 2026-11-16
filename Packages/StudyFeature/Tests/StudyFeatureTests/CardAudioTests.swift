import CollectionStore
import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("Audio on cards", .timeLimit(.minutes(1)))
struct CardAudioTests {
    @Test("The fixture card with audio on its back plays it when the answer is shown, from the media folder")
    func fixtureAudioOnAnswer() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.basicDeck)
            let session = try await store.studySession(ofCardsMatching: "adiós")

            let question = try #require(session.state.question)
            #expect(question.question.audio.isEmpty)
            #expect(session.soundsToAutoplay().isEmpty)

            session.showAnswer()

            let adios = store.location.mediaFolder.appendingPathComponent("adios.m4a")
            #expect(session.soundsToAutoplay() == [.file(adios)])
            let answer = try #require(session.state.answer).answer
            // The core's [sound:adios.m4a] became a replay button for it.
            #expect(!answer.html.contains("[sound:"))
            #expect(answer.html.contains(#"data-play="a:0""#))
            #expect(session.sound(forPlayButton: "a:0") == .file(adios))
        }
    }

    @Test("Several sounds and text to speech play in the order they appear; the answer side does not replay the question's")
    func orderOfSounds() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Listening")
            try await store.addNotes(ofType: "Basic", fields: [[
                "one [sound:one.mp3] two [sound:two.mp3] [anki:tts lang=ja_JP speed=1.5]三[/anki:tts]",
                "four [sound:four.mp3]",
            ]], toDeck: deck)
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            let media = store.location.mediaFolder

            let question = try #require(session.state.question).question
            #expect(session.soundsToAutoplay() == [
                .file(media.appendingPathComponent("one.mp3")),
                .file(media.appendingPathComponent("two.mp3")),
                .speech(.init(text: "三", language: "ja_JP", voices: [], speed: 1.5)),
            ])
            #expect(session.soundsToReplay() == session.soundsToAutoplay())
            // Each sound has its replay button where it was, in order.
            let buttons = question.html.matches(of: /data-play="([qa]:\d+)"/).map { String($0.output.1) }
            #expect(buttons == ["q:0", "q:1", "q:2"])
            #expect(question.html.firstRange(of: "one")!.lowerBound < question.html.firstRange(of: #"data-play="q:0""#)!.lowerBound)

            session.showAnswer()

            let four = CardSound.file(media.appendingPathComponent("four.mp3"))
            // {{FrontSide}} shows the question with its buttons, which play
            // the question's sounds, but only the answer's own sound plays
            // by itself.
            let answer = try #require(session.state.answer).answer
            let answerButtons = answer.html.matches(of: /data-play="([qa]:\d+)"/).map { String($0.output.1) }
            #expect(answerButtons == ["q:0", "q:1", "q:2", "a:0"])
            #expect(session.soundsToAutoplay() == [four])
            #expect(session.sound(forPlayButton: "q:1") == .file(media.appendingPathComponent("two.mp3")))
            #expect(session.sound(forPlayButton: "a:0") == four)
            #expect(session.sound(forPlayButton: "a:1") == nil)
            // Replaying the answer side plays the question's sounds first, as
            // Anki does by default.
            #expect(session.soundsToReplay().count == 4)
            #expect(session.soundsToReplay().last == four)
        }
    }

    @Test("The deck's options can stop audio playing by itself, and skip the question when replaying the answer")
    func deckAudioOptions() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Quiet")
            try await store.addNotes(ofType: "Basic", fields: [["[sound:q.mp3]", "[sound:a.mp3]"]], toDeck: deck)
            try await store.setDeckOptions(of: deck, ["autoplay": false, "replayq": false])
            let session = StudySessionModel(store: store, deckID: deck)
            await session.start()
            let media = store.location.mediaFolder

            #expect(session.soundsToAutoplay().isEmpty)
            #expect(session.soundsToReplay() == [.file(media.appendingPathComponent("q.mp3"))])
            session.showAnswer()
            #expect(session.soundsToAutoplay().isEmpty)
            #expect(session.soundsToReplay() == [.file(media.appendingPathComponent("a.mp3"))])
        }
    }
}

private extension CollectionStore {
    /// Changes options of the deck's preset, by their names in Anki's
    /// legacy deck options JSON.
    func setDeckOptions(of deckID: Int64, _ changes: [String: Any]) async throws {
        let deck = try await core.getDeck(.with { $0.did = deckID })
        let legacy = try await core.getDeckConfigLegacy(.with { $0.dcid = deck.normal.configID })
        var json = try #require(try JSONSerialization.jsonObject(with: legacy.json) as? [String: Any])
        json.merge(changes) { _, new in new }
        _ = try await core.addOrUpdateDeckConfigLegacy(.with { $0.json = try! JSONSerialization.data(withJSONObject: json) })
    }
}
