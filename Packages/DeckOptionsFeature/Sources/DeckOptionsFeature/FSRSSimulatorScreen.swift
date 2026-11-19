import Charts
import SwiftUI

struct FSRSSimulatorScreen: View {
    let model: DeckOptionsModel
    let workload: Bool
    @State private var input: FSRSSimulationSettings
    @State private var runs: [Run] = []
    @State private var metric: Metric
    @State private var selectedX: Int?
    @State private var smoothing = true
    @State private var isRunning = false
    @State private var error: String?
    @State private var confirmingApply = false
    @Environment(\.dismiss) private var dismiss

    init(model: DeckOptionsModel, workload: Bool) {
        self.model = model
        self.workload = workload
        _input = State(initialValue: model.fsrsSimulationSettings(workload: workload))
        _metric = State(initialValue: workload ? .efficiency : .reviews)
    }

    var body: some View {
        NavigationStack {
            Form {
                simulationInput.disabled(isRunning)
                Section {
                    Button {
                        Task { await simulate() }
                    } label: {
                        Text("Simulate", bundle: .module)
                    }
                    .disabled(isRunning)
                    if isRunning {
                        ProgressView { Text("Simulating…", bundle: .module) }
                    }
                    Button {
                        runs.removeLast()
                        selectedX = nil
                    } label: {
                        Text("Clear Last Simulation", bundle: .module)
                    }
                    .disabled(runs.isEmpty || isRunning)
                    Button {
                        confirmingApply = true
                    } label: {
                        Text("Use These Options in the Preset", bundle: .module)
                    }
                    .disabled(isRunning)
                    if let error {
                        Text(verbatim: error).foregroundStyle(.red)
                    }
                }
                if !runs.isEmpty { results }
            }
            .navigationTitle(workload
                ? Text("Compare Desired Retention", bundle: .module)
                : Text("FSRS Simulator", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                    .disabled(isRunning)
                }
            }
            .confirmationDialog(
                Text("Apply these options to the shared preset?", bundle: .module),
                isPresented: $confirmingApply,
                titleVisibility: .visible
            ) {
                Button {
                    model.applyFSRSSimulation(input, workload: workload)
                    dismiss()
                } label: {
                    Text("Apply to Preset", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            }
        }
        .interactiveDismissDisabled(isRunning)
    }

    private var simulationInput: some View {
        Section {
            SimulatorNumberRow(value: $input.days, range: 1...3650) {
                Text("Days to simulate", bundle: .module)
            }
            SimulatorNumberRow(value: $input.additionalNewCards, range: 0...100_000) {
                Text("Additional new cards", bundle: .module)
            }
            if !workload {
                RetentionStepper(value: $input.desiredRetention) {
                    Text("Desired retention", bundle: .module)
                }
            }
            SimulatorNumberRow(value: $input.newLimit, range: 0...9999) {
                Text("New cards/day", bundle: .module)
            }
            SimulatorNumberRow(value: $input.reviewLimit, range: 0...9999) {
                Text("Maximum reviews/day", bundle: .module)
            }
            DisclosureGroup {
                EasyDaysRows(values: $input.easyDays)
            } label: {
                Text("Easy Days", bundle: .module)
            }
            DisclosureGroup {
                SimulatorNumberRow(value: $input.maximumInterval, range: 1...36_500) {
                    Text("Maximum interval (days)", bundle: .module)
                }
                Picker(selection: $input.reviewOrder) {
                    ForEach(ReviewSortOrder.allCases, id: \.self) { order in
                        order.title.tag(order)
                    }
                } label: {
                    Text("Review sort order", bundle: .module)
                }
                Toggle(isOn: $input.newCardsIgnoreReviewLimit) {
                    Text("New cards ignore review limit", bundle: .module)
                }
                if !workload {
                    Toggle(isOn: $smoothing) {
                        Text("Smooth graphs", bundle: .module)
                    }
                }
                Toggle(isOn: $input.suspendLeeches) {
                    Text("Suspend leeches", bundle: .module)
                }
                if input.suspendLeeches {
                    SimulatorNumberRow(value: $input.leechThreshold, range: 1...9999) {
                        Text("Leech threshold", bundle: .module)
                    }
                }
            } label: {
                Text("Advanced Settings", bundle: .module)
            }
        } header: {
            Text("Simulation Settings", bundle: .module)
        }
    }

    private var results: some View {
        Section {
            Picker(selection: $metric) {
                if workload { Metric.efficiency.title.tag(Metric.efficiency) }
                Metric.reviews.title.tag(Metric.reviews)
                Metric.time.title.tag(Metric.time)
                Metric.remembered.title.tag(Metric.remembered)
            } label: {
                Text("Show", bundle: .module)
            }

            let chartPoints = chartPoints
            Chart(chartPoints) { point in
                LineMark(x: .value(workload ? "Retention (%)" : "Study day", point.x), y: .value("Estimate", point.y))
                    .foregroundStyle(by: .value("Simulation", point.run))
            }
            .chartXSelection(value: $selectedX)
            .chartXAxisLabel {
                workload ? Text("Desired retention (%)", bundle: .module) : Text("Study day", bundle: .module)
            }
            .chartYAxisLabel { metric.title }
            .frame(minHeight: 230)

            if let selectedX {
                ForEach(chartPoints.filter { $0.x == selectedX }) { point in
                    LabeledContent {
                        Text(point.y, format: .number.precision(.fractionLength(0...2)))
                    } label: {
                        Text("Simulation \(point.run)", bundle: .module)
                    }
                }
            }
        } header: {
            Text("Estimated Workload", bundle: .module)
        }
    }

    private var chartPoints: [ChartPoint] {
        runs.enumerated().flatMap { index, run in
            let window = !workload && smoothing ? max((run.samples.count + 364) / 365, 1) : 1
            let raw = run.samples.map { $0.value(for: metric) ?? 0 }
            var sum = 0.0
            return run.samples.enumerated().map { i, sample in
                sum += raw[i]
                if i >= window { sum -= raw[i - window] }
                return ChartPoint(run: index + 1, x: sample.x, y: sum / Double(min(i + 1, window)))
            }
        }
    }

    private func simulate() async {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        defer { isRunning = false }
        do {
            if workload {
                let result = try await model.simulateFSRSWorkload(input)
                let samples = result.memorized.keys.sorted().map { retention in
                    let seconds = Double(result.cost[retention, default: 0])
                    let remembered = Double(result.memorized[retention, default: 0])
                    return Sample(
                        x: Int(retention),
                        reviews: Double(result.reviewCount[retention, default: 0]) / Double(input.days),
                        minutes: seconds / (60 * Double(input.days)),
                        remembered: remembered,
                        efficiency: seconds > 0 ? 3600 * (remembered - Double(result.reviewlessEndMemorized)) / seconds : nil
                    )
                }
                runs.append(Run(samples: samples))
            } else {
                let result = try await model.simulateFSRSReviews(input)
                let samples = result.dailyTimeCost.indices.map { day in
                    Sample(
                        x: day + 1,
                        reviews: Double(result.dailyReviewCount[day]) + Double(result.dailyNewCount[day]),
                        minutes: Double(result.dailyTimeCost[day]) / 60,
                        remembered: Double(result.accumulatedKnowledgeAcquisition[day]),
                        efficiency: nil
                    )
                }
                runs.append(Run(samples: samples))
            }
        } catch {
            self.error = error.message
        }
    }

    private enum Metric: Hashable {
        case efficiency, reviews, time, remembered

        var title: Text {
            switch self {
            case .efficiency: Text("Cards remembered per hour", bundle: .module)
            case .reviews: Text("Answers per day", bundle: .module)
            case .time: Text("Minutes per day", bundle: .module)
            case .remembered: Text("Cards remembered", bundle: .module)
            }
        }
    }

    private struct Sample {
        let x: Int
        let reviews: Double
        let minutes: Double
        let remembered: Double
        let efficiency: Double?

        func value(for metric: Metric) -> Double? {
            switch metric {
            case .reviews: reviews
            case .time: minutes
            case .remembered: remembered
            case .efficiency: efficiency
            }
        }
    }

    private struct Run {
        let samples: [Sample]
    }

    private struct ChartPoint: Identifiable {
        let run: Int
        let x: Int
        let y: Double

        var id: String { "\(run)-\(x)" }
    }
}

private struct SimulatorNumberRow<Label: View>: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @ViewBuilder let label: Label

    var body: some View {
        NumberRow(value: Binding { value } set: {
            value = min(max($0, range.lowerBound), range.upperBound)
        }, identifier: "") {
            label
        }
    }
}

struct EasyDaysRows: View {
    @Binding var values: [Float]

    var body: some View {
        let weekdays = Calendar.current.weekdaySymbols
        ForEach(0..<7, id: \.self) { day in
            Picker(selection: Binding {
                values.indices.contains(day) ? values[day] : 1
            } set: { value in
                if values.count < 7 {
                    values.append(contentsOf: repeatElement(1, count: 7 - values.count))
                }
                values[day] = value
            }) {
                Text("Minimum", bundle: .module).tag(Float(0))
                Text("Reduced", bundle: .module).tag(Float(0.5))
                Text("Normal", bundle: .module).tag(Float(1))
            } label: {
                Text(verbatim: weekdays[(day + 1) % 7])
            }
        }
    }
}
