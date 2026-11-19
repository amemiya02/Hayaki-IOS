import SwiftUI

public enum HayakiTheme: Sendable {
    case light, dark, black

    /// The pinned Hayaki palettes, expressed in sRGB.
    public var backgroundRGB: UInt32 {
        switch self {
        case .light: 0xFEF7FF
        case .dark: 0x141218
        case .black: 0x000000
        }
    }

    public var surfaceRGB: UInt32 {
        switch self {
        case .light: 0xF7F2FA
        case .dark: 0x211F26
        case .black: 0x0F0E12
        }
    }

    public var accentRGB: UInt32 { self == .light ? 0x6750A4 : 0xD0BCFF }
    public var background: Color { Color(hayakiRGB: backgroundRGB) }
    public var surface: Color { Color(hayakiRGB: surfaceRGB) }
    public var accent: Color { Color(hayakiRGB: accentRGB) }

    public func rgb(for role: SemanticColor) -> UInt32 {
        switch role {
        case .new, .easy: self == .light ? 0x1F5BC4 : 0xA8C7FA
        case .learning, .again: self == .light ? 0xB3261E : 0xF2B8B5
        case .due, .good: self == .light ? 0x1B6E3A : 0x8BD8A0
        case .hard: self == .light ? 0x7A5900 : 0xF0C36D
        }
    }

    public func color(for role: SemanticColor) -> Color {
        Color(hayakiRGB: rgb(for: role))
    }
}

public enum SemanticColor: CaseIterable, Sendable {
    case new, learning, due, again, hard, good, easy
}

private extension Color {
    init(hayakiRGB rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double(rgb >> 16) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255
        )
    }
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

    /// Keep the native scroll controls, using the selected appearance behind them.
    func hayakiScrollBackground() -> some View {
        modifier(ScrollBackgroundModifier())
    }
}

private struct AppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    private var settings = AppearanceSettings()

    func body(content: Content) -> some View {
        let theme = settings.resolved(for: systemColorScheme)
        content
            .environment(\.hayakiTheme, theme)
            .tint(theme.accent)
            .background(theme.background.ignoresSafeArea())
            .preferredColorScheme(settings.preferredColorScheme)
    }
}

private struct ScrollBackgroundModifier: ViewModifier {
    @Environment(\.hayakiTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
    }
}
