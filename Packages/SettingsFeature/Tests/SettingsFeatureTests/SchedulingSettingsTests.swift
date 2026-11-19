import CollectionTesting
import Testing

struct SchedulingSettingsTests {
    @Test func concurrentChangesPreserveOtherCollectionPreferences() async throws {
        try await withTemporaryCollection { store in
            let initial = try await store.core.getPreferences()
            #expect(initial.scheduling.rollover == 4)
            #expect(initial.scheduling.learnAheadSecs == 20 * 60)

            async let rollover: Void = store.updateSchedulingPreferences { $0.rollover = 8 }
            async let learnAhead: Void = store.updateSchedulingPreferences { $0.learnAheadSecs = 5 * 60 }
            _ = try await (rollover, learnAhead)

            let saved = try await store.core.getPreferences()
            #expect(saved.scheduling.rollover == 8)
            #expect(saved.scheduling.learnAheadSecs == 5 * 60)
            #expect(saved.reviewing == initial.reviewing)
            #expect(saved.editing == initial.editing)
            #expect(saved.backups == initial.backups)
        }
    }
}
