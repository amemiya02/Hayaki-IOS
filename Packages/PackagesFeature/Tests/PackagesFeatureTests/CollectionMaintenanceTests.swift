import CollectionStore
import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Collection maintenance")
struct CollectionMaintenanceTests {
    @Test("Media check publishes its repairs to note references")
    func checkPublishesRepairedReferences() async throws {
        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Photos")
            let original = #"<img src="photo?.png">"#
            let repaired = #"<img src="photo.png">"#
            try await store.addNotes(ofType: "Basic", fields: [["Photo", original]], toDeck: deck)
            try Data([1]).write(to: store.location.mediaFolder.appendingPathComponent("photo.png"))
            let changes = store.changes()
            var noteChanged = false
            let listener = Task {
                for await change in changes where change.contains(.noteText) {
                    noteChanged = true
                    return
                }
            }
            defer { listener.cancel() }

            let maintenance = CollectionMaintenanceModel(store: store)
            await maintenance.checkMedia()

            #expect(maintenance.error == nil)
            #expect(try await store.snapshot().notes.first?.fields == ["Photo", repaired])
            try await eventually(timeout: .seconds(1), "media check to publish the changed note reference") { noteChanged }
        }
    }

    @Test("Media check keeps referenced files and can recover an unused file from trash")
    func recoverUnusedMedia() async throws {
        try await withTemporaryCollection { store in
            try await store.importFixture(.collection)
            let orphan = store.location.mediaFolder.appendingPathComponent("unused.txt")
            try Data("backed by test fixture".utf8).write(to: orphan)
            let maintenance = CollectionMaintenanceModel(store: store)
            await maintenance.checkMedia()
            let result = try #require(maintenance.media)
            #expect(result.unused == ["unused.txt"])
            #expect(result.missing.isEmpty)

            await maintenance.trashUnusedMedia()

            let namesAfterTrash = try store.mediaFileNames()
            #expect(!namesAfterTrash.contains("unused.txt"))
            #expect(namesAfterTrash.contains("sol.png"))
            #expect(maintenance.media?.hasTrash == true)

            await maintenance.restoreMediaTrash()

            #expect(try String(contentsOf: orphan, encoding: .utf8) == "backed by test fixture")
            #expect(maintenance.media?.unused == ["unused.txt"])
        }
    }
}
