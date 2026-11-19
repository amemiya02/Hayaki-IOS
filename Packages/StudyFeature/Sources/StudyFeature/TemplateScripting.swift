import AnkiProto
import Foundation

struct TemplateRequest: Equatable, Sendable {
    let command: String
    let version: String
    let developer: String
    var data: String?

    func decoded<T: Decodable>(_ type: T.Type) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: Data(data.utf8))
    }

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
    var searchResults: String? = nil

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
        var reply = ["success": success, "value": value]
        if let searchResults { reply["searchResults"] = searchResults }
        return reply
    }
}

extension StudySessionModel {
    func handleTemplate(
        _ request: TemplateRequest, cardID: Int64, isAnswer: Bool, typedAnswer: String = "",
        allowsCollectionAccess: Bool = false
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
        if request.command == "searchCardWithCallback" {
            guard allowsCollectionAccess, let query = request.data else { return .unavailable }
            return await templateSearch(query, cardID: cardID, isAnswer: isAnswer)
        }
        guard !isBusy else { return .unavailable }
        if request.command == "setNoteTags" || request.command == "addTagToNote" {
            return await templateTagUpdate(request, on: card, allowsCollectionAccess: allowsCollectionAccess)
        }
        return await runTemplateAction(request, card: card, isAnswer: isAnswer, typedAnswer: typedAnswer)
    }

    private func templateQueueValue(_ command: String, card: StudyCard, isAnswer: Bool) -> TemplateReply? {
        switch command {
        case "init": .accepted
        case "newCardCount": .value(.integer(Int64(counts.new)))
        case "lrnCardCount": .value(.integer(Int64(counts.learning)))
        case "revCardCount": .value(.integer(Int64(counts.due)))
        case "eta": .value(.integer(0))
        case "nextTime1": .value(.text(isAnswer && showsRatingIntervals ? card.intervals[.again] : ""))
        case "nextTime2": .value(.text(isAnswer && showsRatingIntervals ? card.intervals[.hard] : ""))
        case "nextTime3": .value(.text(isAnswer && showsRatingIntervals ? card.intervals[.good] : ""))
        case "nextTime4": .value(.text(isAnswer && showsRatingIntervals ? card.intervals[.easy] : ""))
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

    private func templateTagUpdate(
        _ request: TemplateRequest, on card: StudyCard, allowsCollectionAccess: Bool
    ) async -> TemplateReply {
        switch request.command {
        case "setNoteTags":
            guard let input = request.decoded(TagUpdate.self), input.tags.allSatisfy(Self.isTemplateTag) else {
                return .unavailable
            }
            await updateTemplateTags(noteID: card.noteID) { $0 = input.tags }
        case "addTagToNote":
            guard let input = request.decoded(TagAddition.self), Self.isTemplateTag(input.tag),
                  input.noteId == card.noteID || allowsCollectionAccess else { return .unavailable }
            await updateTemplateTags(noteID: input.noteId) { tags in
                if !tags.contains(input.tag) { tags.append(input.tag) }
            }
        default:
            return .unavailable
        }
        return actionError == nil ? .accepted : .unavailable
    }

    private nonisolated static func isTemplateTag(_ tag: String) -> Bool {
        !tag.isEmpty && !tag.contains(where: \.isWhitespace)
    }

    private func templateSearch(_ query: String, cardID: Int64, isAnswer: Bool) async -> TemplateReply {
        do {
            let result = try await store.core.searchCards(.with { $0.search = query })
            var notes: [Int64: [String: String]] = [:]
            var fields: [Int64: [String]] = [:]
            var cards: [SearchMatch] = []
            cards.reserveCapacity(result.ids.count)
            for id in result.ids {
                guard !Task.isCancelled, store.allowsNewProfileWork,
                      state.card?.id == cardID, (state.answer != nil) == isAnswer else { return .unavailable }
                let card = try await store.core.getCard(.with { $0.cid = id })
                if notes[card.noteID] == nil {
                    let note = try await store.core.getNote(.with { $0.nid = card.noteID })
                    if fields[note.notetypeID] == nil {
                        let type = try await store.core.getNotetype(.with { $0.ntid = note.notetypeID })
                        fields[note.notetypeID] = type.fields.map(\.name)
                    }
                    notes[card.noteID] = Dictionary(zip(fields[note.notetypeID] ?? [], note.fields), uniquingKeysWith: { first, _ in first })
                }
                cards.append(SearchMatch(cardId: id, noteId: card.noteID, fieldsData: notes[card.noteID] ?? [:]))
            }
            let encoded = try JSONEncoder().encode(cards)
            return TemplateReply(success: true, value: .boolean(true), searchResults: String(decoding: encoded, as: UTF8.self))
        } catch {
            return .unavailable
        }
    }

    private struct SearchMatch: Encodable {
        let cardId: Int64
        let noteId: Int64
        let fieldsData: [String: String]
    }

    private struct TagUpdate: Decodable { let tags: [String] }

    private struct TagAddition: Decodable {
        let noteId: Int64
        let tag: String
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
