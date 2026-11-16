import SwiftUI

/// One block of the Statistics screen: a titled list section holding a chart,
/// or a short message in its place when there is nothing to chart.
struct StatisticsSectionView<Content: View>: View {
    let title: Text
    /// Shown instead of the content when not nil.
    let emptyMessage: Text?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            if let emptyMessage {
                emptyMessage
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
            } else {
                content()
            }
        } header: {
            title
        }
    }
}
