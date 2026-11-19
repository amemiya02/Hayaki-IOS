import AnkiCore
import AnkiProto
import Foundation
import SwiftUI

extension DeckOptionsModel {
    struct FSRSWorkloadEstimateRequest: Equatable, Hashable, Sendable {
        let search: String
        let parameters: [Float]
        let previous: UInt32
        let target: UInt32

        func ratio(in costs: [UInt32: Float]) -> Float? {
            guard let base = costs[previous], base.isFinite, base > 0,
                  let current = costs[target], current.isFinite, current >= 0 else { return nil }
            let factor = current / base
            return factor.isFinite ? factor : nil
        }
    }

    struct FSRSCutoffEstimateRequest: Equatable, Hashable, Sendable {
        let search: String
        let date: String
    }

    struct FSRSCutoffEstimate: Equatable, Sendable {
        let included: UInt64
        let total: UInt64
    }

    struct FSRSWorkloadCache {
        let search: String
        let parameters: [Float]
        let costs: [UInt32: Float]
    }

    var fsrsWorkloadEstimateRequest: FSRSWorkloadEstimateRequest? {
        guard fsrsEnabled, state == .loaded, !isOptimizingFSRS, fsrsParameterError == nil,
              let previousRetention = savedEffectiveFSRSRetention else { return nil }
        let previous = Self.roundedRetention(previousRetention)
        let target = Self.roundedRetention(deckDesiredRetention ?? desiredRetention)
        guard target != previous else { return nil }
        let parameters = [selectedConfig.fsrsParams6, selectedConfig.fsrsParams5, selectedConfig.fsrsParams4]
            .first { !$0.isEmpty } ?? []
        return FSRSWorkloadEstimateRequest(search: savedPresetSearch, parameters: parameters, previous: previous, target: target)
    }

    var fsrsCutoffEstimateRequest: FSRSCutoffEstimateRequest? {
        let date = selectedConfig.ignoreRevlogsBeforeDate
        guard state == .loaded, !isOptimizingFSRS, !date.isEmpty, date != "1970-01-01" else { return nil }
        let search = fsrsParameterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return FSRSCutoffEstimateRequest(search: search.isEmpty ? savedPresetSearch : search, date: date)
    }

    func loadFSRSWorkloadEstimate(_ request: FSRSWorkloadEstimateRequest) async -> Float? {
        if let fsrsWorkloadCache, fsrsWorkloadCache.search == request.search, fsrsWorkloadCache.parameters == request.parameters {
            return request.ratio(in: fsrsWorkloadCache.costs)
        }
        guard let costs = try? await store.core.getRetentionWorkload(.with {
            $0.search = request.search
            $0.w = request.parameters
        }).costs else { return nil }
        if !Task.isCancelled {
            fsrsWorkloadCache = .init(search: request.search, parameters: request.parameters, costs: costs)
        }
        return request.ratio(in: costs)
    }

    func loadFSRSCutoffEstimate(_ request: FSRSCutoffEstimateRequest) async -> FSRSCutoffEstimate? {
        guard let counts = try? await store.core.getIgnoredBeforeCount(.with {
            $0.search = request.search
            $0.ignoreRevlogsBeforeDate = request.date
        }) else { return nil }
        return FSRSCutoffEstimate(included: counts.included, total: counts.total)
    }

    private var savedPresetSearch: String {
        guard let selectedIndex, let name = entries[selectedIndex].saved?.name else { return defaultFSRSParameterSearch }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "preset:\"\(escaped)\" -is:suspended"
    }

    private static func roundedRetention(_ value: Float) -> UInt32 {
        UInt32((validDesiredRetention(value) * 100).rounded())
    }
}

struct FSRSWorkloadEstimateLabel: View {
    let model: DeckOptionsModel
    @State private var factor: Float?

    var body: some View {
        let request = model.fsrsWorkloadEstimateRequest
        Group {
            if let request, let factor {
                Text(
                    "\(factor.formatted(.number.precision(.fractionLength(2))))× the workload at \(request.previous.formatted())% retention",
                    bundle: .module
                )
            }
        }
        .task(id: request) {
            factor = nil
            guard let request else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let value = await model.loadFSRSWorkloadEstimate(request)
            if !Task.isCancelled { factor = value }
        }
    }
}

struct FSRSCutoffEstimateLabel: View {
    let model: DeckOptionsModel
    @State private var counts: DeckOptionsModel.FSRSCutoffEstimate?

    var body: some View {
        let request = model.fsrsCutoffEstimateRequest
        Group {
            if let counts {
                Text("\(counts.included.formatted()) of \(counts.total.formatted()) cards are included in optimization.", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(counts.included < counts.total ? Color.orange : Color.secondary)
            }
        }
        .task(id: request) {
            counts = nil
            guard let request else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let estimate = await model.loadFSRSCutoffEstimate(request)
            if !Task.isCancelled { counts = estimate }
        }
    }
}
