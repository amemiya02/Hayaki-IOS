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
        settings.mode = .dark
        #expect(AppearanceSettings(store: defaults).resolved(for: .light) == .dark)
        settings.mode = .black
        #expect(AppearanceSettings(store: defaults).resolved(for: .light) == .black)

        settings.mode = .system
        let reopened = AppearanceSettings(store: defaults)
        #expect(reopened.resolved(for: .light) == .light)
        #expect(reopened.resolved(for: .dark) == .black)
        #expect(reopened.preferredColorScheme == nil)
    }
}
