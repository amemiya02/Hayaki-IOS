import AppShell
import Testing

@MainActor
@Suite("Adding a note from outside the app")
struct AddNoteOpenerTests {
    @Test("The Home Screen Add Note quick action asks for the note editor once")
    func quickAction() {
        let opener = AddNoteOpener()
        #expect(!opener.isRequested)

        #expect(opener.open(quickActionType: "io.github.amemiya02.hayaki.add-note"))
        #expect(opener.isRequested)

        #expect(opener.takeRequest())
        #expect(!opener.isRequested)
        #expect(!opener.takeRequest())
    }

    @Test("A quick action Hayaki does not know is left alone")
    func unknownQuickAction() {
        let opener = AddNoteOpener()
        #expect(!opener.open(quickActionType: "io.github.amemiya02.hayaki.something-else"))
        #expect(!opener.isRequested)
    }

    @Test("Asking twice before the editor opens still opens it once")
    func repeatedRequests() {
        let opener = AddNoteOpener()
        opener.request()
        opener.request()
        #expect(opener.takeRequest())
        #expect(!opener.takeRequest())
    }
}
