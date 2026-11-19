import SwiftUI

struct TrueRetentionSection: View {
    let retention: [TrueRetention]
    @State private var mode: Mode = .summary

    private enum Mode: CaseIterable {
        case young, mature, summary

        var title: String {
            switch self {
            case .young: String(localized: "Young", bundle: .module)
            case .mature: String(localized: "Mature", bundle: .module)
            case .summary: String(localized: "All Cards", bundle: .module)
            }
        }
    }

    var body: some View {
        Section {
            DisclosureGroup {
                Text("True retention measures correct answers on cards with review intervals of at least one day.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } label: {
                Text("About True Retention", bundle: .module)
            }
            Picker(selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Text("Card Type", bundle: .module)
            }
            .pickerStyle(.segmented)
            ForEach(retention, id: \.window) { row in
                retentionRow(row)
            }
        } header: {
            Text("True Retention", bundle: .module)
        }
    }

    private func retentionRow(_ row: TrueRetention) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.window.title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            switch mode {
            case .summary:
                resultRow(row.young, label: Text("Young", bundle: .module))
                resultRow(row.mature, label: Text("Mature", bundle: .module))
                resultRow(row.combined, label: Text("All Cards", bundle: .module))
            case .young:
                resultRow(row.young, label: Text("Young", bundle: .module))
            case .mature:
                resultRow(row.mature, label: Text("Mature", bundle: .module))
            }
        }
    }

    private func resultRow(_ result: TrueRetention.Result, label: Text) -> some View {
        LabeledContent {
            if let rate = result.rate {
                Text("\(result.passed, format: .number) of \(result.total, format: .number) (\(rate, format: .percent.precision(.fractionLength(1))))", bundle: .module)
                    .monospacedDigit()
            } else {
                Text("No reviews", bundle: .module)
            }
        } label: {
            label
        }
        .font(.callout)
    }
}
