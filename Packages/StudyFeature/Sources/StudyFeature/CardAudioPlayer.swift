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
    private var pending: [CardSound] = []
    private var player: AVPlayer?
    /// Ends the sound now playing early, when the player is stopped.
    private var currentEnd: PlaybackEnd?
    private let synthesizer = AVSpeechSynthesizer()
    private let speechDelegate = SpeechDelegate()
    /// Whether this player activated the audio session and has not released it.
    private var holdsSession = false
    /// Where the audio session is activated and released, in order, off the
    /// main thread: releasing it right after stopping a sound blocks until
    /// the audio hardware has stopped, which takes more than half a second.
    nonisolated private static let sessionQueue = DispatchQueue(label: "io.github.amemiya02.hayaki.card-audio-session")

    init() {
        synthesizer.delegate = speechDelegate
    }

    /// Plays the sounds in order, optionally after sounds already queued for the question.
    ///
    /// Moving on to new sounds keeps the audio session active, so turning the
    /// card over or going to the next card while a sound plays does not wait
    /// for the session to be released.
    func play(_ sounds: [CardSound], afterCurrent: Bool = false) {
        if !afterCurrent { stopPlaying() }
        guard !sounds.isEmpty else {
            if queue == nil { releaseSession() }
            return
        }
        pending.append(contentsOf: sounds)
        guard queue == nil else { return }
        queue = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            activateSession()
            while !pending.isEmpty, !Task.isCancelled {
                let sound = pending.removeFirst()
                await playOne(sound)
            }
            guard !Task.isCancelled else { return }
            queue = nil
            currentEnd = nil
            player = nil
            releaseSession()
        }
    }

    func waitForCompletion() async {
        await queue?.value
    }

    /// Stops the audio and releases the audio session in the background.
    func stop() {
        stopPlaying()
        releaseSession()
    }

    /// Stops the audio and releases the audio session before returning, for
    /// a recorder or recognizer that sets up the session itself next.
    func stopAndReleaseSession() {
        stopPlaying()
        releaseSession(waiting: true)
    }

    private func stopPlaying() {
        queue?.cancel()
        queue = nil
        pending.removeAll()
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
        utterance.voice = CardSpeechVoice.preferredVoice(for: speech)
        let speed = speech.speed > 0 ? speech.speed : 1
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * speed, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)
        return utterance
    }

    /// Card audio plays even with the ring/silent switch on silent, as the
    /// learner asked for it by studying, and lowers other apps' audio while
    /// it plays.
    private func activateSession() {
        holdsSession = true
        do {
            try Self.sessionQueue.sync {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try session.setActive(true)
            }
        } catch {
            Self.log.error("The audio session could not start: \(error, privacy: .public)")
        }
    }

    private func releaseSession(waiting: Bool = false) {
        guard holdsSession else { return }
        holdsSession = false
        let release: @Sendable () -> Void = {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        if waiting {
            Self.sessionQueue.sync(execute: release)
        } else {
            Self.sessionQueue.async(execute: release)
        }
    }

    nonisolated private static let log = Logger(subsystem: "io.github.amemiya02.hayaki", category: "CardAudioPlayer")
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
