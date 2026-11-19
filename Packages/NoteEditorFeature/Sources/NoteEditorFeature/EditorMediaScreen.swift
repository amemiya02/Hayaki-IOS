#if os(iOS)
import AVFoundation
import AVKit
import PencilKit
import StudyFeature
import SwiftUI
import UIKit

struct EditorRecordingScreen: View {
    let accept: (URL) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var recorder = AudioRecorder()
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(recorder.state == .recording ? Color.red : Color.accentColor)
                    .accessibilityHidden(true)
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.largeTitle.monospacedDigit())
                }
                controls
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text("Record Audio", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let file = recorder.file else { return }
                        saving = true
                        recorder.stopPlayback()
                        Task {
                            defer { saving = false }
                            do {
                                try await accept(file)
                                dismiss()
                            } catch {
                                failure = error.localizedDescription
                            }
                        }
                    } label: {
                        Text("Use Recording", bundle: .module)
                    }
                    .disabled(recorder.file == nil || saving || recorder.state == .requestingPermission)
                }
            }
            .alert(Text("Could Not Record Audio", bundle: .module), isPresented: Binding(
                get: { recorder.errorMessage != nil || failure != nil },
                set: { if !$0 { recorder.clearError(); failure = nil } }
            )) {
                if recorder.permissionDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button { openURL(settings) } label: { Text("Open Settings", bundle: .module) }
                }
                Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
            } message: {
                Text(failure ?? recorder.errorMessage ?? "")
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .onDisappear { recorder.discard() }
    }

    private var controls: some View {
        HStack {
            switch recorder.state {
            case .idle, .recorded, .playing:
                Button {
                    Task { await recorder.record() }
                } label: {
                    Label { Text("Record", bundle: .module) } icon: { Image(systemName: "record.circle") }
                }
                if recorder.file != nil {
                    Button {
                        if recorder.state == .playing { recorder.stopPlayback() }
                        else { recorder.play() }
                    } label: {
                        if recorder.state == .playing {
                            Label { Text("Stop Replay", bundle: .module) } icon: { Image(systemName: "stop.fill") }
                        } else {
                            Label { Text("Replay", bundle: .module) } icon: { Image(systemName: "play.fill") }
                        }
                    }
                }
            case .requestingPermission:
                ProgressView()
            case .recording, .paused:
                Button {
                    if recorder.state == .paused { recorder.resume() }
                    else { recorder.pause() }
                } label: {
                    if recorder.state == .paused {
                        Label { Text("Resume", bundle: .module) } icon: { Image(systemName: "record.circle") }
                    } else {
                        Label { Text("Pause", bundle: .module) } icon: { Image(systemName: "pause.fill") }
                    }
                }
                Button {
                    recorder.stopRecording()
                } label: {
                    Label { Text("Stop", bundle: .module) } icon: { Image(systemName: "stop.fill") }
                }
            }
        }
        .buttonStyle(.bordered)
    }
}

struct EditorMediaPlayback: View {
    let file: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .navigationTitle(file.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
                .task {
                    let player = AVPlayer(url: file)
                    self.player = player
                    player.play()
                }
                .onDisappear {
                    player?.pause()
                    player = nil
                }
        }
    }
}

struct EditorMediaImage: View {
    let data: Data
    let existing: Bool
    let accept: (Data, CGRect?) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var cropping = false
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack {
                if let image {
                    if cropping {
                        EditorCropCanvas(image: image, crop: $crop)
                            .padding()
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(Text("Image Preview", bundle: .module))
                            .padding()
                    }
                } else {
                    ContentUnavailableView {
                        Label { Text("Could Not Open the Image", bundle: .module) } icon: { Image(systemName: "photo") }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle(cropping ? Text("Crop Image", bundle: .module) : Text("Image Preview", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !cropping {
                        Button {
                            cropping = true
                        } label: {
                            Label { Text("Crop Image", bundle: .module) } icon: { Image(systemName: "crop") }
                        }
                        .disabled(image == nil)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if cropping || !existing {
                        Button {
                            saving = true
                            Task {
                                defer { saving = false }
                                do {
                                    try await accept(data, cropping ? crop : nil)
                                    dismiss()
                                } catch {
                                    failure = error.localizedDescription
                                }
                            }
                        } label: {
                            if existing { Text("Save", bundle: .module) }
                            else { Text("Use Image", bundle: .module) }
                        }
                        .disabled(image == nil)
                    }
                }
            }
            .alert(Text("Could Not Save the Image", bundle: .module), isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } }
            )) {
                Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
            } message: {
                Text(failure ?? "")
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .task { image = UIImage(data: data) }
    }
}

private struct EditorCropCanvas: View {
    let image: UIImage
    @Binding var crop: CGRect

    var body: some View {
        GeometryReader { geometry in
            let ratio = image.size.width / image.size.height
            let width = min(geometry.size.width, geometry.size.height * ratio)
            let size = CGSize(width: width, height: width / ratio)
            Image(uiImage: image).resizable()
                .frame(width: size.width, height: size.height)
                .overlay {
                    Canvas { context, _ in
                        var shade = Path(CGRect(origin: .zero, size: size))
                        shade.addRect(CGRect(x: crop.minX * size.width, y: crop.minY * size.height,
                                             width: crop.width * size.width, height: crop.height * size.height))
                        context.fill(shade, with: .color(.black.opacity(0.6)), style: FillStyle(eoFill: true))
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    ForEach(Corner.allCases, id: \.self) { corner in
                        handle(corner, size: size)
                    }
                }
                .coordinateSpace(.named("image-crop"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
    }

    private func handle(_ corner: Corner, size: CGSize) -> some View {
        let x = corner.isLeft ? crop.minX : crop.maxX
        let y = corner.isTop ? crop.minY : crop.maxY
        return Circle()
            .fill(.white)
            .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
            .frame(width: 18, height: 18)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .position(x: x * size.width, y: y * size.height)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("image-crop")).onChanged { gesture in
                let x = min(1, max(0, gesture.location.x / size.width))
                let y = min(1, max(0, gesture.location.y / size.height))
                let left = corner.isLeft ? min(x, crop.maxX - 0.04) : crop.minX
                let right = corner.isLeft ? crop.maxX : max(x, crop.minX + 0.04)
                let top = corner.isTop ? min(y, crop.maxY - 0.04) : crop.minY
                let bottom = corner.isTop ? crop.maxY : max(y, crop.minY + 0.04)
                crop = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            })
    }
}

struct EditorDrawingScreen: View {
    let accept: (Data) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var color = Color.black
    @State private var erasing = false
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DrawingCanvas(canvas: canvas, tool: erasing ? PKEraserTool(.vector) : PKInkingTool(.pen, color: UIColor(color), width: 5))
                HStack {
                    ColorPicker(selection: $color, supportsOpacity: false) {
                        Text("Ink Color", bundle: .module)
                    }
                    Button {
                        erasing.toggle()
                    } label: {
                        Label { Text("Eraser", bundle: .module) } icon: { Image(systemName: "eraser") }
                    }
                    .tint(erasing ? .accentColor : .secondary)
                    Button {
                        canvas.undoManager?.undo()
                    } label: {
                        Label { Text("Undo", bundle: .module) } icon: { Image(systemName: "arrow.uturn.backward") }
                    }
                }
                .padding()
                .labelStyle(.iconOnly)
            }
            .navigationTitle(Text("Drawing", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !canvas.drawing.strokes.isEmpty else {
                            dismiss()
                            return
                        }
                        let bounds = canvas.bounds
                        let drawing = canvas.drawing.image(from: bounds, scale: 2)
                        let image = UIGraphicsImageRenderer(size: bounds.size).image { context in
                            UIColor.white.setFill()
                            context.fill(bounds)
                            drawing.draw(in: bounds)
                        }
                        guard let data = image.pngData() else { return }
                        saving = true
                        Task {
                            defer { saving = false }
                            do {
                                try await accept(data)
                                dismiss()
                            } catch {
                                failure = error.localizedDescription
                            }
                        }
                    } label: {
                        Text("Use Drawing", bundle: .module)
                    }
                }
            }
            .alert(Text("Could Not Save the Drawing", bundle: .module), isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } }
            )) {
                Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
            } message: {
                Text(failure ?? "")
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
    }
}

private struct DrawingCanvas: UIViewRepresentable {
    let canvas: PKCanvasView
    let tool: any PKTool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        view.tool = tool
    }
}

struct EditorCamera: UIViewControllerRepresentable {
    let onImage: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (Data?) -> Void

        init(onImage: @escaping (Data?) -> Void) {
            self.onImage = onImage
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.95))
        }
    }
}
#endif
