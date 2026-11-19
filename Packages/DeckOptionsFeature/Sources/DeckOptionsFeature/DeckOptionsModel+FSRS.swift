import AnkiCore
import AnkiProto
import Foundation

extension DeckOptionsModel {
    public enum FSRSOutcome: Equatable, Sendable {
        case optimized(healthCheckPassed: Bool?)
        case alreadyOptimal(healthCheckPassed: Bool?)
        case savedAndOptimized
        case evaluated(logLoss: Float, rmse: Float)
        case insufficientHistory
        case cancelled
        case failed(String)
    }

    enum FSRSActivity {
        case optimize, optimizeAll, evaluate
    }

    /// FSRS is enabled for the whole collection.
    public var fsrsEnabled: Bool {
        get { settings.fsrs }
        set { settings.fsrs = newValue }
    }

    public var fsrsHealthCheck: Bool {
        get { settings.fsrsHealthCheck }
        set { settings.fsrsHealthCheck = newValue }
    }

    public var rescheduleWithFSRS: Bool {
        get { fsrsReschedule }
        set { fsrsReschedule = newValue }
    }

    public var desiredRetention: Float {
        get { selectedConfig.desiredRetention }
        set { selectedConfig.desiredRetention = Self.validDesiredRetention(newValue) }
    }

    public var deckDesiredRetention: Float? {
        get {
            let limits = settings.currentDeck.limits
            return limits.hasDesiredRetention ? limits.desiredRetention : nil
        }
        set {
            if let newValue {
                settings.currentDeck.limits.desiredRetention = Self.validDesiredRetention(newValue)
            } else {
                settings.currentDeck.limits.clearDesiredRetention()
            }
        }
    }

    public var fsrsParameters: [Float] { selectedConfig.fsrsParams6 }

    public var fsrsParameterText: String {
        get { fsrsParameterDrafts[selectedID] ?? formattedFSRSParameters }
        set {
            fsrsParameterDrafts[selectedID] = newValue
            // The display rounds weights to four decimal places. Keep the original values until edited.
            guard newValue != formattedFSRSParameters, let parameters = Self.parseFSRSParameters(newValue) else { return }
            selectedConfig.fsrsParams6 = parameters
        }
    }

    public var fsrsParameterError: String? {
        guard let draft = fsrsParameterDrafts[selectedID], Self.parseFSRSParameters(draft) == nil else { return nil }
        return String(localized: "Enter 17, 19, or 21 comma-separated numbers, or leave the field empty to use defaults.", bundle: .module)
    }

    var hasInvalidFSRSParameters: Bool {
        fsrsParameterDrafts.values.contains { Self.parseFSRSParameters($0) == nil }
    }

    private var formattedFSRSParameters: String {
        fsrsParameters.map { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            .joined(separator: ", ")
    }

    private static func parseFSRSParameters(_ text: String) -> [Float]? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [] }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        let weights = parts.compactMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard [17, 19, 21].contains(weights.count),
              parts.count == weights.count, weights.allSatisfy(\.isFinite)
        else { return nil }
        return weights
    }

    public var fsrsParameterSearch: String {
        get { selectedConfig.paramSearch }
        set { selectedConfig.paramSearch = newValue }
    }

    var defaultFSRSParameterSearch: String {
        let name = (selectedPreset?.name ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "preset:\"\(name)\" -is:suspended"
    }

    public var isOptimizingFSRS: Bool { fsrsActivity != nil }

    var canEvaluateFSRS: Bool { settings.fsrsLegacyEvaluate }

    var daysSinceLastFSRSOptimization: UInt32 { settings.daysSinceLastFsrsOptimize }

    public var canOptimizeFSRS: Bool {
        canSave && fsrsEnabled && hasSavedFSRSPreset
    }

    var hasSavedFSRSPreset: Bool {
        guard let selected = selectedIndex, let saved = entries[selected].saved else { return false }
        return selectedID == loadedSelectedID && saved.name == entries[selected].config.name
    }

    public func optimizeFSRS() async {
        guard canOptimizeFSRS else { return }
        let preset = selectedID
        let params = fsrsParameters
        let request = Anki_Scheduler_ComputeFsrsParamsRequest.with {
            $0.search = effectiveFSRSParameterSearch
            $0.currentParams = params
            $0.ignoreRevlogsBeforeMs = fsrsIgnoreHistoryBeforeMilliseconds
            $0.numOfRelearningSteps = fsrsRelearningStepsInOneDay
            $0.healthCheck = fsrsHealthCheck
        }

        await runFSRS(.computeFsrsParams(request), activity: .optimize) { result in
            let healthCheck = result.hasHealthCheckPassed ? result.healthCheckPassed : nil
            if result.fsrsItems == 0 {
                fsrsOutcome = .insufficientHistory
            } else if result.params == params || result.params.isEmpty {
                fsrsOutcome = .alreadyOptimal(healthCheckPassed: healthCheck)
            } else if let index = entries.firstIndex(where: { $0.id == preset }) {
                entries[index].config.config.fsrsParams6 = result.params
                fsrsParameterDrafts[preset] = nil
                fsrsOutcome = .optimized(healthCheckPassed: healthCheck)
            }
        }
    }

    @discardableResult
    public func saveAndOptimizeAllFSRS() async -> Bool {
        guard canSave, fsrsEnabled, let request = saveRequest(mode: .computeAllParams) else { return false }
        return await runFSRS(
            .updateDeckConfigs(request),
            activity: .optimizeAll,
            collect: { operation async throws(CoreError) in try await self.store.modify(operation) }
        ) { _ in
            await load()
            fsrsOutcome = .savedAndOptimized
        }
    }

    func evaluateFSRS() async {
        guard canOptimizeFSRS, canEvaluateFSRS else { return }
        let request = Anki_Scheduler_EvaluateParamsLegacyRequest.with {
            $0.search = effectiveFSRSParameterSearch
            $0.params = fsrsParameters
            $0.ignoreRevlogsBeforeMs = fsrsIgnoreHistoryBeforeMilliseconds
        }
        await runFSRS(.evaluateParamsLegacy(request), activity: .evaluate) { result in
            fsrsOutcome = .evaluated(logLoss: result.logLoss, rmse: result.rmseBins)
        }
    }

    @discardableResult
    private func runFSRS<Response>(
        _ call: CoreCall<Response>,
        activity: FSRSActivity,
        collect: (LongOperation<Response>) async throws(CoreError) -> Response = { try await $0.result },
        apply: (Response) async -> Void
    ) async -> Bool {
        // The core publishes initial progress before the first training checkpoint.
        let operation = store.core.start(call, pollingInterval: .milliseconds(40))
        fsrsActivity = activity
        cancelFSRSOperation = { operation.cancel() }
        resetFSRSFeedback()
        isCancellingFSRS = false

        let progress = Task {
            for await report in operation.progress {
                if case .computeParams(let value) = report.value { fsrsProgress = value }
            }
        }
        defer {
            progress.cancel()
            cancelFSRSOperation = nil
            fsrsActivity = nil
            isCancellingFSRS = false
        }

        do {
            let result = try await collect(operation)
            // A read-only result can be discarded if Cancel races with completion.
            // A successful batch save has already been committed by the core.
            if activity != .optimizeAll && (isCancellingFSRS || Task.isCancelled) {
                fsrsOutcome = .cancelled
                return false
            }
            await apply(result)
            return true
        } catch {
            fsrsOutcome = error.isInterrupted ? .cancelled : .failed(error.message)
            return false
        }
    }

    public func cancelFSRSOptimization() {
        guard let cancelFSRSOperation else { return }
        isCancellingFSRS = true
        cancelFSRSOperation()
    }

    private var effectiveFSRSParameterSearch: String {
        let search = fsrsParameterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? defaultFSRSParameterSearch : search
    }

    func resetFSRSFeedback() {
        fsrsOutcome = nil
        fsrsProgress = nil
    }

    static func validDesiredRetention(_ value: Float) -> Float {
        guard value.isFinite else { return 0.9 }
        return min(max(value, 0.7), 0.99)
    }

    var fsrsIgnoreHistoryBeforeMilliseconds: Int64 {
        let date = selectedConfig.ignoreRevlogsBeforeDate
        guard !date.isEmpty,
              let value = try? Date(date, strategy: .iso8601.year().month().day())
        else { return 0 }
        return Int64(value.timeIntervalSince1970 * 1000)
    }

    var fsrsRelearningStepsInOneDay: UInt32 {
        var totalMinutes: Float = 0
        let withinDay = selectedConfig.relearnSteps.prefix { step in
            totalMinutes += step
            return totalMinutes < 1440
        }
        return UInt32(withinDay.count)
    }
}
