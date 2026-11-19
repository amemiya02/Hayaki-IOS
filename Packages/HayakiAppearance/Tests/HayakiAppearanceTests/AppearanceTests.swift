import Foundation
import HayakiAppearance
import SwiftUI
import Testing

@MainActor
struct AppearanceTests {
    @Test func systemFollowsEachSystemAppearanceAndKeepsItsOwnNightChoice() {
        let name = "HayakiAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppearanceSettings(store: defaults)
        #expect(settings.mode == .system)
        #expect(settings.resolved(for: .light) == .light)
        #expect(settings.resolved(for: .dark) == .dark)
        #expect(settings.preferredColorScheme == nil)

        settings.systemNightMode = .black
        settings.mode = .light
        #expect(AppearanceSettings(store: defaults).resolved(for: .dark) == .light)
        #expect(settings.systemNightMode == .black)
        settings.mode = .dark
        #expect(AppearanceSettings(store: defaults).resolved(for: .light) == .dark)
        #expect(settings.systemNightMode == .dark)
        settings.mode = .black
        #expect(AppearanceSettings(store: defaults).resolved(for: .light) == .black)

        settings.mode = .system
        let reopened = AppearanceSettings(store: defaults)
        #expect(reopened.resolved(for: .light) == .light)
        #expect(reopened.resolved(for: .dark) == .black)
        #expect(reopened.preferredColorScheme == nil)
    }
}

extension AppearanceTests {
    @Test func semanticLabelsHaveReadableContrastAcrossAllThreePalettes() {
        #expect(HayakiTheme.black.backgroundRGB == 0)
        #expect(HayakiTheme.dark.backgroundRGB != 0)
        for theme in [HayakiTheme.light, .dark, .black] {
            let foregrounds = SemanticColor.allCases.map { theme.rgb(for: $0) }
            #expect(Set(foregrounds).count == 4)
            for foreground in foregrounds {
                #expect(contrast(foreground, theme.backgroundRGB) >= 4.5)
                #expect(contrast(foreground, theme.surfaceRGB) >= 4.5)
            }
        }
    }

    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift in
            let value = Double((rgb >> shift) & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
