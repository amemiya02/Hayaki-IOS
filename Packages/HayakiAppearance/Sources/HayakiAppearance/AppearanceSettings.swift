import Foundation
import SwiftUI

public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark, black
}

public enum SystemNightMode: String, CaseIterable, Sendable {
    case dark, black
}

/// Device preferences apply across profiles. The night choice is remembered
/// while an explicit appearance is selected.
public struct AppearanceSettings: DynamicProperty {
    @AppStorage public var mode: AppearanceMode
    @AppStorage public var systemNightMode: SystemNightMode

    public init(store: UserDefaults? = nil) {
        _mode = AppStorage(wrappedValue: .system, "hayaki.appearance.mode", store: store)
        _systemNightMode = AppStorage(wrappedValue: .dark, "hayaki.appearance.systemNightMode", store: store)
    }

    public var preferredColorScheme: ColorScheme? {
        switch mode {
        case .system: nil
        case .light: .light
        case .dark, .black: .dark
        }
    }

    public func resolved(for system: ColorScheme) -> HayakiTheme {
        switch mode {
        case .system:
            if system == .light { return .light }
            return systemNightMode == .black ? .black : .dark
        case .light: return .light
        case .dark: return .dark
        case .black: return .black
        }
    }
}
