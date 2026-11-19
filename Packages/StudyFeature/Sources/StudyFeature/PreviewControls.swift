import Foundation

public enum PreviewCommand: String, CaseIterable, Codable, Sendable {
    case previous, next, mark, edit, answerOnly, replayMedia, clearFlag
    case flagRed, flagOrange, flagGreen, flagBlue, flagPink, flagTurquoise, flagPurple

    public static let coloredFlags: [Self] = [
        .flagRed, .flagOrange, .flagGreen, .flagBlue, .flagPink, .flagTurquoise, .flagPurple,
    ]

    public var flag: UInt32? {
        if self == .clearFlag { return 0 }
        return Self.coloredFlags.firstIndex(of: self).map { UInt32($0 + 1) }
    }

    public var title: String {
        switch self {
        case .previous: String(localized: "Previous Card", bundle: .module)
        case .next: String(localized: "Next Card", bundle: .module)
        case .mark: ReviewerCommand.mark.title
        case .edit: ReviewerCommand.edit.title
        case .answerOnly: String(localized: "Answer Side Only", bundle: .module)
        case .replayMedia: ReviewerCommand.replayMedia.title
        default: ReviewerCommand(rawValue: rawValue)?.title ?? rawValue
        }
    }
}

public struct PreviewControls: Equatable, Codable, Sendable {
    private static let key = "preview.controls"

    struct Binding: Codable, Equatable, Identifiable, Sendable {
        let id: ReviewerInput
        let command: PreviewCommand
    }

    private(set) var bindings = defaultBindings

    public init() {}

    public func command(for input: ReviewerInput) -> PreviewCommand? {
        bindings.first { $0.id == input }?.command
    }

    public mutating func bind(_ command: PreviewCommand?, to input: ReviewerInput) {
        if let index = bindings.firstIndex(where: { $0.id == input }) {
            if let command {
                bindings[index] = Binding(id: input, command: command)
            } else {
                bindings.remove(at: index)
            }
        } else if let command {
            bindings.append(Binding(id: input, command: command))
        }
    }

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return saved
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    var keySignatures: [String] {
        bindings.compactMap {
            guard case .keyboard(let key) = $0.id else { return nil }
            return ([key.name] + key.modifiers.map(\.rawValue).sorted()).joined(separator: "+")
        }
    }

    var usesController: Bool {
        bindings.contains { if case .controller = $0.id { true } else { false } }
    }

    private static let defaultBindings: [Binding] = [
        Binding(id: .key("arrowleft"), command: .previous),
        Binding(id: .key("arrowright"), command: .next),
        Binding(id: .key("*"), command: .mark),
        Binding(id: .key("*", modifiers: [.shift]), command: .mark),
        Binding(id: .key("e"), command: .edit),
        Binding(id: .key("b"), command: .answerOnly),
        Binding(id: .key("r"), command: .replayMedia),
    ] + PreviewCommand.coloredFlags.enumerated().map {
        Binding(id: .key(String($0.offset + 1), modifiers: [.control]), command: $0.element)
    }
}
