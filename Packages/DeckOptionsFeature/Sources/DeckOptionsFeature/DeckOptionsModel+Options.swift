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

    /// Whether this deck has its own daily limits, set in Anki on another
    /// device, which apply instead of the preset's. The screen does not edit
    /// them but keeps them.
    public var deckHasOwnLimits: Bool {
        let limits = settings.currentDeck.limits
        return limits.hasNew || limits.hasReview
            || (limits.newTodayActive && limits.hasNewToday)
            || (limits.reviewTodayActive && limits.hasReviewToday)
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
