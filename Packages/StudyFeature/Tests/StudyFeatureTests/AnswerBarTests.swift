@testable import StudyFeature
import SwiftUI
import Testing

@Suite("Answer bar")
struct AnswerBarTests {
    @Test("Again gives a firmer tap than Good and Easy")
    func ratingHaptics() {
        #expect(Rating.again.feedback == .impact(weight: .heavy))
        #expect(Rating.hard.feedback == .impact(weight: .medium))
        #expect(Rating.good.feedback == .impact(weight: .light))
        #expect(Rating.easy.feedback == .impact(weight: .light))
    }
}
