import CollectionTesting
import Foundation
import PackagesFeature
import Testing

@MainActor
@Suite("Delimited text import")
struct TextImportTests {
    @Test("A preview shows UTF-8 columns and import uses the selected field mapping")
    func textFieldMapping() async throws {
        try await withTemporaryCollection { store in
            let folder = try TemporaryFolder()
            let file = folder.url.appendingPathComponent("vocabulary.txt")
            try Data("日|sun\n月|moon\n".utf8).write(to: file)
            let model = TextImportModel(store: store)

            await model.prepare(file)

            let metadata = try #require(model.metadata)
            #expect(metadata.delimiter == .pipe)
            #expect(metadata.preview.first?.vals == ["日", "sun"])
            model.setFieldColumn(2, forField: 0)
            model.setFieldColumn(1, forField: 1)

            await model.startImport()

            #expect(model.summary?.added == 2)
            let fields = try await store.snapshot().notes.map(\.fields)
            #expect(Set(fields) == Set([["sun", "日"], ["moon", "月"]]))
        }
    }

    @Test("Updating, preserving, and adding duplicates produce different collection changes")
    func duplicateResolution() async throws {
        try await withTemporaryCollection { store in
            let folder = try TemporaryFolder()
            let original = folder.url.appendingPathComponent("original.csv")
            let revision = folder.url.appendingPathComponent("revision.csv")
            try "Word,Meaning\n".write(to: original, atomically: true, encoding: .utf8)
            try "Word,Updated meaning\n".write(to: revision, atomically: true, encoding: .utf8)
            let model = TextImportModel(store: store)
            await model.prepare(original)
            await model.startImport()
            #expect(model.summary?.added == 1)

            await model.prepare(revision)
            model.updateOptions { $0.dupeResolution = .preserve }
            await model.startImport()
            #expect(model.summary?.skipped == 1)

            await model.prepare(revision)
            model.updateOptions { $0.dupeResolution = .update }
            await model.startImport()
            #expect(model.summary?.updated == 1)

            await model.prepare(original)
            model.updateOptions { $0.dupeResolution = .duplicate }
            await model.startImport()
            #expect(model.summary?.added == 1)
            let storedFields = try await store.snapshot().notes.map(\.fields)
            #expect(Set(storedFields) == Set([["Word", "Meaning"], ["Word", "Updated meaning"]]))
        }
    }
}
