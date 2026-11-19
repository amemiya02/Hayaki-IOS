import AnkiProto
import Foundation

public typealias NewCardInsertionOrder = Anki_DeckConfig_DeckConfig.Config.NewCardInsertOrder
public typealias LeechAction = Anki_DeckConfig_DeckConfig.Config.LeechAction
public typealias AutoAdvanceQuestionAction = Anki_DeckConfig_DeckConfig.Config.QuestionAction
public typealias AutoAdvanceAnswerAction = Anki_DeckConfig_DeckConfig.Config.AnswerAction

extension DeckOptionsModel {
    // MARK: New cards and lapses

    public var newCardInsertionOrder: NewCardInsertionOrder {
        get { selectedConfig.newCardInsertOrder }
        set { selectedConfig.newCardInsertOrder = newValue }
    }

    public var graduatingInterval: Int {
        get { Int(selectedConfig.graduatingIntervalGood) }
        set { selectedConfig.graduatingIntervalGood = bounded(newValue, to: 1...9999) }
    }

    public var easyGraduatingInterval: Int {
        get { Int(selectedConfig.graduatingIntervalEasy) }
        set { selectedConfig.graduatingIntervalEasy = bounded(newValue, to: 1...9999) }
    }

    public var minimumLapseInterval: Int {
        get { Int(selectedConfig.minimumLapseInterval) }
        set { selectedConfig.minimumLapseInterval = bounded(newValue, to: 1...9999) }
    }

    public var leechThreshold: Int {
        get { Int(selectedConfig.leechThreshold) }
        set { selectedConfig.leechThreshold = bounded(newValue, to: 1...9999) }
    }

    public var leechAction: LeechAction {
        get { selectedConfig.leechAction }
        set { selectedConfig.leechAction = newValue }
    }

    // MARK: Timer and audio

    public var maximumAnswerSeconds: Int {
        get { Int(selectedConfig.capAnswerTimeToSecs) }
        set { selectedConfig.capAnswerTimeToSecs = bounded(newValue, to: 1...7200) }
    }

    public var showAnswerTimer: Bool {
        get { selectedConfig.showTimer }
        set { selectedConfig.showTimer = newValue }
    }

    public var stopTimerOnAnswer: Bool {
        get { selectedConfig.stopTimerOnAnswer }
        set { selectedConfig.stopTimerOnAnswer = newValue }
    }

    public var automaticallyPlayAudio: Bool {
        get { !selectedConfig.disableAutoplay }
        set { selectedConfig.disableAutoplay = !newValue }
    }

    public var skipQuestionAudioWhenReplayingAnswer: Bool {
        get { selectedConfig.skipQuestionWhenReplayingAnswer }
        set { selectedConfig.skipQuestionWhenReplayingAnswer = newValue }
    }

    // MARK: Auto advance

    public var secondsToShowQuestion: Float {
        get { selectedConfig.secondsToShowQuestion }
        set { selectedConfig.secondsToShowQuestion = newValue.clamped(to: 0...9999) }
    }

    public var secondsToShowAnswer: Float {
        get { selectedConfig.secondsToShowAnswer }
        set { selectedConfig.secondsToShowAnswer = newValue.clamped(to: 0...9999) }
    }

    public var waitForAudio: Bool {
        get { selectedConfig.waitForAudio }
        set { selectedConfig.waitForAudio = newValue }
    }

    public var questionAction: AutoAdvanceQuestionAction {
        get { selectedConfig.questionAction }
        set { selectedConfig.questionAction = newValue }
    }

    public var answerAction: AutoAdvanceAnswerAction {
        get { selectedConfig.answerAction }
        set { selectedConfig.answerAction = newValue }
    }

    // MARK: Easy days and advanced scheduling

    public var easyDaysPercentages: [Float] {
        get { selectedConfig.easyDaysPercentages }
        set {
            guard newValue.count == 7, newValue.allSatisfy({ (0...1).contains($0) }) else { return }
            selectedConfig.easyDaysPercentages = newValue
        }
    }

    public var maximumReviewInterval: Int {
        get { Int(selectedConfig.maximumReviewInterval) }
        set { selectedConfig.maximumReviewInterval = bounded(newValue, to: 1...36_500) }
    }

    public var initialEase: Float {
        get { selectedConfig.initialEase }
        set { selectedConfig.initialEase = newValue.clamped(to: 1.31...5) }
    }

    public var easyMultiplier: Float {
        get { selectedConfig.easyMultiplier }
        set { selectedConfig.easyMultiplier = newValue.clamped(to: 1...5) }
    }

    public var intervalMultiplier: Float {
        get { selectedConfig.intervalMultiplier }
        set { selectedConfig.intervalMultiplier = newValue.clamped(to: 0.5...2) }
    }

    public var hardMultiplier: Float {
        get { selectedConfig.hardMultiplier }
        set { selectedConfig.hardMultiplier = newValue.clamped(to: 0.5...1.3) }
    }

    public var lapseMultiplier: Float {
        get { selectedConfig.lapseMultiplier }
        set { selectedConfig.lapseMultiplier = newValue.clamped(to: 0...1) }
    }

    public var historicalRetention: Float {
        get { selectedConfig.historicalRetention }
        set { selectedConfig.historicalRetention = newValue.clamped(to: 0.5...1) }
    }

    /// The calendar date in the learner's time zone. The core stores only the date.
    public var ignoreFSRSHistoryBefore: Date? {
        get { try? dateOnlyFormat.parse(selectedConfig.ignoreRevlogsBeforeDate) }
        set { selectedConfig.ignoreRevlogsBeforeDate = newValue.map { dateOnlyFormat.format($0) } ?? "" }
    }

    public var customScheduling: String {
        get { settings.cardStateCustomizer }
        set { settings.cardStateCustomizer = newValue }
    }

    var reviewSortChoices: [ReviewSortOrder] {
        let supported = ReviewSortOrder.choices(fsrs: fsrsEnabled)
        // Keep an imported selection available until the learner explicitly changes it.
        return supported.contains(reviewSortOrder) ? supported : supported + [reviewSortOrder]
    }

    private var dateOnlyFormat: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
    }

    private func bounded(_ value: Int, to range: ClosedRange<Int>) -> UInt32 {
        UInt32(min(max(value, range.lowerBound), range.upperBound))
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        guard isFinite else { return range.lowerBound }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
