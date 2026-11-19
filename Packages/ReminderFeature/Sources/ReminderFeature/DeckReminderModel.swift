import AnkiCore
import CollectionStore
import Foundation
import Observation

public struct DeckReminder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Nil means all decks in the profile. Existing saved deck IDs keep their format.
    public var deckID: Int64?
    public var hour: Int
    public var minute: Int
    public var enabled = true
    public var minimumCards = 1
    public var countNew = true
    public var countLearning = true
    public var countReview = true
    public var onlyWithoutReviews = false

    public init(deckID: Int64? = nil, hour: Int, minute: Int) {
        id = UUID()
        self.deckID = deckID
        self.hour = hour
        self.minute = minute
    }

    public var time: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    static func load(profileID: UUID, from defaults: UserDefaults) -> [Self] {
        guard let data = defaults.data(forKey: key(for: profileID)) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }

    static func save(_ reminders: [Self], profileID: UUID, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: key(for: profileID))
    }

    private static func key(for profileID: UUID) -> String { "reminder.decks.\(profileID.uuidString)" }
}

public struct DeckReminderDestination: Equatable, Sendable {
    public let profileID: UUID
    /// Nil opens the profile's deck list.
    public let deckID: Int64?
    let ruleID: UUID
    let isSnoozed: Bool

    static let prefix = ScheduledReminder.identifierPrefix + "deck."

    static func identifierStem(profileID: UUID, deckID: Int64?, ruleID: UUID) -> String {
        let scope = deckID.map(String.init) ?? "all"
        return prefix + "\(profileID.uuidString).\(scope).\(ruleID.uuidString)."
    }

    init?(identifier: String) {
        guard identifier.hasPrefix(Self.prefix) else { return nil }
        let parts = identifier.dropFirst(Self.prefix.count).split(separator: ".")
        guard parts.count == 4, let profileID = UUID(uuidString: String(parts[0])),
              let ruleID = UUID(uuidString: String(parts[2]))
        else { return nil }
        if parts[1] == "all" {
            deckID = nil
        } else {
            guard let id = Int64(parts[1]), id > 0 else { return nil }
            deckID = id
        }
        self.profileID = profileID
        self.ruleID = ruleID
        isSnoozed = parts[3].hasPrefix("snoozed-")
    }

    var identifierStem: String { Self.identifierStem(profileID: profileID, deckID: deckID, ruleID: ruleID) }
}

@MainActor
@Observable
public final class DeckReminderModel {
    public struct Deck: Identifiable, Sendable {
        public let id: Int64
        public let name: String
    }

    public private(set) var rules: [DeckReminder]
    public private(set) var decks: [Deck] = []
    public private(set) var notificationsRefused = false
    @ObservationIgnored private let profileID: UUID
    @ObservationIgnored private let centre: any NotificationCentre
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private let schedule: ReminderSchedule

    public init(
        store: CollectionStore,
        profileID: UUID,
        centre: any NotificationCentre = SystemNotificationCentre(),
        defaults: UserDefaults = .standard
    ) {
        self.profileID = profileID
        self.centre = centre
        self.defaults = defaults
        self.store = store
        schedule = ReminderSchedule(store: store, centre: centre, defaults: defaults, profileID: profileID)
        rules = DeckReminder.load(profileID: profileID, from: defaults)
    }

    public func refresh() async {
        if let names = try? await store.core.getDeckNames(.with { $0.includeFiltered = true }) {
            decks = names.entries.map { Deck(id: $0.id, name: $0.name) }
        }
        notificationsRefused = await centre.permission() == .denied
    }

    public func save(_ rule: DeckReminder) async {
        guard store.allowsNewProfileWork, (0..<24).contains(rule.hour), (0..<60).contains(rule.minute)
        else { return }
        var updated = DeckReminder.load(profileID: profileID, from: defaults)
        if let index = updated.firstIndex(where: { $0.id == rule.id }) {
            updated[index] = rule
        } else {
            updated.append(rule)
        }
        persist(updated)

        if rule.enabled {
            if await centre.permission() == .notDetermined {
                _ = try? await centre.requestPermission()
            }
            notificationsRefused = await centre.permission() != .allowed
        }
        await schedule.update()
    }

    public func delete(_ id: UUID) async {
        var updated = DeckReminder.load(profileID: profileID, from: defaults)
        updated.removeAll { $0.id == id }
        persist(updated)
        await schedule.update()
    }

    private func persist(_ updated: [DeckReminder]) {
        DeckReminder.save(updated, profileID: profileID, to: defaults)
        rules = updated
    }
}
