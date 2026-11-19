import AnkiCore
import AnkiProto
import Foundation

extension DeckOptionsModel {
    public enum FSRSOutcome: Equatable, Sendable {
        case optimized(healthCheckPassed: Bool?)
        case alreadyOptimal(healthCheckPassed: Bool?)
        case insufficientHistory
        case cancelled
        case failed(String)
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

    public var isOptimizingFSRS: Bool { fsrsOptimization != nil }

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
        let search = fsrsParameterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Anki_Scheduler_ComputeFsrsParamsRequest.with {
            $0.search = search.isEmpty ? defaultFSRSParameterSearch : search
            $0.currentParams = params
            $0.ignoreRevlogsBeforeMs = fsrsIgnoreHistoryBeforeMilliseconds
            $0.numOfRelearningSteps = fsrsRelearningStepsInOneDay
            $0.healthCheck = fsrsHealthCheck
        }

        // The core publishes its initial progress immediately. Poll before the
        // first training checkpoint so even short runs can show progress.
        let operation = store.core.start(.computeFsrsParams(request), pollingInterval: .milliseconds(40))
        fsrsOptimization = operation
        fsrsProgress = nil
        fsrsOutcome = nil
        isCancellingFSRS = false
        let progress = Task {
            for await report in operation.progress {
                if case .computeParams(let value) = report.value { fsrsProgress = value }
            }
        }
        defer {
            progress.cancel()
            fsrsOptimization = nil
            isCancellingFSRS = false
        }
        do {
            let result = try await operation.result
            if isCancellingFSRS || Task.isCancelled {
                fsrsOutcome = .cancelled
            } else if result.fsrsItems == 0 {
                fsrsOutcome = .insufficientHistory
            } else if result.params == params || result.params.isEmpty {
                fsrsOutcome = .alreadyOptimal(healthCheckPassed: result.hasHealthCheckPassed ? result.healthCheckPassed : nil)
            } else if let index = entries.firstIndex(where: { $0.id == preset }) {
                entries[index].config.config.fsrsParams6 = result.params
                fsrsParameterDrafts[preset] = nil
                fsrsOutcome = .optimized(healthCheckPassed: result.hasHealthCheckPassed ? result.healthCheckPassed : nil)
            }
        } catch {
            fsrsOutcome = error.isInterrupted || isCancellingFSRS ? .cancelled : .failed(error.message)
        }
    }

    public func cancelFSRSOptimization() {
        guard let fsrsOptimization else { return }
        isCancellingFSRS = true
        fsrsOptimization.cancel()
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
