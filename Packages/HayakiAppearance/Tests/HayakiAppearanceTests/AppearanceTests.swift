import Foundation
import HayakiAppearance
import SwiftUI
import Testing

@MainActor
struct AppearanceTests {
    @Test func systemFollowsEachSystemAppearanceAndKeepsItsOwnNightChoice() {
        withDefaults { defaults in
            let settings = AppearanceSettings(store: defaults)
            #expect(settings.mode == .system)
            #expect(settings.resolved(for: .light).appearance == .light)
            #expect(settings.resolved(for: .dark).appearance == .dark)
            #expect(settings.preferredColorScheme == nil)

            settings.systemNightMode = .black
            settings.mode = .light
            #expect(AppearanceSettings(store: defaults).resolved(for: .dark).appearance == .light)
            #expect(settings.systemNightMode == .black)
            settings.mode = .dark
            #expect(AppearanceSettings(store: defaults).resolved(for: .light).appearance == .dark)
            #expect(settings.systemNightMode == .dark)
            settings.mode = .black
            #expect(AppearanceSettings(store: defaults).resolved(for: .light).appearance == .black)

            settings.mode = .system
            let reopened = AppearanceSettings(store: defaults)
            #expect(reopened.resolved(for: .light).appearance == .light)
            #expect(reopened.resolved(for: .dark).appearance == .black)
            #expect(reopened.preferredColorScheme == nil)
        }
    }

    @Test func hayakiIsTheDefaultThemeAndEveryThemeIsKeptAcrossLaunches() {
        withDefaults { defaults in
            #expect(AppearanceSettings(store: defaults).theme == .hayaki)
            for theme in Theme.allCases {
                AppearanceSettings(store: defaults).theme = theme
                #expect(AppearanceSettings(store: defaults).theme == theme)
                #expect(AppearanceSettings(store: defaults).resolved(for: .light).theme == theme)
            }
        }
    }

    @Test func theTenThemesFromTheSpecAreOfferedInOrder() {
        #expect(Theme.allCases == [
            .hayaki, .sakura, .matcha, .ocean, .indigo, .wisteria, .amber, .sumi, .paper, .midnight,
        ])
    }

    @Test func anExistingAppearanceChoiceIsKeptAndGetsTheDefaultTheme() {
        withDefaults { defaults in
            // What earlier versions stored: the mode, then the night choice.
            defaults.set("black/black", forKey: "hayaki.appearance")
            let settings = AppearanceSettings(store: defaults)
            #expect(settings.mode == .black)
            #expect(settings.systemNightMode == .black)
            #expect(settings.theme == .hayaki)
            #expect(settings.resolved(for: .light) == HayakiTheme(.hayaki, .black))
        }
    }

    @Test func anUnknownStoredThemeFallsBackToHayaki() {
        withDefaults { defaults in
            defaults.set("shu", forKey: "hayaki.theme")
            #expect(AppearanceSettings(store: defaults).theme == .hayaki)
        }
    }

    @Test func themeAndAppearanceCombineFreely() {
        withDefaults { defaults in
            let settings = AppearanceSettings(store: defaults)
            settings.theme = .sakura
            settings.mode = .black
            #expect(settings.mode == .black)
            #expect(settings.theme == .sakura)
            settings.mode = .light
            #expect(settings.theme == .sakura)
            #expect(settings.resolved(for: .dark) == HayakiTheme(.sakura, .light))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "HayakiAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}

extension AppearanceTests {
    @Test func theDefaultHayakiThemeUsesTheIconTealAsItsAccent() {
        #expect(HayakiTheme(.hayaki, .light).accentRGB == 0x2C776E)
        #expect(HayakiTheme(.hayaki, .dark).accentRGB == 0x7ED6CA)
        // Black mode reuses the dark accent.
        #expect(HayakiTheme(.hayaki, .black).accentRGB == 0x7ED6CA)
    }

    @Test func eachThemeHasItsOwnAccentInLightAndDark() {
        #expect(HayakiTheme(.sumi, .light).accentRGB == 0x4A4A4F)
        #expect(HayakiTheme(.sumi, .black).accentRGB == 0xC7C7CC)
        #expect(HayakiTheme(.ocean, .dark).accentRGB == 0x5EC4F0)
        let lightAccents = Set(Theme.allCases.map { HayakiTheme($0, .light).accentRGB })
        #expect(lightAccents.count == Theme.allCases.count)
    }

    @Test func theTintIsFaintInLightAndDarkAndAbsentInBlack() {
        #expect(HayakiTheme(.hayaki, .light).tintOpacity == 0.04)
        #expect(HayakiTheme(.hayaki, .dark).tintOpacity == 0.06)
        #expect(HayakiTheme(.hayaki, .black).tintOpacity == 0)
    }

    @Test func everyAccentIsReadableOnItsBackgrounds() {
        // iOS system backgrounds: systemBackground and systemGroupedBackground with
        // the tint, then secondarySystemGroupedBackground for surfaces. Paper and
        // Midnight add their own canvas.
        let systemBackgrounds: [ResolvedAppearance: [UInt32]] = [
            .light: [0xFFFFFF, 0xF2F2F7],
            .dark: [0x000000, 0x1C1C1E],
            .black: [0x000000, 0x1C1C1E],
        ]
        for theme in Theme.allCases {
            for (appearance, backgrounds) in systemBackgrounds {
                let resolved = HayakiTheme(theme, appearance)
                var all = backgrounds.map { blend(resolved.accentRGB, over: $0, opacity: resolved.tintOpacity) }
                all += backgrounds
                all.append(resolved.canvasRGB)
                for background in all {
                    #expect(
                        contrast(resolved.accentRGB, background) >= 4.5,
                        "\(theme) \(appearance) accent on \(String(format: "%06X", background))"
                    )
                }
            }
        }
    }

    @Test func prominentButtonLabelsAreReadableOnEveryAccent() {
        for theme in Theme.allCases {
            for appearance in [ResolvedAppearance.light, .dark, .black] {
                let resolved = HayakiTheme(theme, appearance)
                #expect(
                    contrast(resolved.onAccentRGB, resolved.accentRGB) >= 4.5,
                    "\(theme) \(appearance) label on accent"
                )
            }
        }
    }

    @Test func theCardCanvasMatchesTheTintedStudyBackground() {
        #expect(HayakiTheme(.hayaki, .light).canvasRGB == 0xF7FAF9)
        #expect(HayakiTheme(.hayaki, .dark).canvasRGB == 0x080D0C)
        #expect(HayakiTheme(.hayaki, .black).canvasRGB == 0x000000)
    }

    @Test func onlyPaperAndMidnightChangeTheCardCanvas() {
        #expect(HayakiTheme(.paper, .light).canvasRGB == 0xF6F1E7)
        #expect(HayakiTheme(.paper, .dark).canvasRGB == 0x1E1A15)
        #expect(HayakiTheme(.midnight, .light).canvasRGB == 0xEEF3FA)
        #expect(HayakiTheme(.midnight, .dark).canvasRGB == 0x0B1426)
        // Black stays pure black in every theme.
        #expect(HayakiTheme(.midnight, .black).canvasRGB == 0x000000)
        let overriding = Theme.allCases.filter { $0.palette.lightCanvasRGB != nil || $0.palette.darkCanvasRGB != nil }
        #expect(overriding == [.paper, .midnight])
        for theme in Theme.allCases where !overriding.contains(theme) {
            let resolved = HayakiTheme(theme, .light)
            #expect(resolved.canvasRGB == blend(resolved.accentRGB, over: 0xFFFFFF, opacity: resolved.tintOpacity))
        }
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
