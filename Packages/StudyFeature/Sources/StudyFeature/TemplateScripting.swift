import AnkiProto
import Foundation

struct TemplateRequest: Equatable, Sendable {
    let command: String
    let version: String
    let developer: String
    var data: String?

    var isValid: Bool { version == "0.0.3" && !developer.isEmpty }

    init(command: String, version: String, developer: String, data: String? = nil) {
        self.command = command
        self.version = version
        self.developer = developer
        self.data = data
    }

    init?(message: Any) {
        guard let arguments = message as? [String: Any],
              let command = arguments["command"] as? String,
              let version = arguments["version"] as? String,
              let developer = arguments["developer"] as? String
        else { return nil }
        let data = arguments["data"] as? String
        guard command.utf8.count <= 80, version.utf8.count <= 20, developer.utf8.count <= 1024,
              (data?.utf8.count ?? 0) <= 32_768 else { return nil }
        self.init(command: command, version: version, developer: developer, data: data)
    }
}

struct TemplateReply: Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case integer(Int64)
        case boolean(Bool)
        case text(String)
    }

    let success: Bool
    let value: Value

    static let invalid = Self(success: false, value: .integer(-1))
    static let accepted = Self(success: true, value: .boolean(true))
    static let unavailable = Self(success: true, value: .boolean(false))

    static func value(_ value: Value) -> Self { Self(success: true, value: value) }

    var message: [String: Any] {
        let value: Any = switch self.value {
        case .integer(let value): value
        case .boolean(let value): value
        case .text(let value): value
        }
        return ["success": success, "value": value]
    }
}

extension StudySessionModel {
    func handleTemplate(
        _ request: TemplateRequest, cardID: Int64, isAnswer: Bool, typedAnswer: String = ""
    ) async -> TemplateReply {
        guard request.isValid else { return .invalid }
        guard store.allowsNewProfileWork, let card = state.card,
              card.id == cardID, (state.answer != nil) == isAnswer else { return .unavailable }

        if let reply = templateQueueValue(request.command, card: card, isAnswer: isAnswer) { return reply }
        if request.command.hasPrefix("card"), let reply = await templateStoredCardValue(request.command, id: cardID) {
            return reply
        }
        if request.command == "deckName" {
            guard let stored = try? await store.core.getCard(.with { $0.cid = cardID }),
                  let deck = try? await store.core.getDeck(.with { $0.did = stored.deckID })
            else { return .unavailable }
            return .value(.text(deck.name.components(separatedBy: "::").last ?? deck.name))
        }
        if request.command == "getNoteTags" {
            guard let note = try? await store.core.getNote(.with { $0.nid = card.noteID }),
                  let data = try? JSONEncoder().encode(note.tags)
            else { return .unavailable }
            return .value(.text(String(decoding: data, as: UTF8.self)))
        }
        guard !isBusy else { return .unavailable }
        return await runTemplateAction(request, card: card, isAnswer: isAnswer, typedAnswer: typedAnswer)
    }

    private func templateQueueValue(_ command: String, card: StudyCard, isAnswer: Bool) -> TemplateReply? {
        switch command {
        case "init": .accepted
        case "newCardCount": .value(.integer(Int64(counts.new)))
        case "lrnCardCount": .value(.integer(Int64(counts.learning)))
        case "revCardCount": .value(.integer(Int64(counts.due)))
        case "eta": .value(.integer(-1))
        case "nextTime1": .value(.text(card.intervals[.again]))
        case "nextTime2": .value(.text(card.intervals[.hard]))
        case "nextTime3": .value(.text(card.intervals[.good]))
        case "nextTime4": .value(.text(card.intervals[.easy]))
        case "cardMark": .value(.boolean(card.isNoteMarked))
        case "cardFlag": .value(.integer(Int64(card.flag)))
        case "cardId": .value(.integer(card.id))
        case "cardNid": .value(.integer(card.noteID))
        case "isDisplayingAnswer": .value(.boolean(isAnswer))
        default: nil
        }
    }

    private func templateStoredCardValue(_ command: String, id: Int64) async -> TemplateReply? {
        guard let card = try? await store.core.getCard(.with { $0.cid = id }) else { return .unavailable }
        let value: Int64
        switch command {
        case "cardDid": value = card.deckID
        case "cardReps": value = Int64(card.reps)
        case "cardInterval": value = Int64(card.interval)
        case "cardFactor": value = Int64(card.easeFactor)
        case "cardMod": value = card.mtimeSecs
        case "cardType": value = Int64(card.ctype)
        case "cardLeft": value = Int64(card.remainingSteps)
        case "cardODid": value = card.originalDeckID
        case "cardODue": value = Int64(card.originalDue)
        case "cardQueue": value = Int64(card.queue)
        case "cardLapses": value = Int64(card.lapses)
        case "cardDue": value = Int64(card.due)
        default: return nil
        }
        return .value(.integer(value))
    }

    private func runTemplateAction(
        _ request: TemplateRequest, card: StudyCard, isAnswer: Bool, typedAnswer: String
    ) async -> TemplateReply {
        switch request.command {
        case "showAnswer", "answerEase1", "answerEase2", "answerEase3", "answerEase4":
            if !isAnswer {
                await showAnswer(typed: typedAnswer)
                return state.answer?.id == card.id ? .accepted : .unavailable
            }
            if let digit = request.command.last?.wholeNumberValue {
                let reviewed = reviewedCount
                await answer(Rating.allCases[digit - 1])
                return reviewedCount > reviewed ? .accepted : .unavailable
            }
            return .accepted
        case "toggleFlag":
            let flags: [String: UInt32] = [
                "none": 0, "red": 1, "orange": 2, "green": 3, "blue": 4, "pink": 5, "turquoise": 6, "purple": 7,
            ]
            guard let name = request.data, let flag = flags[name] else { return .unavailable }
            await setFlag(card.flag == flag ? 0 : flag)
        case "markCard": await toggleMark()
        case "buryCard": await bury(note: false)
        case "buryNote": await bury(note: true)
        case "suspendCard": await suspend(note: false)
        case "suspendNote": await suspend(note: true)
        case "setCardDue":
            guard let text = request.data, let days = Int(text), (0...9_999).contains(days) else {
                return .unavailable
            }
            await setDueDate(String(days))
        case "resetProgress": await resetProgress()
        default: return .unavailable
        }
        return actionError == nil ? .accepted : .unavailable
    }
}
