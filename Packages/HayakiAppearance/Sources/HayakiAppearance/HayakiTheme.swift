import SwiftUI

/// The resolved appearance: system backgrounds plus the default Hayaki theme's
/// teal accent (taken from the app icon's background) and its faint tint.
public enum HayakiTheme: Sendable {
    case light, dark, black

    /// The Hayaki accent in sRGB. Black mode reuses the dark accent.
    public var accentRGB: UInt32 { self == .light ? 0x2C776E : 0x7ED6CA }
    public var accent: Color { Color(hayakiRGB: accentRGB) }

    /// How strongly the accent tints the screen background. Black mode keeps
    /// a pure black background.
    public var tintOpacity: Double {
        switch self {
        case .light: 0.04
        case .dark: 0.06
        case .black: 0
        }
    }

    /// The study screen's background in sRGB (`systemBackground` plus the tint),
    /// for the card page's canvas.
    public var canvasRGB: UInt32 {
        switch self {
        case .light: Self.blend(accentRGB, over: 0xFFFFFF, opacity: tintOpacity)
        case .dark: Self.blend(accentRGB, over: 0x000000, opacity: tintOpacity)
        case .black: 0x000000
        }
    }

    /// Card and section surfaces.
    public var surface: Color { Color.hayakiSecondaryGroupedBackground }

    private static func blend(_ foreground: UInt32, over background: UInt32, opacity: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { result, shift in
            let top = Double((foreground >> shift) & 255)
            let bottom = Double((background >> shift) & 255)
            return result | UInt32((top * opacity + bottom * (1 - opacity)).rounded()) << shift
        }
    }
}

/// Colors that carry meaning. They are system colors, never themed, so they
/// stay the same in every theme and follow Increase Contrast.
public enum SemanticColor: CaseIterable, Sendable {
    case new, learning, due, again, hard, good, easy

    public var color: Color {
        switch self {
        case .again, .learning: .red
        case .hard: .orange
        case .good, .due: .green
        case .easy, .new: .blue
        }
    }
}

/// Which system background a screen uses.
public enum HayakiBackgroundStyle: Sendable {
    /// `systemGroupedBackground`, for lists and forms.
    case grouped
    /// `systemBackground`, for the study screen.
    case plain
}

/// A system background with the theme tint over it.
public struct HayakiBackground: View {
    @Environment(\.hayakiTheme) private var theme
    private let style: HayakiBackgroundStyle

    public init(_ style: HayakiBackgroundStyle = .grouped) {
        self.style = style
    }

    public var body: some View {
        if theme == .black {
            Color.black
        } else {
            (style == .grouped ? Color.hayakiGroupedBackground : Color.hayakiPlainBackground)
                .overlay(theme.accent.opacity(theme.tintOpacity))
        }
    }
}

extension Color {
    init(hayakiRGB rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double(rgb >> 16) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255
        )
    }

    #if canImport(UIKit)
    static var hayakiGroupedBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var hayakiPlainBackground: Color { Color(uiColor: .systemBackground) }
    static var hayakiSecondaryGroupedBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    #else
    static var hayakiGroupedBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var hayakiPlainBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var hayakiSecondaryGroupedBackground: Color { Color(nsColor: .controlBackgroundColor) }
    #endif
}

private struct HayakiThemeKey: EnvironmentKey {
    static let defaultValue: HayakiTheme? = nil
}

public extension EnvironmentValues {
    var hayakiTheme: HayakiTheme {
        get { self[HayakiThemeKey.self] ?? (colorScheme == .dark ? .dark : .light) }
        set { self[HayakiThemeKey.self] = newValue }
    }
}

public extension View {
    func hayakiAppearance() -> some View {
        modifier(AppearanceModifier())
    }

    /// Keep the native scroll controls, using the tinted grouped background behind them.
    func hayakiScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .hayakiBackground(.grouped)
    }

    /// Fill the screen behind this view with a tinted system background.
    func hayakiBackground(_ style: HayakiBackgroundStyle = .grouped) -> some View {
        background { HayakiBackground(style).ignoresSafeArea() }
    }

    /// The style for text that is only digits: SF Rounded with monospaced digits.
    /// Keep any words (units, labels) in a separate `Text`, since SF Rounded has
    /// no Chinese or Japanese glyphs.
    func hayakiNumeric() -> some View {
        fontDesign(.rounded).monospacedDigit()
    }
}

private struct AppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    private var settings = AppearanceSettings()

    func body(content: Content) -> some View {
        let theme = settings.resolved(for: systemColorScheme)
        content
            // Fill the screen so a small view (such as a loading spinner)
            // does not get a background rectangle of its own.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .hayakiBackground(.grouped)
            .environment(\.hayakiTheme, theme)
            .tint(theme.accent)
            .preferredColorScheme(settings.preferredColorScheme)
    }
}
