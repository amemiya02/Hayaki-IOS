import Foundation
import Synchronization
import SyncFeature

/// Stands in for the Keychain on the Mac, where tests have no Keychain access
/// group. It keeps exactly what the app would put in the Keychain, so tests can
/// look at what was stored.
final class MemoryAccountStorage: SyncAccountStorage {
    private let stored = Mutex<Data?>(nil)

    init(_ account: SyncAccount? = nil) {
        if let account { try? save(account) }
    }

    init(storedText: String) {
        stored.withLock { $0 = Data(storedText.utf8) }
    }

    /// The stored bytes, as text: what would be in the Keychain item.
    var storedText: String? {
        stored.withLock { $0.map { String(decoding: $0, as: UTF8.self) } }
    }

    func load() throws -> SyncAccount? {
        try stored.withLock { data in
            try data.map { try JSONDecoder().decode(SyncAccount.self, from: $0) }
        }
    }

    func save(_ account: SyncAccount) throws {
        let data = try JSONEncoder().encode(account)
        stored.withLock { $0 = data }
    }

    func remove() throws {
        stored.withLock { $0 = nil }
    }
}
