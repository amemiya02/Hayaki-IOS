import SwiftUI

/// A reviewer command and the key that triggers it, as listed in the
/// system shortcut overlay (holding Command on an iPad keyboard).
public struct ReviewerShortcut: Hashable, Sendable {
    public let command: ReviewerCommand
    public let key: ReviewerKey
}

extension ReviewerPreferences {
    /// One shortcut per command bound to a keyboard key on `side`, in command
    /// order. A command with several keys shows the one with the fewest
    /// modifiers, preferring Command over Control; each key is listed once.
    public func keyboardShortcuts(on side: ReviewerSide) -> [ReviewerShortcut] {
        var usedKeys = Set<ReviewerKey>()
        return ReviewerCommand.allCases.compactMap { command in
            let keys = bindings.compactMap { binding -> ReviewerKey? in
                guard binding.side == side, binding.command == command,
                      case .keyboard(let key) = binding.input, key.keyEquivalent != nil,
                      !usedKeys.contains(key) else { return nil }
                return key
            }
            guard let key = keys.enumerated().min(by: { Self.rank($0) < Self.rank($1) })?.element else { return nil }
            usedKeys.insert(key)
            return ReviewerShortcut(command: command, key: key)
        }
    }

    private static func rank(_ entry: (offset: Int, element: ReviewerKey)) -> (Int, Int, Int) {
        let modifiers = entry.element.modifiers
        return (modifiers.count, modifiers.contains(.command) ? 0 : 1, entry.offset)
    }
}

extension ReviewerKey {
    /// The system key for this reviewer key, or nil for a key the system
    /// cannot name in a shortcut.
    public var keyEquivalent: KeyEquivalent? {
        switch name {
        case "space": .space
        case "return": .return
        case "escape": .escape
        case "tab": .tab
        case "backspace": .delete
        case "arrowup": .upArrow
        case "arrowdown": .downArrow
        case "arrowleft": .leftArrow
        case "arrowright": .rightArrow
        case "pageup": .pageUp
        case "pagedown": .pageDown
        default: name.count == 1 ? name.first.map { KeyEquivalent($0) } : nil
        }
    }

    public var eventModifiers: EventModifiers {
        modifiers.reduce(into: []) { result, modifier in
            switch modifier {
            case .shift: result.insert(.shift)
            case .control: result.insert(.control)
            case .option: result.insert(.option)
            case .command: result.insert(.command)
            }
        }
    }
}

/// What the study screen offers the app's Study menu while it is on screen.
public struct ReviewerShortcutMenu {
    let shortcuts: [ReviewerShortcut]
    let isEnabled: Bool
    let perform: @MainActor (ReviewerKey) -> Void
}

extension FocusedValues {
    @Entry var reviewerShortcutMenu: ReviewerShortcutMenu?
}

/// The Study menu: every reviewer keyboard shortcut for the side on screen,
/// with its localized title, so it appears in the system shortcut overlay
/// and the iPad menu bar. Add it to the app's scene with `.commands`.
public struct StudyCommands: Commands {
    @FocusedValue(\.reviewerShortcutMenu) private var menu

    public init() {}

    public var body: some Commands {
        CommandMenu(Text("Study", bundle: .module)) {
            if let menu {
                ForEach(menu.shortcuts, id: \.self) { shortcut in
                    if let key = shortcut.key.keyEquivalent {
                        Button(shortcut.command.title) { menu.perform(shortcut.key) }
                            .keyboardShortcut(key, modifiers: shortcut.key.eventModifiers)
                            .disabled(!menu.isEnabled)
                    }
                }
            }
        }
    }
}
