import AppIntents
import ExtensionBridge
import SwiftUI
import WidgetKit

@main
struct HayakiWidgets: WidgetBundle {
    var body: some Widget {
        DeckListWidget()
        SingleDeckWidget()
    }
}

struct WidgetDeck: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Deck"
    static let defaultQuery = WidgetDeckQuery()

    let id: String
    let name: String

    init(_ deck: ExtensionDeck, profileID: UUID) {
        id = Self.identifier(for: deck, profileID: profileID)
        name = deck.name.replacingOccurrences(of: "::", with: " › ")
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static func identifier(for deck: ExtensionDeck, profileID: UUID) -> String {
        "\(profileID.uuidString):\(deck.id)"
    }
}

struct WidgetDeckQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetDeck] {
        let choices = Dictionary(uniqueKeysWithValues: currentDecks.map { ($0.id, $0) })
        return identifiers.compactMap { choices[$0] }
    }

    func entities(matching string: String) async throws -> [WidgetDeck] {
        currentDecks.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [WidgetDeck] { currentDecks }

    private var currentDecks: [WidgetDeck] {
        guard let snapshot = ExtensionBridge.appGroup?.snapshot() else { return [] }
        return snapshot.decks.map { WidgetDeck($0, profileID: snapshot.profileID) }
    }
}

protocol DeckWidgetIntent: WidgetConfigurationIntent {
    var selectedDecks: [WidgetDeck] { get }
}

struct DeckListConfiguration: DeckWidgetIntent {
    static let title: LocalizedStringResource = "Deck List"
    static let description = IntentDescription("Choose which decks to show, in order.")

    @Parameter(title: "Decks", size: .init(min: 1, max: 8))
    var decks: [WidgetDeck]?

    var selectedDecks: [WidgetDeck] { decks ?? [] }
}

struct SingleDeckConfiguration: DeckWidgetIntent {
    static let title: LocalizedStringResource = "One Deck"
    static let description = IntentDescription("Choose a deck to see its study counts.")
    @Parameter(title: "Deck") var deck: WidgetDeck?

    var selectedDecks: [WidgetDeck] { deck.map { [$0] } ?? [] }
}

struct DeckWidgetEntry: TimelineEntry {
    let date: Date
    let profileID: UUID?
    let decks: [ExtensionDeck]
    let emptyMessage: LocalizedStringKey

    static var placeholder: Self {
        DeckWidgetEntry(
            date: .now, profileID: nil,
            decks: [ExtensionDeck(id: 1, name: "Languages", isFiltered: false, new: 8, learning: 3, review: 12)],
            emptyMessage: "Open Hayaki to update"
        )
    }

    func destination(for deck: ExtensionDeck) -> URL {
        guard let profileID else { return deckListDestination }
        return DeckLink.deck(profileID: profileID, deckID: deck.id, action: deck.destination).url
    }

    var deckListDestination: URL { DeckLink.decks(profileID: profileID).url }
}

struct DeckWidgetProvider<Intent: DeckWidgetIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeckWidgetEntry { .placeholder }

    func snapshot(for configuration: Intent, in context: Context) async -> DeckWidgetEntry {
        context.isPreview ? .placeholder : entry(configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<DeckWidgetEntry> {
        Timeline(entries: [entry(configuration)], policy: .never)
    }

    private func entry(_ configuration: Intent) -> DeckWidgetEntry {
        guard let data = ExtensionBridge.appGroup?.snapshot() else {
            return DeckWidgetEntry(date: .now, profileID: nil, decks: [], emptyMessage: "Open Hayaki to update")
        }
        let selected = configuration.selectedDecks
        let available = Dictionary(uniqueKeysWithValues: data.decks.map {
            (WidgetDeck.identifier(for: $0, profileID: data.profileID), $0)
        })
        let decks = selected.compactMap { available[$0.id] }
        let message: LocalizedStringKey = selected.isEmpty
            ? "Edit the widget to choose decks"
            : "Selected decks are unavailable in this profile"
        return DeckWidgetEntry(date: .now, profileID: data.profileID, decks: decks, emptyMessage: message)
    }
}

struct DeckListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: ExtensionBridge.deckListWidgetKind, intent: DeckListConfiguration.self,
            provider: DeckWidgetProvider<DeckListConfiguration>()
        ) { entry in
            DeckListWidgetView(entry: entry)
        }
        .configurationDisplayName("Deck List")
        .description("Show study counts for a list of decks.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SingleDeckWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: ExtensionBridge.singleDeckWidgetKind, intent: SingleDeckConfiguration.self,
            provider: DeckWidgetProvider<SingleDeckConfiguration>()
        ) { entry in
            SingleDeckWidgetView(entry: entry)
        }
        .configurationDisplayName("One Deck")
        .description("Open a deck and see its new, learning, and review counts.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct DeckListWidgetView: View {
    let entry: DeckWidgetEntry
    @Environment(\.widgetFamily) private var family

    private let countWidth: CGFloat = 37

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Link(destination: entry.deckListDestination) {
                Text("Decks").font(.headline)
            }
            if entry.decks.isEmpty {
                Text(entry.emptyMessage).font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack {
                    Spacer()
                    countHeaders
                }
                .accessibilityHidden(true)
                ForEach(entry.decks.prefix(family == .systemLarge ? 8 : 3)) { deck in
                    Link(destination: entry.destination(for: deck)) {
                        HStack {
                            Text(verbatim: deck.name.replacingOccurrences(of: "::", with: " › "))
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            count(deck.new, "New")
                            count(deck.learning, "Learning")
                            count(deck.review, "Review")
                        }
                    }
                    .privacySensitive()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(entry.deckListDestination)
    }

    private var countHeaders: some View {
        Group {
            Image(systemName: "plus.circle")
            Image(systemName: "arrow.clockwise")
            Image(systemName: "checkmark.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: countWidth, alignment: .trailing)
    }

    private func count(_ value: Int, _ label: LocalizedStringKey) -> some View {
        Text(value, format: .number)
            .font(.subheadline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: countWidth, alignment: .trailing)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value, format: .number))
    }
}

private struct SingleDeckWidgetView: View {
    let entry: DeckWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let deck = entry.decks.first {
                Text(verbatim: deck.name.replacingOccurrences(of: "::", with: " › "))
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                metric("New", deck.new)
                metric("Learning", deck.learning)
                metric("Review", deck.review)
            } else {
                Text("One Deck").font(.headline)
                Text(entry.emptyMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .privacySensitive()
        .containerBackground(.background, for: .widget)
        .widgetURL(entry.decks.first.map(entry.destination) ?? entry.deckListDestination)
    }

    private func metric(_ label: LocalizedStringKey, _ value: Int) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value, format: .number).font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}
