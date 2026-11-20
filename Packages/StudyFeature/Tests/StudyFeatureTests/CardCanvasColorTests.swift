@testable import StudyFeature
import Testing

@Suite("Card canvas colour")
struct CardCanvasColorTests {
    @Test("An opaque CSS colour from the card page is read as sRGB")
    func opaque() throws {
        let white = try #require(CardCanvasColor(css: "rgb(255, 255, 255)"))
        #expect(white == CardCanvasColor(red: 1, green: 1, blue: 1))
        let teal = try #require(CardCanvasColor(css: "rgba(0, 51, 102, 1)"))
        #expect(teal == CardCanvasColor(red: 0, green: 0.2, blue: 0.4))
        #expect(CardCanvasColor(css: "rgb(0 51 102)") == teal)
    }

    @Test("A page with no background of its own leaves the screen's background")
    func transparent() {
        #expect(CardCanvasColor(css: "rgba(0, 0, 0, 0)") == nil)
        #expect(CardCanvasColor(css: "transparent") == nil)
        #expect(CardCanvasColor(css: "") == nil)
        #expect(CardCanvasColor(css: "rgba(10, 20, 30, 0.5)") == nil)
    }

    @Test("Anything else is ignored")
    func malformed() {
        #expect(CardCanvasColor(css: "red") == nil)
        #expect(CardCanvasColor(css: "rgb(1, 2)") == nil)
        #expect(CardCanvasColor(css: "rgb(a, b, c)") == nil)
    }

    @Test("The page reports its canvas with a background message")
    func pageEvent() {
        #expect(CardPageEvent(message: ["background": "rgb(255, 255, 255)"])
            == .background(CardCanvasColor(red: 1, green: 1, blue: 1)))
        #expect(CardPageEvent(message: ["background": "rgba(0, 0, 0, 0)"]) == .background(nil))
    }
}
