import Foundation

/// What a reminder says.
enum ReminderText {
    static var title: String {
        String(localized: "Time to Study", bundle: .module, comment: "Title of the daily study reminder notification.")
    }

    /// The language the reminder is written in: the one its strings resolve
    /// to. Plural forms follow it rather than the device's region, so a
    /// device in a language Hayaki has no strings for, which falls back to
    /// English, still gets "1 card is due." and not "1 cards are due.".
    private static var language: Locale {
        Locale(identifier: Bundle.module.preferredLocalizations.first ?? "en")
    }

    /// The reminder's text for a day, or nil when there is nothing to study
    /// that day, so no reminder is sent.
    static func body(for counts: StudyCounts) -> String? {
        var sentences: [String] = []
        if counts.due > 0 {
            sentences.append(String(
                localized: "\(counts.due) cards are due.",
                bundle: .module,
                locale: language,
                comment: "Daily reminder text: how many cards (reviews and learning cards) are due. Plural variations by count."
            ))
        }
        if counts.new > 0 {
            sentences.append(String(
                localized: "\(counts.new) new cards are ready to learn.",
                bundle: .module,
                locale: language,
                comment: "Daily reminder text: how many new cards can be learned that day. Plural variations by count."
            ))
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
