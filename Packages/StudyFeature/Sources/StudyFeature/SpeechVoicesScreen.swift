#if os(iOS)
import AVFoundation
import SwiftUI

/// Voice discovery for writing compatible card templates.
struct SpeechVoicesScreen: View {
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var search = ""
    @State private var sample = ""
    @State private var audio = CardAudioPlayer()

    var body: some View {
        List {
            Section("Voice Preview") {
                TextField("Text to Speak", text: $sample)
            }
            ForEach(languages, id: \.self) { language in
                Section(Locale.current.localizedString(forIdentifier: language) ?? language) {
                    ForEach(filtered.filter { $0.language == language }, id: \.identifier) { voice in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(voice.name)
                                Text(verbatim: voice.language.replacingOccurrences(of: "-", with: "_"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Preview", systemImage: "play.circle") {
                                let text = sample.isEmpty ? voice.name : sample
                                audio.play([.speech(.init(
                                    text: text, language: voice.language, voices: [voice.identifier], speed: 1
                                ))])
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            Button("Copy Template Filter", systemImage: "document.on.document") {
                                UIPasteboard.general.string = "{{tts \(voice.language.replacingOccurrences(of: "-", with: "_")) voices=\(CardSpeechVoice.templateName(voice)):Field}}"
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Text-to-Speech Voices")
        .searchable(text: $search)
        .task {
            voices = AVSpeechSynthesisVoice.speechVoices().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        .onDisappear { audio.stop() }
    }

    private var languages: [String] {
        Set(filtered.map(\.language)).sorted {
            let locale = Locale.current
            return (locale.localizedString(forIdentifier: $0) ?? $0)
                .localizedStandardCompare(locale.localizedString(forIdentifier: $1) ?? $1) == .orderedAscending
        }
    }

    private var filtered: [AVSpeechSynthesisVoice] {
        guard !search.isEmpty else { return voices }
        return voices.filter { voice in
            voice.name.localizedCaseInsensitiveContains(search)
                || voice.language.localizedCaseInsensitiveContains(search)
                || Locale.current.localizedString(forIdentifier: voice.language)?.localizedCaseInsensitiveContains(search) == true
        }
    }
}

@MainActor
enum CardSpeechVoice {
    static func templateName(_ voice: AVSpeechSynthesisVoice) -> String {
        "Apple_" + voice.name.replacingOccurrences(of: " ", with: "_")
    }

    static func preferredVoice(for speech: CardSound.Speech) -> AVSpeechSynthesisVoice? {
        let language = speech.language.replacingOccurrences(of: "_", with: "-")
        if !speech.voices.isEmpty {
            let voices = AVSpeechSynthesisVoice.speechVoices()
            for requested in speech.voices {
                if let voice = voices.first(where: {
                    requested == $0.identifier || requested == $0.name
                        || requested == templateName($0)
                        || requested == $0.name.replacingOccurrences(of: " ", with: "_")
                }) {
                    return voice
                }
            }
        }
        return AVSpeechSynthesisVoice(language: language)
    }
}
#endif
