import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct StatisticsPDF: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    private init(data: Data) { self.data = data }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    @MainActor
    static func make(
        graphs: StatisticsGraphs, preferences: StatisticsPreferences, scope: Text, locale: Locale
    ) throws -> Self {
        let data = NSMutableData()
        var paper = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &paper, nil)
        else { throw CocoaError(.fileWriteUnknown) }

        let sections: [AnyView] = [
            AnyView(TodaySection(graphs: graphs)),
            AnyView(ForecastSection(graphs: graphs, includeBacklog: .constant(preferences.includeBacklog))),
            AnyView(CalendarSection(graphs: graphs, firstWeekday: .constant(preferences.firstWeekday))),
            AnyView(ReviewHistorySection(graphs: graphs)),
            AnyView(ReviewHistorySection(graphs: graphs, reportReviewTime: true)),
            AnyView(CardCountsSection(
                counts: graphs.cardCounts(separateInactive: preferences.separateInactive),
                separateInactive: .constant(preferences.separateInactive)
            )),
        ] + graphs.distributions.map { AnyView(DistributionSection(data: $0)) } + [
            AnyView(TrueRetentionSection(retention: graphs.trueRetention)),
            AnyView(HourlySection(graphs: graphs)),
            AnyView(RatingsSection(graphs: graphs)),
            AnyView(AddedSection(graphs: graphs)),
        ]

        for section in sections {
            let margin: CGFloat = 32
            let available = paper.insetBy(dx: margin, dy: margin)
            let page = VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    StatisticsSection.title.font(.title2.weight(.semibold))
                    scope.font(.headline)
                    Text(graphs.period.title)
                    Text(graphs.studyDate, format: .dateTime.year().month().day())
                }
                .foregroundStyle(.primary)
                Divider()
                ForEach(sections: section) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        group.header.font(.title3.weight(.semibold))
                        group.content
                        group.footer
                    }
                }
            }
            .frame(width: available.width, alignment: .leading)
            .environment(\.locale, locale)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .medium)
            .environment(\.statisticsReportPeriod, graphs.period)

            let renderer = ImageRenderer(content: page)
            renderer.render { size, draw in
                let scale = min(1, available.height / max(1, size.height))
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: margin, y: paper.height - margin - size.height * scale)
                context.scaleBy(x: scale, y: scale)
                draw(context)
                context.restoreGState()
                context.endPDFPage()
            }
        }

        context.closePDF()
        return Self(data: data as Data)
    }
}

extension EnvironmentValues {
    @Entry var statisticsReportPeriod: StatisticsPeriod?
}
