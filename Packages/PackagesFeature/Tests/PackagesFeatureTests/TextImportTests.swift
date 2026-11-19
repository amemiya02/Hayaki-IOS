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

            #expect(model.summary?.changes.added.count == 2)
            let fields = try await store.snapshot().notes.map(\.fields)
            #expect(Set(fields) == Set([["sun", "日"], ["moon", "月"]]))
        }
    }
}
