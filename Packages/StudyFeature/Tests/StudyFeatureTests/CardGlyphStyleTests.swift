import Foundation
import StudyFeature
import Testing

@Suite("Card Kanji/Hanzi style")
struct CardGlyphStyleTests {
    @Test("Follow App Language is the default")
    func defaultStyle() {
        #expect(CardGlyphStyle.default == .followAppLanguage)
        #expect(CardGlyphStyle(rawValue: "unknown") == nil)
    }

    @Test("A chosen style sets the card page's language whatever the app language")
    func explicitStyles() {
        for appLanguage in ["en", "ja", "zh-Hans"] {
            #expect(CardGlyphStyle.japanese.cardLanguage(appLanguage: appLanguage) == "ja")
            #expect(CardGlyphStyle.simplifiedChinese.cardLanguage(appLanguage: appLanguage) == "zh-Hans")
            #expect(CardGlyphStyle.traditionalChinese.cardLanguage(appLanguage: appLanguage) == "zh-Hant")
        }
    }

    @Test(
        "Follow App Language uses the UI language",
        arguments: [
            ("ja", "ja"),
            ("ja-JP", "ja-JP"),
            ("zh-Hans", "zh-Hans"),
            ("zh-Hant", "zh-Hant"),
            ("zh_Hans", "zh-Hans"),
            ("en", "en"),
        ]
    )
    func followsAppLanguage(appLanguage: String, expected: String) {
        #expect(CardGlyphStyle.followAppLanguage.cardLanguage(appLanguage: appLanguage) == expected)
    }

    @Test("Follow App Language with no known app language leaves the page language unset")
    func noAppLanguage() {
        #expect(CardGlyphStyle.followAppLanguage.cardLanguage(appLanguage: nil) == "")
    }
}
