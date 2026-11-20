import CollectionTesting
import Foundation
import StudyFeature
import Testing

@MainActor
@Suite("Reviewer controls")
struct ReviewerControlsTests {
    @Test("New reviewer preferences show cards edge to edge and preserve an explicit frame choice")
    func defaultCardFrame() throws {
        let missingFrame = try JSONDecoder().decode(ReviewerPreferences.self, from: Data("{}".utf8))
        let explicitFrame = try JSONDecoder().decode(
            ReviewerPreferences.self, from: Data(#"{"cardFrame":true}"#.utf8)
        )
        let explicitEdgeToEdge = try JSONDecoder().decode(
            ReviewerPreferences.self, from: Data(#"{"cardFrame":false}"#.utf8)
        )
        func savedFrame(_ preferences: ReviewerPreferences) throws -> Bool? {
            (try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])?["cardFrame"] as? Bool
        }
        #expect(try savedFrame(ReviewerPreferences()) == false)
        #expect(try savedFrame(missingFrame) == false)
        #expect(try savedFrame(explicitFrame) == true)
        #expect(try savedFrame(explicitEdgeToEdge) == false)
    }

    @Test("Saved physical bindings reveal and rate on their configured sides")
    func savedPhysicalBindings() async throws {
        let suite = "ReviewerControlsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let trigger = ReviewerInput.controller("buttonA")
        var controls = ReviewerPreferences.load(from: defaults)
        controls.bind(.showAnswer, to: trigger, on: .question)
        controls.bind(.rateEasy, to: trigger, on: .answer)
        controls.save(to: defaults)

        try await withTemporaryCollection { store in
            let deck = try await store.addDeck(named: "Spanish")
            let card = try #require(try await store.addBasicNotes(count: 1, toDeck: deck).first)
            let session = StudySessionModel(store: store, deckID: deck)
            let reopened = ReviewerPreferences.load(from: defaults)
            await session.start()

            #expect(reopened.command(for: .key("4"), on: .question) == nil)
            #expect(await session.perform(.rateEasy) == false)
            #expect(session.state.question?.id == card)
            let reveal = try #require(reopened.command(for: trigger, on: .question))
            #expect(await session.perform(reveal))
            #expect(session.state.answer?.id == card)

            let rate = try #require(reopened.command(for: trigger, on: .answer))
            #expect(await session.perform(rate))
            #expect(session.state.finished != nil)
            #expect(try await store.reviewCount() == 1)
        }
    }
}

@MainActor
@Suite("Reviewer tools")
struct ReviewerToolTests {
    @Test("Drawing and recorder preferences stay isolated by profile and studied deck")
    func isolatedDeckTools() throws {
        let suite = "ReviewerToolTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = URL(fileURLWithPath: "/example/first")
        let other = URL(fileURLWithPath: "/example/second")
        var tools = ReviewerDeckTools.load(profile: profile, deckID: 17, defaults: defaults)
        tools.whiteboardEnabled = true
        tools.drawingShown = false
        tools.stylusOnly = true
        tools.recorderShown = true
        tools.penColor = "red"
        tools.save(profile: profile, deckID: 17, defaults: defaults)

        #expect(ReviewerDeckTools.load(profile: profile, deckID: 17, defaults: defaults) == tools)
        #expect(ReviewerDeckTools.load(profile: profile, deckID: 18, defaults: defaults) == ReviewerDeckTools())
        #expect(ReviewerDeckTools.load(profile: other, deckID: 17, defaults: defaults) == ReviewerDeckTools())
    }
}

#if canImport(PencilKit)
import ImageIO
import PencilKit

extension ReviewerToolTests {
    @Test("Exporting a PencilKit stroke writes a readable PNG")
    func drawingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let points = [12.0, 32.0, 52.0].map { x in
            PKStrokePoint(
                location: CGPoint(x: x, y: 24), timeOffset: x / 1000, size: CGSize(width: 5, height: 5),
                opacity: 1, force: 1, azimuth: 0, altitude: 1
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: .now)
        let drawing = PKDrawing(strokes: [PKStroke(
            ink: PKInk(.pen, color: .black), path: path, transform: .identity, mask: nil
        )])
        let url = try WhiteboardExport.save(drawing, in: root)

        #expect(url.deletingLastPathComponent().lastPathComponent == "Whiteboard")
        #expect(url.pathExtension == "png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let png = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(png.width > 40)
        #expect(png.height > 5)
    }
}
#endif
