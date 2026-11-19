import Foundation
import SwiftUI

public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark, black
}

public enum SystemNightMode: String, CaseIterable, Sendable {
    case dark, black
}

/// Device preferences apply across profiles. An explicit dark or black
/// appearance also becomes the stored choice for System at night.
public struct AppearanceSettings: DynamicProperty {
    public static let browseTextScaleKey = "hayaki.accessibility.browseTextScale"
    public static let browseMediaFilenamesKey = "hayaki.browse.showMediaFilenames"

    @AppStorage private var selection: String

    public init(store: UserDefaults? = nil) {
        _selection = AppStorage(wrappedValue: "system/dark", "hayaki.appearance", store: store)
    }

    public var mode: AppearanceMode {
        get { AppearanceMode(rawValue: stored(0)) ?? .system }
        nonmutating set {
            let night: SystemNightMode
            switch newValue {
            case .system, .light: night = systemNightMode
            case .dark: night = .dark
            case .black: night = .black
            }
            select(newValue, night: night)
        }
    }

    public var systemNightMode: SystemNightMode {
        get { SystemNightMode(rawValue: stored(1)) ?? .dark }
        nonmutating set { select(mode, night: newValue) }
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

    private func stored(_ position: Int) -> String {
        let values = selection.split(separator: "/", omittingEmptySubsequences: false)
        return values.indices.contains(position) ? String(values[position]) : ""
    }

    private func select(_ mode: AppearanceMode, night: SystemNightMode) {
        selection = "\(mode.rawValue)/\(night.rawValue)"
    }
}
