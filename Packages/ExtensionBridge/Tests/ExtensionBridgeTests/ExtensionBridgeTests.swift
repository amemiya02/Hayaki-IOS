import ExtensionBridge
import Foundation
import Testing

@Test("An extension saves a text draft for the profile it opened, even if the active profile changes")
func savingSharedText() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bridge = ExtensionBridge(directory: directory)
    let original = UUID()
    let other = UUID()
    let draft = SharedNote(
        profileID: original, deckID: 47, noteTypeID: 102,
        fieldNames: ["Front", "Back"], values: ["one < two\n二", "answer"], mode: .quickAdd
    )

    try bridge.enqueue(draft)

    #expect(try bridge.pendingNotes(for: other).isEmpty)
    #expect(try bridge.pendingNotes(for: original) == [draft])
    try bridge.remove(draft)
    #expect(try bridge.pendingNotes(for: original).isEmpty)
}

@Test("An empty deck links to options and a deck with work links to the reviewer in its profile")
func widgetLinks() throws {
    let profile = UUID()
    let ready = ExtensionDeck(id: 146, name: "Spanish", isFiltered: false, new: 1, learning: 0, review: 0)
    let empty = ExtensionDeck(id: 159, name: "French", isFiltered: false, new: 0, learning: 0, review: 0)
    #expect(ready.destination == .study)
    #expect(empty.destination == .options)
    let readyLink = DeckLink.deck(profileID: profile, deckID: ready.id, action: .study)
    let emptyLink = DeckLink.deck(profileID: profile, deckID: empty.id, action: .options)
    #expect(DeckLink(url: readyLink.url) == readyLink)
    #expect(DeckLink(url: emptyLink.url) == emptyLink)
    #expect(DeckLink(url: try #require(URL(string: "hayaki://decks/\(profile)/146"))) == nil)
}
