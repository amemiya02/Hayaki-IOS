import AnkiCore
import AnkiProto
import Foundation

extension CoreClient {
    /// Adds `count` notes of the stock Basic note type to the default deck.
    func addBasicNotes(count: UInt32) async throws {
        let basic = try await getNotetypeIdByName(.with { $0.val = "Basic" })
        let template = try await newNote(basic)
        let requests = (0..<count).map { index in
            Anki_Notes_AddNoteRequest.with {
                $0.note = template
                $0.note.fields = ["Question \(index)", "Answer \(index)"]
                $0.deckID = 1
            }
        }
        _ = try await addNotes(.with { $0.requests = requests })
    }
}
