import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("Reviewer controls")
struct ReviewerControlsTests {
    @Test("Saved physical bindings reveal and rate on their configured sides")
    func savedPhysicalBindings() async throws {
        let suite = "ReviewerControlsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let trigger = ReviewerInput.controller("buttonA")
        var controls = ReviewerPreferences.load(from: defaults)
        controls.bind(.showAnswer, to: trigger, on: .question)
        controls.bind(.rateEasy, to: trigger, on: .answer)
        controls.save(to: defaults)

        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let card = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            let reopened = ReviewerPreferences.load(from: defaults)
            await session.start()

            #expect(reopened.command(for: .key("4"), on: .question) == nil)
            #expect(await session.perform(.rateEasy) == false)
            #expect(session.state.question?.id == card)
            let reveal = try #require(reopened.command(for: trigger, on: .question))
            #expect(await session.perform(reveal))
            #expect(session.state.answer?.id == card)

            let rate = try #require(reopened.command(for: trigger, on: .answer))
            #expect(await session.perform(rate))
            #expect(session.state.finished != nil)
            #expect(try await store.reviewCount() == 1)
        }
    }
}
