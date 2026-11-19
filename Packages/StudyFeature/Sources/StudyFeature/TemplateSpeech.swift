#if os(iOS)
import AVFoundation
import Foundation

@MainActor
final class TemplateSpeech {
    private var synthesizer: AVSpeechSynthesizer?
    private var voice: AVSpeechSynthesisVoice?
    private var rate: Float = 1
    private var pitch: Float = 1

    func handle(_ request: TemplateRequest, prepareAudio: () -> Void) -> TemplateReply? {
        switch request.command {
        case "ttsFieldModifierIsAvailable": return .value(.boolean(false))
        case "ttsIsSpeaking": return .value(.boolean(synthesizer?.isSpeaking == true))
        case "ttsStop":
            stop()
            return status(0)
        case "ttsSetLanguage":
            guard let locale = request.data, !locale.isEmpty else { return status(-2) }
            let language = locale.replacingOccurrences(of: "_", with: "-")
            guard let candidate = AVSpeechSynthesisVoice(language: language) else { return status(-2) }
            voice = candidate
            return status(language.contains("-") ? 1 : 0)
        case "ttsSetPitch":
            guard let value = positiveNumber(request.data) else { return status(-1) }
            pitch = min(max(value, 0.5), 2)
            return status(0)
        case "ttsSetSpeechRate":
            guard let value = positiveNumber(request.data) else { return status(-1) }
            rate = value
            return status(0)
        case "ttsSpeak":
            guard let body = request.data?.data(using: .utf8),
                  let input = try? JSONDecoder().decode(SpeechInput.self, from: body),
                  !input.text.isEmpty, [0, 1].contains(input.queueMode)
            else { return status(-1) }
            prepareAudio()
            if input.queueMode == 0 { stop() }
            let synthesizer = synthesizer ?? AVSpeechSynthesizer()
            self.synthesizer = synthesizer
            let utterance = AVSpeechUtterance(string: input.text)
            utterance.voice = voice
            utterance.pitchMultiplier = pitch
            utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * rate, AVSpeechUtteranceMinimumSpeechRate),
                                 AVSpeechUtteranceMaximumSpeechRate)
            synthesizer.speak(utterance)
            return status(0)
        default: return nil
        }
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
    }

    private func positiveNumber(_ text: String?) -> Float? {
        guard let text, let value = Float(text), value.isFinite, value > 0 else { return nil }
        return value
    }

    private func status(_ code: Int64) -> TemplateReply {
        .value(.integer(code))
    }

    private struct SpeechInput: Decodable {
        let text: String
        let queueMode: Int
    }
}
#endif
