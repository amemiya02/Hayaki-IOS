#if os(iOS)
import AVFoundation
import OSLog
import Synchronization

/// Plays a card's audio natively, one sound after another: files from the
/// media folder with AVFoundation and text to speech with the system's
/// speech synthesizer. Starting new audio stops whatever was playing, as
/// turning a card over or tapping a replay button does in Anki.
@MainActor
final class CardAudioPlayer {
    private var queue: Task<Void, Never>?
    private var player: AVPlayer?
    /// Ends the sound now playing early, when the player is stopped.
    private var currentEnd: PlaybackEnd?
    private let synthesizer = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate()

    init() {
        synthesizer.delegate = speechDelegate
    }

    /// Stops what is playing and plays `sounds` in order.
    func play(_ sounds: [CardSound]) {
        stop()
        guard !sounds.isEmpty else { return }
        queue = Task { [weak self] in
            self?.activateSession()
            for sound in sounds {
                guard let self, !Task.isCancelled else { return }
                await self.playOne(sound)
            }
            guard let self, !Task.isCancelled else { return }
            self.deactivateSession()
        }
    }

    func stop() {
        queue?.cancel()
        queue = nil
        player?.pause()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentEnd?.signal()
        currentEnd = nil
    }

    private func playOne(_ sound: CardSound) async {
        let end = PlaybackEnd()
        currentEnd = end
        switch sound {
        case .file(let url):
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            let center = NotificationCenter.default
            let observers = [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification]
                .map { center.addObserver(forName: $0, object: item, queue: nil) { _ in end.signal() } }
            // A file that is missing or cannot be decoded is skipped.
            let status = item.observe(\.status, options: [.initial, .new]) { item, _ in
                if item.status == .failed {
                    Self.log.error("A card's sound could not be played: \(item.error?.localizedDescription ?? "", privacy: .public)")
                    end.signal()
                }
            }
            player.play()
            await end.wait()
            observers.forEach(center.removeObserver)
            status.invalidate()
        case .speech(let speech):
            speechDelegate.current.withLock { $0 = end }
            synthesizer.speak(Self.utterance(speech))
            await end.wait()
        }
    }

    private static func utterance(_ speech: CardSound.Speech) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: speech.text)
        let language = speech.language.replacingOccurrences(of: "_", with: "-")
        let voices = AVSpeechSynthesisVoice.speechVoices()
        utterance.voice = voices.first { speech.voices.contains($0.name) || speech.voices.contains($0.identifier) }
            ?? AVSpeechSynthesisVoice(language: language)
        let speed = speech.speed > 0 ? speech.speed : 1
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * speed, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        return utterance
    }

    /// Card audio plays even with the ring/silent switch on silent, as the
    /// learner asked for it by studying, and lowers other apps' audio while
    /// it plays.
    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.log.error("The audio session could not start: \(error, privacy: .public)")
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static let log = Logger(subsystem: "io.github.amemiya02.hayaki", category: "CardAudioPlayer")
}

/// The end of one sound: signalled once, by whichever comes first of the
/// sound ending, failing or being stopped.
private final class PlaybackEnd: Sendable {
    private struct State {
        var ended = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func signal() {
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.ended = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let ended = state.withLock { state in
                if !state.ended { state.waiter = continuation }
                return state.ended
            }
            if ended { continuation.resume() }
        }
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, Sendable {
    let current = Mutex<PlaybackEnd?>(nil)

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        current.withLock { $0?.signal() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        current.withLock { $0?.signal() }
    }
}
#endif
