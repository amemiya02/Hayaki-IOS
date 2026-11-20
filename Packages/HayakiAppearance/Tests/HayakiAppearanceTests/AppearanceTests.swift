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
    @Test func theDefaultHayakiThemeUsesTheIconTealAsItsAccent() {
        #expect(HayakiTheme.light.accentRGB == 0x2C776E)
        #expect(HayakiTheme.dark.accentRGB == 0x7ED6CA)
        // Black mode reuses the dark accent.
        #expect(HayakiTheme.black.accentRGB == 0x7ED6CA)
    }

    @Test func theTintIsFaintInLightAndDarkAndAbsentInBlack() {
        #expect(HayakiTheme.light.tintOpacity == 0.04)
        #expect(HayakiTheme.dark.tintOpacity == 0.06)
        #expect(HayakiTheme.black.tintOpacity == 0)
    }

    @Test func theAccentIsReadableOnEveryTintedSystemBackground() {
        // iOS system backgrounds: systemBackground and systemGroupedBackground,
        // then secondarySystemGroupedBackground for surfaces.
        let backgrounds: [HayakiTheme: [UInt32]] = [
            .light: [0xFFFFFF, 0xF2F2F7],
            .dark: [0x000000, 0x1C1C1E],
            .black: [0x000000, 0x1C1C1E],
        ]
        for (theme, systemBackgrounds) in backgrounds {
            for background in systemBackgrounds {
                let tinted = blend(theme.accentRGB, over: background, opacity: theme.tintOpacity)
                #expect(contrast(theme.accentRGB, tinted) >= 4.5)
            }
        }
    }

    @Test func theCardCanvasMatchesTheTintedStudyBackground() {
        #expect(HayakiTheme.light.canvasRGB == 0xF7FAF9)
        #expect(HayakiTheme.dark.canvasRGB == 0x080D0C)
        #expect(HayakiTheme.black.canvasRGB == 0x000000)
    }

    @Test func ratingAndCountColorsAreFixedSystemColors() {
        #expect(SemanticColor.again.color == .red)
        #expect(SemanticColor.hard.color == .orange)
        #expect(SemanticColor.good.color == .green)
        #expect(SemanticColor.easy.color == .blue)
        #expect(SemanticColor.new.color == .blue)
        #expect(SemanticColor.learning.color == .red)
        #expect(SemanticColor.due.color == .green)
    }

    private func blend(_ foreground: UInt32, over background: UInt32, opacity: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { result, shift in
            let top = Double((foreground >> shift) & 255)
            let bottom = Double((background >> shift) & 255)
            return result | UInt32((top * opacity + bottom * (1 - opacity)).rounded()) << shift
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
