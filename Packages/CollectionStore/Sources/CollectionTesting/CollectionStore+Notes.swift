import AnkiCore
import AnkiProto
import CollectionStore
import Foundation

extension CollectionStore {
    /// Adds notes of a stock note type, such as `"Cloze"` or
    /// `"Basic (type in the answer)"`, to a deck, one note per entry of
    /// `fields` (field values in the note type's field order). Returns the
    /// new notes' ids.
    @discardableResult
    public func addNotes(ofType notetypeName: String, fields: [[String]], toDeck deckID: Int64) async throws -> [Int64] {
        let notetype = try await core.getNotetypeIdByName(.with { $0.val = notetypeName })
        let template = try await core.newNote(notetype)
        let requests = fields.map { values in
            Anki_Notes_AddNoteRequest.with {
                $0.note = template
                // Each note needs its own GUID, which the template already has.
                $0.note.guid = newNoteGUID()
                $0.note.fields = values
                $0.deckID = deckID
            }
        }
        return try await modify(.addNotes(.with { $0.requests = requests })).nids
    }

    /// Adds a media file to the collection's media folder through the core,
    /// as attaching an image or recording does. Returns the name the core
    /// stored it under, which notes refer to.
    @discardableResult
    public func addMediaFile(named name: String, data: Data) async throws -> String {
        try await core.addMediaFile(.with {
            $0.desiredName = name
            $0.data = data
        }).val
    }
}

/// A new note GUID, made as Anki makes them: a random 64-bit number written in
/// base 91. A note template from `newNote` carries one GUID, and the core keeps
/// whatever GUID a note is added with, so notes added from one template would
/// otherwise share it, and imports would take them for one note.
func newNoteGUID() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~")
    var value = UInt64.random(in: .min ... .max)
    var guid = ""
    repeat {
        guid.append(alphabet[Int(value % 91)])
        value /= 91
    } while value > 0
    return guid
}
