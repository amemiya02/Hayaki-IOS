import AnkiCore
import AnkiProto
import Foundation

public struct SavedBrowserSearch: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let query: String
}

extension CardBrowserModel {
    private static let savedSearchesKey = "savedFilters"

    public func loadSavedSearches() async {
        do {
            savedSearches = try await readSavedSearches()
        } catch {
            failure = error.localizedDescription
        }
    }

    public func openSavedSearch(_ saved: SavedBrowserSearch) async {
        searchText = saved.query
        await search()
    }

    public func saveSearch(named input: String) async {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = searchedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .loaded, !name.isEmpty, !query.isEmpty else { return }
        await updateSavedSearches { saved in
            guard saved[name] == nil else {
                failure = String(localized: "A saved search already has that name.", bundle: .module)
                return false
            }
            saved[name] = query
            return true
        }
    }

    public func removeSavedSearch(named name: String) async {
        await updateSavedSearches { $0.removeValue(forKey: name) != nil }
    }

    private func readSavedSearches() async throws(CoreError) -> [SavedBrowserSearch] {
        let saved = try await readConfig([String: String].self, key: Self.savedSearchesKey) ?? [:]
        return saved.map { SavedBrowserSearch(name: $0.key, query: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func updateSavedSearches(_ update: (inout [String: String]) -> Bool) async {
        guard !updatingSavedSearches else { return }
        updatingSavedSearches = true
        failure = nil
        defer { updatingSavedSearches = false }
        do {
            let current = try await readSavedSearches()
            var values = Dictionary(uniqueKeysWithValues: current.map { ($0.name, $0.query) })
            if update(&values) {
                try await writeConfig(values, key: Self.savedSearchesKey)
                savedSearches = values.map { SavedBrowserSearch(name: $0.key, query: $0.value) }
                    .sorted { $0.name < $1.name }
            } else {
                savedSearches = current
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}
