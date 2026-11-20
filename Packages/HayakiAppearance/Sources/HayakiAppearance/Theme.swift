/// One theme's tokens in sRGB. Black mode reuses the dark accent.
public struct ThemePalette: Equatable, Sendable {
    public let lightAccentRGB: UInt32
    public let darkAccentRGB: UInt32
    /// The study screen and card canvas, when the theme sets its own.
    public let lightCanvasRGB: UInt32?
    public let darkCanvasRGB: UInt32?

    public init(light: UInt32, dark: UInt32, lightCanvas: UInt32? = nil, darkCanvas: UInt32? = nil) {
        lightAccentRGB = light
        darkAccentRGB = dark
        lightCanvasRGB = lightCanvas
        darkCanvasRGB = darkCanvas
    }
}

/// The accent color and background tint, chosen independently of the
/// appearance (System, Light, Dark or Black). Adding a theme means adding a
/// case and its palette entry.
public enum Theme: String, CaseIterable, Identifiable, Sendable {
    case hayaki, sakura, matcha, ocean, indigo, wisteria, amber, sumi, paper, midnight

    public static let `default`: Theme = .hayaki

    public var id: String { rawValue }

    /// Light accents are tuned to reach 4.5:1 on the tinted grouped background
    /// (see the spec's theme table; Sakura, Matcha, Wisteria, Amber and
    /// Midnight are darkened from its starting values to get there).
    public var palette: ThemePalette {
        switch self {
        // The icon's teal, darkened slightly from #2E7D74 for contrast.
        case .hayaki: ThemePalette(light: 0x2C776E, dark: 0x7ED6CA)
        case .sakura: ThemePalette(light: 0xB04663, dark: 0xFF9DB7)
        case .matcha: ThemePalette(light: 0x50743F, dark: 0xA8CF8E)
        case .ocean: ThemePalette(light: 0x0A6E9E, dark: 0x5EC4F0)
        case .indigo: ThemePalette(light: 0x3A5BD9, dark: 0x8FA8FF)
        case .wisteria: ThemePalette(light: 0x745AB9, dark: 0xB9A3F5)
        case .amber: ThemePalette(light: 0x916019, dark: 0xF5C451)
        case .sumi: ThemePalette(light: 0x4A4A4F, dark: 0xC7C7CC)
        case .paper: ThemePalette(light: 0x8A5A2B, dark: 0xD9A86C, lightCanvas: 0xF6F1E7, darkCanvas: 0x1E1A15)
        case .midnight: ThemePalette(light: 0x1A757F, dark: 0x5EE6EE, lightCanvas: 0xEEF3FA, darkCanvas: 0x0B1426)
        }
    }
}

/// What the appearance setting resolves to on screen.
public enum ResolvedAppearance: Hashable, Sendable {
    case light, dark, black
}
