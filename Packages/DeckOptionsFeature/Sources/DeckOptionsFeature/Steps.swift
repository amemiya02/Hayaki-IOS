import Foundation

/// Learning and relearning steps as the learner types them: delays separated
/// by spaces, each a number with a unit, such as "1m 10m 1d". The core keeps
/// them as minutes.
enum Steps {
    /// Reads typed steps as minutes. Returns the first part that is not a
    /// step greater than zero, if any. No steps at all is valid.
    static func parse(_ text: String) -> Result<[Float], InvalidStep> {
        var minutes: [Float] = []
        for part in text.split(whereSeparator: \.isWhitespace) {
            guard let value = parseStep(part) else {
                return .failure(InvalidStep(text: String(part)))
            }
            minutes.append(value)
        }
        return .success(minutes)
    }

    /// Writes steps the way Anki shows them, each in the largest unit that
    /// divides it exactly: "30s 10m 1h 1d".
    static func format(_ minutes: [Float]) -> String {
        minutes.map(formatStep).joined(separator: " ")
    }

    struct InvalidStep: Error, Equatable {
        let text: String
    }

    private static let unitMinutes: [Character: Float] = ["s": 1 / 60, "m": 1, "h": 60, "d": 1440]

    private static func parseStep(_ part: Substring) -> Float? {
        var number = part.lowercased()
        var unit: Float = 1
        if let last = number.last, let minutes = unitMinutes[last] {
            unit = minutes
            number.removeLast()
        }
        // Only plain decimal numbers: no signs, exponents, "inf" or "nan".
        guard !number.isEmpty,
              number.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let value = Float(number), value > 0
        else { return nil }
        return value * unit
    }

    private static func formatStep(_ minutes: Float) -> String {
        let seconds = (Double(minutes) * 60).rounded()
        if seconds < 60 || seconds.truncatingRemainder(dividingBy: 60) != 0 {
            return "\(number(Double(minutes) * 60))s"
        }
        let wholeMinutes = seconds / 60
        if wholeMinutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(number(wholeMinutes / 1440))d" }
        if wholeMinutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(number(wholeMinutes / 60))h" }
        return "\(number(wholeMinutes))m"
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

/// Which steps field of which preset a draft belongs to.
struct StepsDraftKey: Hashable {
    enum Kind { case learning, relearning }
    let preset: PresetID
    let kind: Kind
}

extension DeckOptionsModel {
    /// The selected preset's learning steps, as typed: "1m 10m".
    public var learningSteps: String {
        get { stepsText(.learning) }
        set { setStepsText(newValue, .learning) }
    }

    /// The selected preset's relearning steps, for cards forgotten in review.
    public var relearningSteps: String {
        get { stepsText(.relearning) }
        set { setStepsText(newValue, .relearning) }
    }

    /// Why the learning steps as typed cannot be saved; nil when they can.
    public var learningStepsError: String? { stepsError(.learning) }

    /// Why the relearning steps as typed cannot be saved; nil when they can.
    public var relearningStepsError: String? { stepsError(.relearning) }

    /// Whether some preset has steps typed that are not valid.
    var hasInvalidSteps: Bool {
        stepsDrafts.values.contains { text in
            if case .failure = Steps.parse(text) { true } else { false }
        }
    }

    private func steps(_ kind: StepsDraftKey.Kind) -> [Float] {
        switch kind {
        case .learning: selectedConfig.learnSteps
        case .relearning: selectedConfig.relearnSteps
        }
    }

    private func stepsText(_ kind: StepsDraftKey.Kind) -> String {
        stepsDrafts[StepsDraftKey(preset: selectedID, kind: kind)] ?? Steps.format(steps(kind))
    }

    private func setStepsText(_ text: String, _ kind: StepsDraftKey.Kind) {
        let key = StepsDraftKey(preset: selectedID, kind: kind)
        // Unchanged text leaves the stored steps exactly as they were.
        if text == Steps.format(steps(kind)) {
            stepsDrafts[key] = nil
            return
        }
        stepsDrafts[key] = text
        guard case .success(let minutes) = Steps.parse(text), minutes != steps(kind) else { return }
        switch kind {
        case .learning: selectedConfig.learnSteps = minutes
        case .relearning: selectedConfig.relearnSteps = minutes
        }
    }

    private func stepsError(_ kind: StepsDraftKey.Kind) -> String? {
        guard let text = stepsDrafts[StepsDraftKey(preset: selectedID, kind: kind)],
              case .failure(let invalid) = Steps.parse(text)
        else { return nil }
        return String(
            localized: "“\(invalid.text)” is not a step. Enter delays such as 1m 10m 1d, using s, m, h or d.",
            bundle: .module,
            comment: "Shown under a learning or relearning steps field when part of what was typed is not a delay. The placeholder is the part that is wrong."
        )
    }
}
