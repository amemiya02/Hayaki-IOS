import SwiftUI

/// Destinations opened by the reviewer. The app composes these features,
/// avoiding dependencies between the reviewer and the screens it presents.
public enum ReviewerDestination: Hashable, Identifiable, Sendable {
    case browse(search: String, cardID: Int64? = nil)
    case statistics(deckID: Int64)
    case deckOptions(deckID: Int64)
    case customStudy(deckID: Int64)
    case cardInfo(cardID: Int64)
    case addNote(homeDeckID: Int64?)

    public var id: Self { self }
}

public extension View {
    func reviewerDestination<Destination: View>(
        @ViewBuilder _ destination: @escaping @MainActor @Sendable (ReviewerDestination) -> Destination
    ) -> some View {
        reviewerDestination { route, _ in destination(route) }
    }

    func reviewerDestination<Destination: View>(
        @ViewBuilder _ destination: @escaping @MainActor @Sendable (
            ReviewerDestination, @escaping @MainActor (StudyDeck) -> Void
        ) -> Destination
    ) -> some View {
        environment(\.reviewerDestination) { route, study in AnyView(destination(route, study)) }
    }
}

typealias ReviewerDestinationFactory = @MainActor @Sendable (
    ReviewerDestination, @escaping @MainActor (StudyDeck) -> Void
) -> AnyView

private struct ReviewerDestinationKey: EnvironmentKey {
    static let defaultValue: ReviewerDestinationFactory? = nil
}

extension EnvironmentValues {
    var reviewerDestination: ReviewerDestinationFactory? {
        get { self[ReviewerDestinationKey.self] }
        set { self[ReviewerDestinationKey.self] = newValue }
    }
}
