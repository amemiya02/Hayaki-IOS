import Foundation

public enum ReviewerSide: String, CaseIterable, Codable, Sendable {
    case question
    case answer
}

public enum ReviewerGesture: String, CaseIterable, Codable, Sendable {
    case swipeUp, swipeDown, swipeLeft, swipeRight, doubleTap
    case tapTopLeft, tapTop, tapTopRight, tapLeft, tapCenter, tapRight
    case tapBottomLeft, tapBottom, tapBottomRight
    case twoFingerTap, threeFingerTap, fourFingerTap, shake

    var isTapZone: Bool {
        switch self {
        case .tapTopLeft, .tapTop, .tapTopRight, .tapLeft, .tapCenter, .tapRight,
             .tapBottomLeft, .tapBottom, .tapBottomRight: true
        default: false
        }
    }
}

public enum ReviewerTapZones: String, CaseIterable, Codable, Sendable {
    case edges, grid

    func gesture(x: Double, y: Double) -> ReviewerGesture {
        switch self {
        case .edges:
            if abs(x - 0.5) > abs(y - 0.5) { return x < 0.5 ? .tapLeft : .tapRight }
            return y < 0.5 ? .tapTop : .tapBottom
        case .grid:
            let zones: [[ReviewerGesture]] = [
                [.tapTopLeft, .tapTop, .tapTopRight],
                [.tapLeft, .tapCenter, .tapRight],
                [.tapBottomLeft, .tapBottom, .tapBottomRight],
            ]
            return zones[min(2, max(0, Int(y * 3)))][min(2, max(0, Int(x * 3)))]
        }
    }

    var gestures: [ReviewerGesture] {
        switch self {
        case .edges: [.tapTop, .tapLeft, .tapRight, .tapBottom]
        case .grid: ReviewerGesture.allCases.filter(\.isTapZone)
        }
    }
}

public struct ReviewerKey: Hashable, Codable, Sendable {
    public let name: String
    public let modifiers: Set<Modifier>

    public enum Modifier: String, Codable, Sendable {
        case shift, control, option, command
    }

    public init(_ name: String, modifiers: Set<Modifier> = []) {
        self.name = name.lowercased()
        self.modifiers = modifiers
    }
}

public enum ReviewerInput: Hashable, Codable, Sendable {
    case gesture(ReviewerGesture)
    case keyboard(ReviewerKey)
    case controller(String)

    public static func key(_ name: String, modifiers: Set<ReviewerKey.Modifier> = []) -> Self {
        .keyboard(ReviewerKey(name, modifiers: modifiers))
    }
}

/// Commands shared by input bindings, the reviewer toolbar and automation.
public enum ReviewerCommand: String, CaseIterable, Codable, Sendable {
    case showAnswer, rateAgain, rateHard, rateGood, rateEasy
    case undo, redo, mark, edit, addNote, editTags
    case buryCard, buryNote, suspendCard, suspendNote
    case deleteNote, setDueDate, resetProgress
    case clearFlag, flagRed, flagOrange, flagGreen, flagBlue, flagPink, flagTurquoise, flagPurple
    case toggleRedFlag, toggleOrangeFlag, toggleGreenFlag, toggleBlueFlag, togglePinkFlag
    case toggleTurquoiseFlag, togglePurpleFlag
    case replayMedia, recordVoice, replayVoice, toggleWhiteboard, toggleAutoAdvance
    case browse, statistics, deckOptions, cardInfo, previousCardInfo
    case showHint, showAllHints, pageUp, pageDown, exit
    case userAction1, userAction2, userAction3, userAction4, userAction5
    case userAction6, userAction7, userAction8, userAction9

    var rating: Rating? {
        switch self {
        case .rateAgain: .again
        case .rateHard: .hard
        case .rateGood: .good
        case .rateEasy: .easy
        default: nil
        }
    }

    var flag: UInt32? {
        switch self {
        case .clearFlag: 0
        case .flagRed, .toggleRedFlag: 1
        case .flagOrange, .toggleOrangeFlag: 2
        case .flagGreen, .toggleGreenFlag: 3
        case .flagBlue, .toggleBlueFlag: 4
        case .flagPink, .togglePinkFlag: 5
        case .flagTurquoise, .toggleTurquoiseFlag: 6
        case .flagPurple, .togglePurpleFlag: 7
        default: nil
        }
    }

    var togglesFlag: Bool {
        switch self {
        case .toggleRedFlag, .toggleOrangeFlag, .toggleGreenFlag, .toggleBlueFlag, .togglePinkFlag,
             .toggleTurquoiseFlag, .togglePurpleFlag: true
        default: false
        }
    }

    var userActionNumber: Int? {
        guard rawValue.hasPrefix("userAction"), let digit = rawValue.last else { return nil }
        return digit.wholeNumberValue
    }
}

public struct ReviewerBinding: Equatable, Identifiable, Codable, Sendable {
    public let input: ReviewerInput
    public let side: ReviewerSide
    public let command: ReviewerCommand

    public var id: Identifier { Identifier(input: input, side: side) }

    public struct Identifier: Hashable, Sendable {
        public let input: ReviewerInput
        public let side: ReviewerSide
    }
}

/// Device preferences are stored independently of the Anki collection.
public struct ReviewerPreferences: Equatable, Codable, Sendable {
    static let key = "reviewer.preferences"
    public var bindings = defaultBindings
    public var tapZones: ReviewerTapZones = .edges
    public var doubleTapMilliseconds = 200
    public var minimumPressMilliseconds = 0
    public var swipeSensitivity = 100

    public init() {}

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public mutating func bind(_ command: ReviewerCommand?, to input: ReviewerInput, on side: ReviewerSide) {
        bindings.removeAll { $0.input == input && $0.side == side }
        if let command {
            bindings.append(ReviewerBinding(input: input, side: side, command: command))
        }
    }

    public func command(for input: ReviewerInput, on side: ReviewerSide) -> ReviewerCommand? {
        bindings.first { $0.input == input && $0.side == side }?.command
    }

    static let defaultBindings: [ReviewerBinding] = {
        var defaults: [ReviewerBinding] = []
        func add(_ command: ReviewerCommand, _ inputs: [ReviewerInput], sides: [ReviewerSide] = ReviewerSide.allCases) {
            for side in sides {
                defaults += inputs.map { ReviewerBinding(input: $0, side: side, command: command) }
            }
        }

        add(.showAnswer, [.key("space"), .key("return")], sides: [.question])
        add(.rateAgain, [.key("1"), .controller("buttonY")], sides: [.answer])
        add(.rateHard, [.key("2"), .controller("buttonX")], sides: [.answer])
        add(.rateGood, [.key("3"), .key("space"), .key("return"), .controller("dpadCenter")], sides: [.answer])
        add(.rateGood, [.controller("buttonB")], sides: [.answer])
        add(.rateEasy, [.key("4"), .controller("buttonA")], sides: [.answer])

        add(.undo, [.key("z", modifiers: [.control]), .key("z", modifiers: [.command])])
        add(.redo, [.key("z", modifiers: [.shift, .control]), .key("z", modifiers: [.shift, .command])])
        add(.mark, [.key("*", modifiers: [.shift]), .key("*")])
        add(.edit, [.key("e")])
        add(.addNote, [.key("a")])
        add(.buryNote, [.key("=")])
        add(.buryCard, [.key("-")])
        add(.suspendNote, [.key("!", modifiers: [.shift]), .key("!")])
        add(.suspendCard, [.key("@", modifiers: [.shift]), .key("@")])
        add(.toggleAutoAdvance, [.key("a", modifiers: [.shift])])
        add(.showHint, [.key("h")])
        add(.showAllHints, [.key("g")])
        add(.recordVoice, [.key("v", modifiers: [.shift])])
        add(.replayVoice, [.key("v")])
        add(.browse, [.key("b")])
        add(.statistics, [.key("t")])
        add(.replayMedia, [.key("r")])
        add(.previousCardInfo, [.key("i", modifiers: [.control, .option])])
        add(.resetProgress, [.key("n", modifiers: [.control, .option])])

        let flags: [ReviewerCommand] = [.toggleRedFlag, .toggleOrangeFlag, .toggleGreenFlag, .toggleBlueFlag,
                                        .togglePinkFlag, .toggleTurquoiseFlag, .togglePurpleFlag]
        for (offset, flag) in flags.enumerated() {
            add(flag, [.key(String(offset + 1), modifiers: [.control])])
        }
        return defaults
    }()
}
