@testable import AppShell
import CollectionStore
import CollectionTesting
import ExtensionBridge
import Foundation
import Testing

@MainActor
@Test("A queued deck list or study destination opens another profile from a cold start", arguments: [1, nil] as [Int64?])
func coldDeckLink(deckID: Int64?) async throws {
    let folder = try TemporaryFolder()
    let location = CollectionLocation(folder: folder.url.appending(path: "Collection"))
    let backupFolder = folder.url.appending(path: "Backups")
    let suite = "HayakiExtensionTests.\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let app = AppModel(location: { location }, backupFolder: { backupFolder }, language: "en", preferences: preferences)
    let profile = try app.addProfile(named: "French")
    let link = deckID.map { DeckLink.deck(profileID: profile.id, deckID: $0, action: .study) }
        ?? .decks(profileID: profile.id)
    app.waitingDeckLink = .init(link: link)

    await app.routeWaitingDeckLink()
    #expect(app.waitingDeckLink != nil)
    await app.open()
    await app.routeWaitingDeckLink()

    #expect(app.activeProfile == profile)
    #expect(app.waitingDeckLink == nil)
    #expect(app.decksRequested != nil)
    #expect(app.deckPresentation?.deckID == deckID)
    if deckID != nil { #expect(app.deckPresentation?.showsOptions == false) }
    #expect(!app.showsWelcome)
    try await app.store?.close()
}

@MainActor
@Test("Shared plain text produces cards with escaped fields in the selected deck of the intended profile")
func sharedTextAddsNote() async throws {
    try await withTemporaryCollection { store in
        let folder = try TemporaryFolder()
        let bridge = ExtensionBridge(directory: folder.url)
        let service = AppExtensions(bridge: bridge)
        let profile = CollectionProfile(id: UUID(), name: "Italian")
        let deck = try await store.addDeck(named: "Phrases")
        await service.publish(store: store, profile: profile, isCurrent: { true })
        let snapshot = try #require(bridge.snapshot())
        let noteType = try #require(snapshot.noteTypes.first { $0.name == "Basic (type in the answer)" })
        let draft = SharedNote(
            profileID: profile.id, deckID: deck, noteTypeID: noteType.id, fieldNames: noteType.fields,
            values: ["one < two\n二", "answer"], mode: .quickAdd
        )
        try bridge.enqueue(draft)

        await service.consumeNotes(profileID: UUID(), store: store, sceneID: UUID())
        #expect(try await store.cardCount(matching: "deck:Phrases") == 0)
        await service.consumeNotes(profileID: profile.id, store: store, sceneID: UUID())
        #expect(service.editorDraft == nil)
        #expect(try bridge.pendingNotes(for: profile.id).isEmpty)
        let cid = try #require(try await store.core.searchCards(.with { $0.search = "deck:Phrases" }).ids.first)
        let card = try await store.core.getCard(.with { $0.cid = cid })
        let note = try await store.core.getNote(.with { $0.nid = card.noteID })
        #expect(card.deckID == deck)
        #expect(note.notetypeID == noteType.id)
        #expect(note.fields == ["one &lt; two<br>二", "answer"])
        await service.publish(store: store, profile: profile, isCurrent: { true })
        #expect(bridge.snapshot()?.decks.first(where: { $0.id == deck })?.new == 1)

        try await store.answerNextCard(inDeck: deck, rating: .easy)
        await service.publish(store: store, profile: profile, isCurrent: { true })
        #expect(bridge.snapshot()?.decks.first(where: { $0.id == deck })?.new == 0)
    }
}


@MainActor
@Test("A shared full-editor draft can be cancelled without adding a card")
func cancellingSharedDraft() async throws {
    try await withTemporaryCollection { store in
        let folder = try TemporaryFolder()
        let bridge = ExtensionBridge(directory: folder.url)
        let service = AppExtensions(bridge: bridge)
        let profile = CollectionProfile(id: UUID(), name: "Japanese")
        let deck = try await store.addDeck(named: "Phrases")
        await service.publish(store: store, profile: profile, isCurrent: { true })
        let snapshot = try #require(bridge.snapshot())
        let type = try #require(snapshot.noteTypes.first { $0.name == "Basic" })
        let draft = SharedNote(
            profileID: profile.id, deckID: deck, noteTypeID: type.id, fieldNames: type.fields,
            values: ["apples", "りんご"], mode: .fullEditor
        )
        try bridge.enqueue(draft)
        let scene = UUID()
        await service.consumeNotes(profileID: profile.id, store: store, sceneID: scene)

        let editorDraft = try #require(service.editorDraft)
        #expect(editorDraft.sceneID == scene)
        #expect(editorDraft.editor.fields.map(\.text) == ["apples", "りんご"])
        #expect(editorDraft.editor.deckID == deck)
        service.dismissDraft(editorDraft)
        #expect(try bridge.pendingNotes(for: profile.id).isEmpty)
        #expect(try await store.cardCount(matching: "deck:Phrases") == 0)
    }
}
