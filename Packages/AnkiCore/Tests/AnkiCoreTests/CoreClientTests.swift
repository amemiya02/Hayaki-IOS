import AnkiCore
import AnkiProto
import Foundation
import Testing

@Suite("Core Client")
struct CoreClientTests {
    @Test("A typed call round-trips through the core on a new collection")
    func typedRoundTrip() async throws {
        let collection = try TemporaryCollection()
        let core = try await CoreClient(language: "en")

        try await core.openCollection(collection.openRequest)
        let names = try await core.getDeckNames(.with {
            $0.skipEmptyDefault = false
            $0.includeFiltered = true
        })
        #expect(names.entries.map(\.name) == ["Default"])
        try await core.closeCollection(.init())

        #expect(FileManager.default.fileExists(atPath: collection.openRequest.collectionPath))
    }

    @Test("A rejected call throws the core's error kind and its message in the client's language")
    func typedLocalisedError() async throws {
        let collection = try TemporaryCollection()
        let core = try await CoreClient(language: "ja")
        try await core.openCollection(collection.openRequest)

        let error = await #expect(throws: CoreError.self) {
            try await core.searchCards(.with { $0.search = "(" })
        }

        #expect(error?.kind == .searchError)
        // Copied from vendor/anki/ftl/core-repo/core/ja/search.ftl (search-unclosed-group).
        #expect(error?.message.contains("開き括弧 `(` がありますが、その後に対応する閉じ括弧 `)` がありません。") == true)
        #expect(error?.localizedDescription == error?.message)
        try await core.closeCollection(.init())
    }

    @Test("A panic inside the core is an error, and the client keeps working afterwards")
    func panicIsRecovered() async throws {
        let core = try await CoreClient(language: "en")

        // Upstream's AddMediaFromUrl unwraps the open collection without checking
        // for one, so with no collection open it panics before any network access.
        // It panics while holding the core's collection lock, which poisons the
        // lock: that backend could never open a collection again.
        let error = await #expect(throws: CoreError.self) {
            try await core.addMediaFromUrl(.with { $0.url = "https://example.invalid/a.png" })
        }
        #expect(error?.isPanic == true)
        #expect(error?.message.contains("unwrap") == true)

        let collection = try TemporaryCollection()
        try await core.openCollection(collection.openRequest)
        let names = try await core.getDeckNames(.with { $0.includeFiltered = true })
        #expect(names.entries.map(\.name) == ["Default"])
        try await core.closeCollection(.init())
    }

    @Test("A long operation reports its progress while it runs")
    func longOperationProgress() async throws {
        let collection = try TemporaryCollection()
        let core = try await CoreClient(language: "en")
        try await core.openCollection(collection.openRequest)
        try await core.addBasicNotes(count: Self.manyNotes)

        let check = core.start(.checkDatabase(), pollingInterval: .milliseconds(20))
        var reports: [Anki_Collection_Progress.DatabaseCheck] = []
        for await progress in check.progress {
            if case .databaseCheck(let report) = progress.value { reports.append(report) }
        }
        _ = try await check.result

        // The check walks every note, reporting how far it has got.
        let noteReports = reports.filter { $0.stageTotal == Self.manyNotes }
        #expect(!noteReports.isEmpty)
        #expect(noteReports.contains { $0.stageCurrent > 0 && $0.stageCurrent < Self.manyNotes })
        try await core.closeCollection(.init())
    }

    @Test("Cancelling a long operation stops the work inside the core")
    func longOperationCancel() async throws {
        let collection = try TemporaryCollection()
        let core = try await CoreClient(language: "en")
        try await core.openCollection(collection.openRequest)
        try await core.addBasicNotes(count: Self.manyNotes)

        let check = core.start(.checkDatabase(), pollingInterval: .milliseconds(20))
        // Cancel as soon as the check is walking the notes.
        for await progress in check.progress {
            if case .databaseCheck(let report) = progress.value, report.stageTotal == Self.manyNotes {
                check.cancel()
                break
            }
        }

        let error = await #expect(throws: CoreError.self) { try await check.result }
        #expect(error?.isInterrupted == true)

        // The check ran in a transaction the core rolled back; the collection
        // is intact and the client goes on working.
        let cards = try await core.searchCards(.with { $0.search = "" })
        #expect(cards.ids.count == Int(Self.manyNotes))
        try await core.closeCollection(.init())
    }

    @Test("A long operation cancelled before it starts never runs")
    func longOperationCancelledWhileQueued() async throws {
        let collection = try TemporaryCollection()
        let core = try await CoreClient(language: "en")
        try await core.openCollection(collection.openRequest)
        try await core.addBasicNotes(count: Self.manyNotes)

        // The first check keeps the worker busy, so the second one waits.
        let first = core.start(.checkDatabase())
        let second = core.start(.checkDatabase())
        second.cancel()

        _ = try await first.result
        let error = await #expect(throws: CoreError.self) { try await second.result }
        #expect(error?.isInterrupted == true)
        try await core.closeCollection(.init())
    }

    @Test("The main actor stays free while a call works inside the core")
    @MainActor
    func mainActorStaysFree() async throws {
        let collection = try TemporaryCollection()
        let core = try await CoreClient(language: "en")
        try await core.openCollection(collection.openRequest)
        try await core.addBasicNotes(count: Self.manyNotes)

        let clock = ContinuousClock()
        let started = clock.now
        let ticking = Task { @MainActor in
            var ticks = 0
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(for: .milliseconds(10))
            }
            return ticks
        }
        _ = try await core.checkDatabase()
        let elapsed = clock.now - started
        ticking.cancel()
        let ticks = await ticking.value

        // Had the check run on the main thread, the main actor could not have
        // woken up while it ran.
        #expect(elapsed > .milliseconds(300))
        #expect(ticks >= 10)
        try await core.closeCollection(.init())
    }

    /// Enough notes that checking them takes about two seconds on a busy
    /// Apple silicon Mac, far longer than the core's 0.1 second progress
    /// throttle, so progress and cancellation are observed reliably.
    static let manyNotes: UInt32 = 10_000

    @Test(
        "The core speaks the one language the client was started with",
        // Expected texts are copied from vendor/anki/ftl/core-repo/core/*/scheduling.ftl.
        // Fluent wraps the number in Unicode isolation marks (U+2068, U+2069);
        // the German file uses a no-break space (U+00A0).
        arguments: [
            ("ja", "\u{2068}3\u{2069} 日"),
            ("zh-CN", "\u{2068}3\u{2069} 天"),
            ("zh-Hans", "\u{2068}3\u{2069} 天"),
            ("und", "\u{2068}3\u{2069} days"),
            ("de", "\u{2068}3\u{2069}\u{00A0}Tage"),
            ("en", "\u{2068}3\u{2069} days"),
        ]
    )
    func oneLanguage(language: String, expected: String) async throws {
        let core = try await CoreClient(language: language)
        let text = try await core.formatTimespan(.with {
            $0.seconds = 3 * 86_400
            $0.context = .precise
        })
        #expect(text.val == expected)
    }

    @Test(
        "The reviewer uses localized short units for rating intervals",
        arguments: [("en", "m"), ("ja", "分"), ("zh-Hans", "分"), ("und", "m")]
    )
    func answerButtonLanguage(language: String, minuteSuffix: String) async throws {
        let core = try await CoreClient(language: language)
        let text = try await core.formatTimespan(.with {
            $0.seconds = 3 * 60
            $0.context = .answerButtons
        })
        #expect(text.val.hasSuffix(minuteSuffix))
    }

    @Test("Right-to-left core translations retain number isolation", arguments: ["ar", "ar-SA"])
    func rightToLeftLanguage(language: String) async throws {
        let collection = try TemporaryCollection()
        let core = try await CoreClient(language: language)
        try await core.openCollection(collection.openRequest)

        let interval = try await core.formatTimespan(.with {
            $0.seconds = 3 * 86_400
            $0.context = .precise
        })
        #expect(interval.val.range(of: "\\p{Arabic}", options: .regularExpression) != nil)
        #expect(interval.val.contains("\u{2068}"))
        #expect(interval.val.contains("\u{2069}"))

        let error = await #expect(throws: CoreError.self) {
            try await core.searchCards(.with { $0.search = "(" })
        }
        #expect(error?.kind == .searchError)
        #expect(error?.message.range(of: "\\p{Arabic}", options: .regularExpression) != nil)
        try await core.closeCollection(.init())
    }
}
