import AnkiProto
import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

/// How a deck package import treats cards that are already in the collection
/// (the same note, matched by its GUID, and the same card template). The
/// transfer guide's wording depends on this.
///
/// Confirmed against Anki 26.09.4's core (rslib import_export/package/apkg/
/// import/cards.rs, `import_cards`: an existing card is skipped, "TODO: could
/// update existing card"): whatever the merge choices, a card already in the
/// collection keeps its own scheduling and review history; the package's
/// scheduling and review history are brought only for cards new to the
/// collection. The update choice only decides whether the note's content is
/// replaced.
@MainActor
@Suite("Importing a deck package over cards already in the collection", .timeLimit(.minutes(2)))
struct ExistingCardsTests {
    @Test(
        "Cards already in the collection keep their scheduling and review history under every merge choice",
        arguments: [true, false], [MergeOptions.UpdateCondition.ifNewer, .always, .never]
    )
    func existingCardsKeepTheirScheduling(learningProgress: Bool, updateNotes: MergeOptions.UpdateCondition) async throws {
        try await withTemporaryCollection { store in
            // The learner's collection holds the Spanish deck already, has
            // studied one more of its cards since, and edited one note.
            try await store.importFixture(.collection)
            let spanish = try await store.deckID(named: "Languages::Spanish")
            try await store.answerNextCard(inDeck: spanish, rating: .again)
            try await store.editBackField(ofNoteWithFront: "el sol", to: "the sun, edited here")
            let before = try await store.scheduling(ofCardsIn: "Languages::Spanish")
            let reviewsBefore = try await store.reviewCount()

            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(FixturePackage.basicDeck.url)
            model.mergeOptions.includeLearningProgress = learningProgress
            model.mergeOptions.updateNotes = updateNotes
            await model.startImport()

            guard case .finished(.merged(let result)) = model.step else {
                Issue.record("expected a merge summary, got \(model.step)")
                return
            }
            #expect(try await store.scheduling(ofCardsIn: "Languages::Spanish") == before)
            #expect(try await store.reviewCount() == reviewsBefore)
            #expect(result.added.isEmpty)
            #expect(try await store.contents().notes == FixturePackage.collection.contents.notes)

            // Only the note's content follows the update choice. The edit made
            // here is newer than the package's copy.
            let back = try await store.backField(ofNoteWithFront: "el sol")
            switch updateNotes {
            case .ifNewer, .never:
                #expect(result.updated.isEmpty)
                #expect(result.unchanged.count == 4)
                #expect(back == "the sun, edited here")
            case .always:
                #expect(result.updated == ["el sol"])
                #expect(result.unchanged.count == 3)
                #expect(back.hasPrefix("the sun<br>"))
            }
        }
    }

    @Test("Importing a deck package again with learning progress does not bring that progress to cards already there")
    func progressIsNotBroughtToExistingCards() async throws {
        try await withTemporaryCollection { store in
            let backups = try TemporaryFolder()
            let model = PackageImportModel(store: store, backupFolder: backups.url)
            await model.open(FixturePackage.basicDeck.url)
            model.mergeOptions.includeLearningProgress = false
            await model.startImport()
            #expect(try await store.contents().studiedCards == 0)

            await model.open(FixturePackage.basicDeck.url)
            model.mergeOptions.includeLearningProgress = true
            model.mergeOptions.updateNotes = .always
            await model.startImport()

            // The package has two studied cards with two reviews; the
            // collection's copies stay new.
            let contents = try await store.contents()
            #expect(contents.cards == 4)
            #expect(contents.studiedCards == 0)
            #expect(contents.reviews == 0)
        }
    }
}

/// A card's scheduling, as far as the learner can see it.
struct CardScheduling: Equatable {
    let id: Int64
    let type: UInt32
    let queue: Int32
    let due: Int32
    let interval: UInt32
    let reviews: UInt32
    let lapses: UInt32
}

extension CollectionStore {
    func scheduling(ofCardsIn deck: String) async throws -> [CardScheduling] {
        var cards: [CardScheduling] = []
        for id in try await cardIDs(matching: "\"deck:\(deck)\"").sorted() {
            let card = try await core.getCard(.with { $0.cid = id })
            cards.append(CardScheduling(
                id: id, type: card.ctype, queue: card.queue, due: card.due,
                interval: card.interval, reviews: card.reps, lapses: card.lapses
            ))
        }
        return cards
    }

    func note(withFront front: String) async throws -> Anki_Notes_Note {
        let ids = try await noteIDs(matching: "\"front:\(front)\"")
        let id = try #require(ids.first)
        return try await core.getNote(.with { $0.nid = id })
    }

    func backField(ofNoteWithFront front: String) async throws -> String {
        try await note(withFront: front).fields[1]
    }

    func editBackField(ofNoteWithFront front: String, to back: String) async throws {
        var note = try await note(withFront: front)
        note.fields[1] = back
        try await modify(.updateNotes(.with { $0.notes = [note] }))
    }
}
