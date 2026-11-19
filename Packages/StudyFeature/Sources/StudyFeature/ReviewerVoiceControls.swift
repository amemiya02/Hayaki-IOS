#if os(iOS)
import SwiftUI

struct ReviewerVoiceControls: View {
    let recorder: AudioRecorder
    let stopCardAudio: () -> Void

    var body: some View {
        HStack {
            switch recorder.state {
            case .requestingPermission:
                ProgressView()
            case .recording, .paused:
                Button(
                    recorder.state == .recording ? "Pause Recording" : "Resume Recording",
                    systemImage: recorder.state == .recording ? "pause.circle" : "mic.circle"
                ) {
                    if recorder.state == .recording { recorder.pause() } else { recorder.resume() }
                }
                Button("Stop Recording", systemImage: "stop.circle") { recorder.stopRecording() }
            default:
                Button("Record Voice", systemImage: "mic.circle") {
                    stopCardAudio()
                    Task { await recorder.record() }
                }
                Button(
                    recorder.state == .playing ? "Stop Replay" : "Replay Voice",
                    systemImage: recorder.state == .playing ? "stop.circle" : "play.circle"
                ) {
                    stopCardAudio()
                    if recorder.state == .playing { recorder.stopPlayback() } else { recorder.play() }
                }
                .disabled(recorder.file == nil)
            }
            if [.recording, .paused, .playing].contains(recorder.state) {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let seconds = max(0, Int(recorder.elapsed))
                    Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                }
            }
        }
        .font(.title3)
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
    }
}
#endif
