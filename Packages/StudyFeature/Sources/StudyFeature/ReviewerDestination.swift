import SwiftUI

/// Destinations opened by the reviewer. The app composes these features,
/// avoiding dependencies between the reviewer and the screens it presents.
public enum ReviewerDestination: Hashable, Identifiable, Sendable {
    case browse(search: String)
    case statistics(deckID: Int64)
    case deckOptions(deckID: Int64)
    case cardInfo(cardID: Int64)
    case addNote

    public var id: Self { self }
}

public extension View {
    func reviewerDestination<Destination: View>(
        @ViewBuilder _ destination: @escaping @MainActor @Sendable (ReviewerDestination) -> Destination
    ) -> some View {
        environment(\.reviewerDestination) { route in AnyView(destination(route)) }
    }
}

private struct ReviewerDestinationKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (ReviewerDestination) -> AnyView)? = nil
}

extension EnvironmentValues {
    var reviewerDestination: (@MainActor @Sendable (ReviewerDestination) -> AnyView)? {
        get { self[ReviewerDestinationKey.self] }
        set { self[ReviewerDestinationKey.self] = newValue }
    }
}
