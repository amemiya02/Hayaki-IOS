import HayakiAppearance
import SwiftUI

/// The header of a statistics block: its title and, under it, a one-line
/// plain-language reading of the chart, such as "About 85 cards a day are due
/// over the next 7 days".
struct StatisticsCardHeader: View {
    let title: Text
    var reading: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .accessibilityAddTraits(.isHeader)
            if let reading {
                reading
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One block of the Statistics screen drawn as a rounded card: the section's
/// header, then its rows with a full-width separator between them.
///
/// The blocks stay plain `Section`s, so the PDF report can lay out the same
/// views; the screen turns each one into a card with `ForEach(sections:)`.
struct StatisticsCard: View {
    let section: SectionConfiguration
    @Environment(\.hayakiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section.header
                .font(.headline)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(section.content) { row in
                    if row.id != section.content.first?.id {
                        Divider()
                    }
                    row
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
            }
            section.footer
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.surface, in: .rect(cornerRadius: 20, style: .continuous))
    }
}
