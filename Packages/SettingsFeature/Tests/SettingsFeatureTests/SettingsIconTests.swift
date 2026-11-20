@testable import SettingsFeature
import Testing
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct SettingsIconTests {
    @Test func everyMoreRowHasASystemSymbolThatExists() {
        for icon in SettingsIcon.all {
            #expect(symbolExists(icon.symbol), "\(icon.symbol) is not an SF Symbol")
        }
    }

    @Test func noTwoMoreRowsShareAnIcon() {
        let symbols = SettingsIcon.all.map(\.symbol)
        #expect(Set(symbols).count == symbols.count)
        #expect(SettingsIcon.reviewer.symbol != SettingsIcon.noteTypes.symbol)
    }

    private func symbolExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        UIImage(systemName: name) != nil
        #else
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #endif
    }
}
