@testable import AnkiCore
import Foundation
import Testing

@Test(
    "An untranslated new message falls back to the English source in localized bundles",
    arguments: [("ja", "メディアはまだ同期中です。"), ("zh-Hans", "媒体仍在同步。")]
)
func localizationFallback(language: String, expected: String) throws {
    let url = try #require(Bundle.module.url(forResource: language, withExtension: "lproj"))
    let bundle = try #require(Bundle(url: url))

    #expect(String(localized: "Media sync is still running.", bundle: bundle) == expected)
    #expect(String(localized: "New message for the next release.", bundle: bundle) == "New message for the next release.")
}
