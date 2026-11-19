import AnkiProto

public typealias NewCardGatherOrder = Anki_DeckConfig_DeckConfig.Config.NewCardGatherPriority
public typealias NewCardSortOrder = Anki_DeckConfig_DeckConfig.Config.NewCardSortOrder
public typealias ReviewMix = Anki_DeckConfig_DeckConfig.Config.ReviewMix
public typealias ReviewSortOrder = Anki_DeckConfig_DeckConfig.Config.ReviewCardOrder

/// The options of the selected preset that the screen presents. Each reads
/// and writes one field of the core's own `Config` message.
extension DeckOptionsModel {
    /// The largest daily limit Anki accepts; the core replaces larger ones
    /// with its default when it reads them.
    static let dailyLimitRange = 0...9999

    // MARK: Daily limits

    /// How many new cards are introduced per day.
    public var newCardsPerDay: Int {
        get { Int(selectedConfig.newPerDay) }
        set { selectedConfig.newPerDay = UInt32(newValue.clamped(to: Self.dailyLimitRange)) }
    }

    /// The most review cards shown per day.
    public var reviewsPerDay: Int {
        get { Int(selectedConfig.reviewsPerDay) }
        set { selectedConfig.reviewsPerDay = UInt32(newValue.clamped(to: Self.dailyLimitRange)) }
    }

    public var deckNewCardsLimit: Int? {
        get {
            let limits = settings.currentDeck.limits
            return limits.hasNew ? Int(limits.new) : nil
        }
        set {
            if let limit = Self.dailyLimit(newValue) {
                settings.currentDeck.limits.new = limit
            } else {
                settings.currentDeck.limits.clearNew()
            }
        }
    }

    public var deckReviewsLimit: Int? {
        get {
            let limits = settings.currentDeck.limits
            return limits.hasReview ? Int(limits.review) : nil
        }
        set {
            if let limit = Self.dailyLimit(newValue) {
                settings.currentDeck.limits.review = limit
            } else {
                settings.currentDeck.limits.clearReview()
            }
        }
    }

    public var todayNewCardsLimit: Int? {
        get {
            let limits = settings.currentDeck.limits
            return limits.newTodayActive && limits.hasNewToday ? Int(limits.newToday) : nil
        }
        set {
            if let limit = Self.dailyLimit(newValue) {
                settings.currentDeck.limits.newToday = limit
            }
            settings.currentDeck.limits.newTodayActive = newValue != nil
        }
    }

    public var todayReviewsLimit: Int? {
        get {
            let limits = settings.currentDeck.limits
            return limits.reviewTodayActive && limits.hasReviewToday ? Int(limits.reviewToday) : nil
        }
        set {
            if let limit = Self.dailyLimit(newValue) {
                settings.currentDeck.limits.reviewToday = limit
            }
            settings.currentDeck.limits.reviewTodayActive = newValue != nil
        }
    }

    var suggestedTodayNewCardsLimit: Int {
        let limits = settings.currentDeck.limits
        return limits.hasNewToday ? Int(limits.newToday) : (deckNewCardsLimit ?? newCardsPerDay)
    }

    var suggestedTodayReviewsLimit: Int {
        let limits = settings.currentDeck.limits
        return limits.hasReviewToday ? Int(limits.reviewToday) : (deckReviewsLimit ?? reviewsPerDay)
    }

    public var newCardsIgnoreReviewLimit: Bool {
        get { settings.newCardsIgnoreReviewLimit }
        set { settings.newCardsIgnoreReviewLimit = newValue }
    }

    public var applyAllParentLimits: Bool {
        get { settings.applyAllParentLimits }
        set { settings.applyAllParentLimits = newValue }
    }

    private static func dailyLimit(_ value: Int?) -> UInt32? {
        value.map { UInt32($0.clamped(to: Self.dailyLimitRange)) }
    }

    /// Whether this deck currently overrides daily limits from its preset.
    public var deckHasOwnLimits: Bool {
        deckNewCardsLimit != nil || deckReviewsLimit != nil || todayNewCardsLimit != nil || todayReviewsLimit != nil
    }

    // MARK: Display order

    /// Which new cards are gathered first, across the deck and its subdecks.
    public var newCardGatherOrder: NewCardGatherOrder {
        get { selectedConfig.newCardGatherPriority }
        set { selectedConfig.newCardGatherPriority = newValue }
    }

    /// How the gathered new cards are sorted.
    public var newCardSortOrder: NewCardSortOrder {
        get { selectedConfig.newCardSortOrder }
        set { selectedConfig.newCardSortOrder = newValue }
    }

    /// Whether new cards are shown mixed with reviews, before or after them.
    public var newReviewMix: ReviewMix {
        get { selectedConfig.newMix }
        set { selectedConfig.newMix = newValue }
    }

    /// Whether learning cards due on a later day are mixed with reviews,
    /// shown before or after them.
    public var interdayLearningReviewMix: ReviewMix {
        get { selectedConfig.interdayLearningMix }
        set { selectedConfig.interdayLearningMix = newValue }
    }

    /// How review cards are sorted.
    public var reviewSortOrder: ReviewSortOrder {
        get { selectedConfig.reviewOrder }
        set { selectedConfig.reviewOrder = newValue }
    }

    // MARK: Burying

    /// Whether other new cards of the same note wait until the next day.
    public var buryNewSiblings: Bool {
        get { selectedConfig.buryNew }
        set { selectedConfig.buryNew = newValue }
    }

    /// Whether other review cards of the same note wait until the next day.
    public var buryReviewSiblings: Bool {
        get { selectedConfig.buryReviews }
        set { selectedConfig.buryReviews = newValue }
    }

    /// Whether other learning cards of the same note, due on a later day,
    /// wait until the next day.
    public var buryInterdayLearningSiblings: Bool {
        get { selectedConfig.buryInterdayLearning }
        set { selectedConfig.buryInterdayLearning = newValue }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
