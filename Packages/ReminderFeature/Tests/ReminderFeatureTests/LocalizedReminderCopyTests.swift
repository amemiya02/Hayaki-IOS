import Foundation
@testable import ReminderFeature
import Testing

@Test(
    "The packaged reminder has localized notification copy and a formatted count",
    arguments: [
        ("ja", "学習の時間です", "復習待ちのカードが1枚あります。", "新しく学習できるカードが2枚あります。"),
        ("zh-Hans", "该学习了", "有 1 张卡片待复习。", "有 2 张新卡片可以学习。"),
    ]
)
func localizedReminderCopy(language: String, title: String, due: String, new: String) throws {
    let url = try #require(Bundle.module.url(forResource: language, withExtension: "lproj"))
    let bundle = try #require(Bundle(url: url))
    let locale = Locale(identifier: language)

    #expect(String(localized: "Time to Study", bundle: bundle, locale: locale) == title)
    let dueCount = 1
    let newCount = 2
    #expect(String(localized: "\(dueCount) cards are due.", bundle: bundle, locale: locale) == due)
    #expect(String(localized: "\(newCount) new cards are ready to learn.", bundle: bundle, locale: locale) == new)
}
