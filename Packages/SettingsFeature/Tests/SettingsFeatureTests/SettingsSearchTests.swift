import Foundation
@testable import SettingsFeature
import Testing

struct SettingsSearchTests {
    @Test func matchesVisibleDestinationsByTitleAndLocalizedSetting() {
        #expect(SettingsTopic.appearance.matches("  BLACK  THEME ", locale: Locale(identifier: "en")))
        #expect(SettingsTopic.reviewer.matches("二度押し", locale: Locale(identifier: "ja")))
        #expect(SettingsTopic.appearance.matches("深色", locale: Locale(identifier: "zh-Hans")))
        #expect(SettingsTopic.profiles.matches("profíles", locale: Locale(identifier: "en")))
        #expect(SettingsTopic.general.matches("language", locale: Locale(identifier: "en")))
        #expect(SettingsTopic.general.matches("言語", locale: Locale(identifier: "ja")))
        #expect(SettingsTopic.general.matches("语言", locale: Locale(identifier: "zh-Hans")))
        #expect(!SettingsTopic.about.matches("black theme", locale: Locale(identifier: "en")))
    }
}
