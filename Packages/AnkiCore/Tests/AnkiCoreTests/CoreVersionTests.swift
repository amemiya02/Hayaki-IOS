import AnkiCore
import Testing

@Test("The Core Client identifies the embedded Anki release")
func embeddedCoreVersion() {
    // Update this alongside the vendor/anki pin when upgrading Anki.
    #expect(CoreClient.embeddedVersion == "26.09.4")
}
