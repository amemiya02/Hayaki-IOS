import AnkiCore
import AnkiProto
import Foundation
import Testing

/// A throwaway collection folder, removed when the test ends.
private struct TemporaryCollection: ~Copyable {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("hayaki-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var openRequest: Anki_Collection_OpenCollectionRequest {
        .with {
            $0.collectionPath = folder.appendingPathComponent("collection.anki2").path
            $0.mediaFolderPath = folder.appendingPathComponent("collection.media").path
            $0.mediaDbPath = folder.appendingPathComponent("collection.media.db2").path
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}

private func openBackend(language: String = "en") throws -> Backend {
    try Backend(init: Anki_Backend_BackendInit.with { $0.preferredLangs = [language] }.serializedData())
}

private func call<Response: SwiftProtobuf.Message>(
    _ backend: Backend,
    _ method: CoreMethod,
    _ request: some SwiftProtobuf.Message,
    returning: Response.Type
) throws -> Response {
    try Response(serializedBytes: backend.run(method, input: request.serializedData()))
}

@Suite("Bridge to the core")
struct BackendTests {
    @Test("A new collection answers a call with data and closes cleanly")
    func newCollectionRoundTrip() throws {
        let collection = try TemporaryCollection()
        let backend = try openBackend()

        _ = try backend.run(CoreMethod.Collection.openCollection, input: collection.openRequest.serializedData())

        let names = try call(
            backend,
            CoreMethod.Decks.getDeckNames,
            Anki_Decks_GetDeckNamesRequest.with { $0.skipEmptyDefault = false; $0.includeFiltered = true },
            returning: Anki_Decks_DeckNames.self
        )
        #expect(names.entries.map(\.name) == ["Default"])

        _ = try backend.run(
            CoreMethod.Collection.closeCollection,
            input: Anki_Collection_CloseCollectionRequest().serializedData()
        )
        #expect(FileManager.default.fileExists(atPath: collection.openRequest.collectionPath))
    }

    @Test("A panic inside the core comes back as an error and the backend keeps working")
    func panicBecomesError() throws {
        let backend = try openBackend()

        // Upstream's AddMediaFromUrl unwraps the open collection without checking
        // for one, so with no collection open it panics before any network access.
        let failure = #expect(throws: BackendFailure.self) {
            try backend.run(
                CoreMethod.Media.addMediaFromUrl,
                input: Anki_Media_AddMediaFromUrlRequest.with { $0.url = "https://example.invalid/a.png" }
                    .serializedData()
            )
        }
        let error = try Anki_Backend_BackendError(serializedBytes: try #require(failure).encodedError)
        #expect(error.kind == .ankidroidPanicError)
        #expect(error.message.contains("unwrap"))

        // The same backend still answers. (That panic happened while the core held
        // its collection lock, which poisons the lock, so this check uses a call
        // that does not need the collection.)
        let text = try call(
            backend,
            CoreMethod.I18n.formatTimespan,
            Anki_I18n_FormatTimespanRequest.with {
                $0.seconds = 60
                $0.context = .precise
            },
            returning: Anki_Generic_String.self
        )
        #expect(text.val == "\u{2068}1\u{2069} minute")
    }

    @Test("An ordinary core error comes back as a typed error, not a panic")
    func coreErrorIsReported() throws {
        let backend = try openBackend()
        let failure = #expect(throws: BackendFailure.self) {
            // No collection is open.
            try backend.run(
                CoreMethod.Decks.getDeckNames,
                input: Anki_Decks_GetDeckNamesRequest().serializedData()
            )
        }
        let error = try Anki_Backend_BackendError(serializedBytes: try #require(failure).encodedError)
        #expect(error.kind != .ankidroidPanicError)
        #expect(!error.message.isEmpty)
    }

    @Test(
        "The core's own translations are built in",
        // Expected texts are copied from vendor/anki/ftl/core-repo/core/*/scheduling.ftl.
        // Fluent wraps the number in Unicode isolation marks (U+2068, U+2069);
        // the German file uses a no-break space (U+00A0).
        arguments: [
            ("ja", "\u{2068}3\u{2069} 日"),
            ("zh-CN", "\u{2068}3\u{2069} 天"),
            ("de", "\u{2068}3\u{2069}\u{00A0}Tage"),
            ("en", "\u{2068}3\u{2069} days"),
        ]
    )
    func translationsArePresent(language: String, expected: String) throws {
        let backend = try openBackend(language: language)
        let text = try call(
            backend,
            CoreMethod.I18n.formatTimespan,
            Anki_I18n_FormatTimespanRequest.with {
                $0.seconds = 3 * 86_400
                $0.context = .precise
            },
            returning: Anki_Generic_String.self
        )
        #expect(text.val == expected)
    }
}
