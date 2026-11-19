#if os(iOS)
import AVFoundation
import Foundation
import Observation

/// A temporary recording that can be replayed in the reviewer or copied into a
/// note's media by the caller. Dismissing its owner calls `discard()`.
@MainActor
@Observable
public final class AudioRecorder: NSObject {
    public enum State: Equatable, Sendable {
        case idle
        case requestingPermission
        case recording
        case paused
        case recorded
        case playing
    }

    public private(set) var state: State = .idle
    public private(set) var file: URL?
    public private(set) var errorMessage: String?
    public private(set) var permissionDenied = false
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var interruptions: Task<Void, Never>?

    public override init() {
        super.init()
        interruptions = Task { [weak self] in
            let types = NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ).compactMap { notification in
                notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            }
            for await type in types where type == AVAudioSession.InterruptionType.began.rawValue {
                self?.interrupted()
            }
        }
    }

    deinit {
        interruptions?.cancel()
    }

    public var elapsed: TimeInterval {
        switch state {
        case .recording, .paused: recorder?.currentTime ?? 0
        case .playing: player?.currentTime ?? 0
        default: 0
        }
    }

    public func record() async {
        guard state != .requestingPermission, state != .recording, state != .paused else { return }
        clearError()
        let id = UUID()
        requestID = id
        let fallback: State = file == nil ? .idle : .recorded
        stopPlayback()
        state = .requestingPermission
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard requestID == id else { return }
        requestID = nil
        guard permitted else {
            state = fallback
            permissionDenied = true
            errorMessage = String(localized: "Allow microphone access in Settings to record your voice.", bundle: .module)
            return
        }

        let session = AVAudioSession.sharedInstance()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recording = try AVAudioRecorder(url: url, settings: settings)
            recording.delegate = self
            guard recording.record() else { throw RecordingError.couldNotStart }
            if let existing = file { try? FileManager.default.removeItem(at: existing) }
            file = nil
            recorder = recording
            state = .recording
        } catch {
            try? FileManager.default.removeItem(at: url)
            deactivateSession()
            state = fallback
            errorMessage = error.localizedDescription
        }
    }

    public func pause() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            guard recorder?.record() == true else { throw RecordingError.couldNotStart }
            clearError()
            state = .recording
        } catch {
            errorMessage = error.localizedDescription
            stopRecording()
        }
    }

    public func stopRecording() {
        guard let recorder, state == .recording || state == .paused else { return }
        recorder.stop()
        completeRecording(recorder, succeeded: true)
    }

    public func play() {
        guard let file, state == .recorded || state == .playing else { return }
        stopPlayback()
        clearError()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let playback = try AVAudioPlayer(contentsOf: file)
            playback.delegate = self
            guard playback.play() else { throw RecordingError.couldNotPlay }
            player = playback
            state = .playing
        } catch {
            deactivateSession()
            errorMessage = error.localizedDescription
        }
    }

    public func stopPlayback() {
        guard let player else { return }
        player.stop()
        self.player = nil
        state = file == nil ? .idle : .recorded
        deactivateSession()
    }

    public func clearError() {
        errorMessage = nil
        permissionDenied = false
    }

    public func discard() {
        requestID = nil
        if let recorder {
            recorder.stop()
            try? FileManager.default.removeItem(at: recorder.url)
            self.recorder = nil
            deactivateSession()
        }
        stopPlayback()
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        state = .idle
        clearError()
    }

    private func interrupted() {
        switch state {
        case .recording, .paused: stopRecording()
        case .playing: stopPlayback()
        default: break
        }
    }

    private func completeRecording(_ recorder: AVAudioRecorder, succeeded: Bool) {
        guard self.recorder === recorder else { return }
        self.recorder = nil
        deactivateSession()
        if succeeded, (try? recorder.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 {
            file = recorder.url
            state = .recorded
        } else {
            try? FileManager.default.removeItem(at: recorder.url)
            state = .idle
            if errorMessage == nil {
                errorMessage = String(localized: "The recording could not be saved.", bundle: .module)
            }
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    nonisolated public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor in
            guard let recorder = self.recorder, ObjectIdentifier(recorder) == identity else { return }
            completeRecording(recorder, succeeded: flag)
        }
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor in
            guard let player = self.player, ObjectIdentifier(player) == identity else { return }
            stopPlayback()
        }
    }
}

private enum RecordingError: LocalizedError {
    case couldNotStart, couldNotPlay

    var errorDescription: String? {
        switch self {
        case .couldNotStart: String(localized: "The microphone could not start recording.", bundle: .module)
        case .couldNotPlay: String(localized: "The recording could not play.", bundle: .module)
        }
    }
}
#endif
