import Foundation

/// What a reminder says.
enum ReminderText {
    static var title: String {
        String(localized: "Time to Study", bundle: .module, comment: "Title of the daily study reminder notification.")
    }

    /// The reminder's text for a day, or nil when there is nothing to study
    /// that day, so no reminder is sent.
    static func body(for counts: StudyCounts) -> String? {
        var sentences: [String] = []
        if counts.due > 0 {
            sentences.append(String(
                localized: "\(counts.due) cards are due.",
                bundle: .module,
                comment: "Daily reminder text: how many cards (reviews and learning cards) are due. Plural variations by count."
            ))
        }
        if counts.new > 0 {
            sentences.append(String(
                localized: "\(counts.new) new cards are ready to learn.",
                bundle: .module,
                comment: "Daily reminder text: how many new cards can be learned that day. Plural variations by count."
            ))
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
