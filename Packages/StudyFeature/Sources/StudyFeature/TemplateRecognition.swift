#if os(iOS)
import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
final class TemplateRecognition {
    private var locale = Locale.current
    private var operation: UUID?
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?

    func handle(
        _ command: TemplateRequest, context: CardTemplateContext, allowed: Bool, prepareAudio: () -> Void
    ) async -> TemplateReply? {
        switch command.command {
        case "sttSetLanguage":
            guard let name = command.data, !name.isEmpty else { return .unavailable }
            let candidate = Locale(identifier: name)
            guard SFSpeechRecognizer(locale: candidate) != nil else { return .unavailable }
            locale = candidate
            return .accepted
        case "sttStart":
            guard allowed else {
                context.emit("ankiSttResult", Self.failure("Audio recording is disabled for card templates."))
                return .unavailable
            }
            return await start(context, prepareAudio: prepareAudio) ? .accepted : .unavailable
        case "sttStop":
            let wasActive = operation != nil
            stop()
            return .value(.boolean(wasActive))
        default:
            return nil
        }
    }

    private func start(_ context: CardTemplateContext, prepareAudio: () -> Void) async -> Bool {
        guard operation == nil else { return false }
        let id = UUID()
        operation = id
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        defer {
            if operation == id, engine == nil { operation = nil }
        }
        guard operation == id, context.isCurrent() else { return false }
        guard authorized, await AVAudioApplication.requestRecordPermission() else {
            context.emit("ankiSttResult", Self.failure("Speech recognition or microphone permission was denied."))
            return false
        }
        guard operation == id, context.isCurrent() else { return false }
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            context.emit("ankiSttResult", Self.failure("On-device speech recognition is unavailable for this language."))
            return false
        }

        prepareAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let engine = AVAudioEngine()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                context.emit("ankiSttResult", Self.failure("Microphone input is unavailable."))
                return false
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: Self.tap(for: request))
            self.recognizer = recognizer
            self.engine = engine
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.isFinal == true ? result?.transcriptions.map(\.formattedString) : nil
                let failure = error?.localizedDescription
                guard text != nil || failure != nil else { return }
                Task { @MainActor in
                    guard let self, self.operation == id else { return }
                    self.stop()
                    if let text, let data = try? JSONEncoder().encode(text) {
                        context.emit("ankiSttResult", .value(.text(String(decoding: data, as: UTF8.self))))
                    } else {
                        context.emit("ankiSttResult", Self.failure(failure ?? "Speech recognition failed."))
                    }
                }
            }
            engine.prepare()
            try engine.start()
            timeout = Task {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, operation == id else { return }
                stop()
                context.emit("ankiSttResult", Self.failure("Speech recognition timed out."))
            }
            return true
        } catch {
            stop()
            context.emit("ankiSttResult", Self.failure(error.localizedDescription))
            return false
        }
    }

    private nonisolated static func tap(for request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    func stop() {
        operation = nil
        timeout?.cancel()
        timeout = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        engine = nil
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        recognizer = nil
    }

    private static func failure(_ reason: String) -> TemplateReply {
        TemplateReply(success: false, value: .text(reason))
    }
}
#endif
