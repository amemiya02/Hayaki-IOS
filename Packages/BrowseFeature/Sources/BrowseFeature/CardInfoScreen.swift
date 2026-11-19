import CollectionStore
import NoteEditorFeature
import SwiftUI

/// Everything about one card: its note's fields, its deck, when it is due
/// and its review history.
public struct CardInfoScreen: View {
    @State private var model: CardDetailModel
    @State private var isEditing = false
    @State private var didDeleteNote = false
    @Environment(\.dismiss) private var dismiss
    private let store: CollectionStore

    public init(store: CollectionStore, cardID: Int64) {
        self.store = store
        _model = State(initialValue: CardDetailModel(store: store, cardID: cardID))
    }

    public var body: some View {
        content
            .navigationTitle(Text("Card Info", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if case .loaded = model.state {
                    ToolbarItem(placement: .primaryAction) {
                        Button { isEditing = true } label: {
                            Label {
                                Text("Edit Note", bundle: .module)
                            } icon: {
                                Image(systemName: "square.and.pencil")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isEditing, onDismiss: {
                guard didDeleteNote else { return }
                didDeleteNote = false
                dismiss()
            }) {
                NoteEditorScreen(store: store, editingCardID: model.cardID) {
                    didDeleteNote = true
                }
            }
            .task { await model.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .deleted:
            ContentUnavailableView {
                Label {
                    Text("Card Deleted", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                }
            } description: {
                Text("This card is no longer in the collection.", bundle: .module)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label {
                    Text("Could Not Show Card", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(message)
            } actions: {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Text("Try Again", bundle: .module)
                }
            }
        case .loaded(let detail):
            CardDetailList(detail: detail)
        }
    }
}

private struct CardDetailList: View {
    let detail: CardDetail

    var body: some View {
        List {
            Section {
                ForEach(Array(detail.fields.enumerated()), id: \.offset) { _, field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: field.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(verbatim: field.text.isEmpty ? "–" : field.text)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Note", bundle: .module)
            }

            Section {
                LabeledContent {
                    Text(verbatim: detail.deck)
                } label: {
                    Text("Deck", bundle: .module)
                }
                if let originalDeck = detail.originalDeck {
                    LabeledContent {
                        Text(verbatim: originalDeck)
                    } label: {
                        Text("Home Deck", bundle: .module)
                    }
                }
                LabeledContent {
                    dueText
                } label: {
                    Text("Due", bundle: .module)
                }
                if detail.status != .normal {
                    LabeledContent {
                        statusText
                    } label: {
                        Text("Status", bundle: .module)
                    }
                }
                if detail.intervalDays > 0 {
                    LabeledContent {
                        Text("\(detail.intervalDays) days", bundle: .module)
                    } label: {
                        Text("Interval", bundle: .module)
                    }
                }
                LabeledContent {
                    Text(detail.reviewCount, format: .number)
                } label: {
                    Text("Reviews", bundle: .module)
                }
                LabeledContent {
                    Text(detail.lapseCount, format: .number)
                } label: {
                    Text("Lapses", bundle: .module)
                }
                LabeledContent {
                    Text(detail.added, format: .dateTime.year().month().day())
                } label: {
                    Text("Added", bundle: .module)
                }
                LabeledContent {
                    Text(verbatim: detail.noteType)
                } label: {
                    Text("Note Type", bundle: .module)
                }
                LabeledContent {
                    Text(verbatim: detail.cardTemplate)
                } label: {
                    Text("Card Template", bundle: .module)
                }
                SchedulingDetails(detail: detail)
            } header: {
                Text("Card", bundle: .module)
            }

            Section {
                if detail.history.isEmpty {
                    Text("Not reviewed yet.", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(detail.history.enumerated()), id: \.offset) { _, review in
                        ReviewRow(review: review)
                    }
                }
            } header: {
                Text("Review History", bundle: .module)
            }
        }
    }

    private var dueText: Text {
        switch detail.due {
        case .newCardPosition(let position):
            Text("New card #\(position)", bundle: .module)
        case .date(let date):
            Text(date, format: .dateTime.year().month().day())
        case .unknown:
            Text(verbatim: "–")
        }
    }

    private var statusText: Text {
        switch detail.status {
        case .normal: Text(verbatim: "")
        case .suspended: Text("Suspended", bundle: .module)
        case .buried: Text("Buried", bundle: .module)
        }
    }
}

private struct SchedulingDetails: View {
    let detail: CardDetail

    var body: some View {
        if let first = detail.firstReview {
            item(Text("First Review", bundle: .module), Text(first, format: .dateTime.year().month().day()))
        }
        if let latest = detail.latestReview {
            item(Text("Latest Review", bundle: .module), Text(latest, format: .dateTime.year().month().day()))
        }
        if let memory = detail.memoryState {
            item(Text("Stability", bundle: .module), Text(memory.stabilityDays, format: .number.precision(.fractionLength(0...1))) + Text(" days", bundle: .module))
            item(Text("Difficulty", bundle: .module), Text(memory.difficulty, format: .percent.precision(.fractionLength(0))))
            if let retrievability = detail.retrievability {
                item(Text("Retrievability", bundle: .module), Text(retrievability, format: .percent.precision(.fractionLength(0))))
            }
        } else if let ease = detail.ease {
            item(Text("Ease", bundle: .module), Text(ease, format: .percent.precision(.fractionLength(0...1))))
        }
        if detail.totalSeconds > 0 {
            item(Text("Average Time", bundle: .module), Text(detail.averageSeconds.formatted(.number.precision(.fractionLength(0...1))) + " s"))
            item(Text("Total Time", bundle: .module), Text(detail.totalSeconds.formatted(.number.precision(.fractionLength(0...1))) + " s"))
        }
        item(Text("Preset", bundle: .module), Text(verbatim: detail.preset))
        item(Text("Card ID", bundle: .module), Text(verbatim: String(detail.cardID)))
        item(Text("Note ID", bundle: .module), Text(verbatim: String(detail.noteID)))
        if !detail.customData.isEmpty {
            item(Text("Custom Data", bundle: .module), Text(verbatim: detail.customData))
        }
    }

    private func item(_ title: Text, _ value: Text) -> some View {
        LabeledContent {
            value.textSelection(.enabled)
        } label: {
            title
        }
    }
}

/// One review: when, what kind, the rating, the interval it led to and how
/// long the learner took.
private struct ReviewRow: View {
    let review: CardDetail.Review

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.date, format: .dateTime.year().month().day().hour().minute())
                Spacer()
                ratingText
                    .foregroundStyle(ratingColor)
            }
            HStack(spacing: 6) {
                kindText
                if review.intervalSeconds > 0 {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text("Interval \(intervalText)", bundle: .module)
                }
                if let ease = review.ease {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text("Ease \(ease.formatted(.percent.precision(.fractionLength(0...1))))", bundle: .module)
                }
                if review.secondsTaken > 0 {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text("Took \(takenText)", bundle: .module)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var intervalText: String {
        Duration.seconds(review.intervalSeconds).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
        )
    }

    private var takenText: String {
        Duration.seconds(review.secondsTaken).formatted(
            .units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
        )
    }

    private var kindText: Text {
        switch review.kind {
        case .learning: Text("Learning", bundle: .module)
        case .review: Text("Review", bundle: .module)
        case .relearning: Text("Relearning", bundle: .module)
        case .filtered: Text("Filtered", bundle: .module)
        case .manual: Text("Manual", bundle: .module)
        case .rescheduled: Text("Rescheduled", bundle: .module)
        }
    }

    private var ratingText: Text {
        switch review.rating {
        case .again: Text("Again", bundle: .module)
        case .hard: Text("Hard", bundle: .module)
        case .good: Text("Good", bundle: .module)
        case .easy: Text("Easy", bundle: .module)
        case nil: Text(verbatim: "")
        }
    }

    private var ratingColor: Color {
        switch review.rating {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        case nil: .secondary
        }
    }
}
