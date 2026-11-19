#if os(iOS)
import Observation
import PencilKit
import SwiftUI

@MainActor
@Observable
final class ReviewerDrawing {
    @ObservationIgnored let canvas = WhiteboardCanvas()
    private(set) var hasInk = false
    private(set) var canUndo = false
    private(set) var canRedo = false

    func refresh() {
        hasInk = !canvas.drawing.strokes.isEmpty
        canUndo = canvas.undoManager?.canUndo == true
        canRedo = canvas.undoManager?.canRedo == true
    }

    func clear() {
        canvas.drawing = PKDrawing()
        canvas.undoManager?.removeAllActions()
        refresh()
    }

    func save() throws -> URL {
        let drawing = canvas.drawing
        guard !drawing.strokes.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let exportBounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        let scale = min(2, 4096 / max(exportBounds.width, exportBounds.height))
        guard let png = drawing.image(from: exportBounds, scale: scale).pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let folder = URL.documentsDirectory.appending(path: "Whiteboard", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Whiteboard-\(UUID().uuidString).png")
        try png.write(to: url, options: .atomic)
        return url
    }
}

/// Finger input remains available to the card while Apple Pencil is selected.
final class WhiteboardCanvas: PKCanvasView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if drawingPolicy == .pencilOnly, let event,
           event.type == .touches, event.allTouches?.contains(where: { $0.type == .pencil }) != true {
            return false
        }
        return super.point(inside: point, with: event)
    }
}

struct ReviewerWhiteboard: UIViewRepresentable {
    let drawing: ReviewerDrawing
    let tools: ReviewerDeckTools
    let isErasing: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(drawing: drawing) }

    func makeUIView(context: Context) -> WhiteboardCanvas {
        let canvas = drawing.canvas
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        canvas.accessibilityLabel = String(localized: "Whiteboard", bundle: .module)
        return canvas
    }

    func updateUIView(_ canvas: WhiteboardCanvas, context: Context) {
        canvas.drawingPolicy = tools.stylusOnly ? .pencilOnly : .anyInput
        if isErasing {
            canvas.tool = PKEraserTool(tools.strokeEraser ? .vector : .bitmap, width: tools.eraserWidth)
        } else {
            let rgba = UInt32(tools.penColor, radix: 16)
            let color = rgba.map {
                UIColor(
                    red: CGFloat(($0 >> 16) & 255) / 255,
                    green: CGFloat(($0 >> 8) & 255) / 255,
                    blue: CGFloat($0 & 255) / 255,
                    alpha: 1
                )
            } ?? (colorScheme == .dark ? UIColor.white : .black)
            canvas.tool = PKInkingTool(.pen, color: color, width: tools.penWidth)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let drawing: ReviewerDrawing

        init(drawing: ReviewerDrawing) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing.refresh() }
    }
}

struct ReviewerWhiteboardTools: View {
    let drawing: ReviewerDrawing
    @Binding var options: ReviewerDeckTools
    @Binding var isErasing: Bool
    @State private var saved: URL?
    @State private var saveError: String?
    @State private var showSavedFile = false

    var body: some View {
        HStack(spacing: 16) {
            Button(
                options.drawingShown ? "Hide Drawing" : "Show Drawing",
                systemImage: options.drawingShown ? "eye.slash" : "eye"
            ) { options.drawingShown.toggle() }
            if options.drawingShown {
                Button("Pen", systemImage: "pencil") { isErasing = false }
                    .foregroundStyle(isErasing ? Color.primary : Color.accentColor)
                Button("Eraser", systemImage: "eraser") { isErasing = true }
                    .foregroundStyle(isErasing ? Color.accentColor : Color.primary)
                Button("Undo Stroke", systemImage: "arrow.uturn.backward") { drawing.canvas.undoManager?.undo() }
                    .disabled(!drawing.canUndo)
                Menu {
                    Button("Redo Stroke", systemImage: "arrow.uturn.forward") { drawing.canvas.undoManager?.redo() }
                        .disabled(!drawing.canRedo)
                    Button("Clear Drawing", systemImage: "trash", role: .destructive) { drawing.clear() }
                        .disabled(!drawing.hasInk)
                    ColorPicker("Pen Color", selection: penColor, supportsOpacity: false)
                    Button("Automatic Pen Color") { options.penColor = "automatic" }
                    Picker("Pen Width", selection: $options.penWidth) {
                        ForEach([2.0, 4.0, 8.0, 12.0], id: \.self) { Text($0, format: .number).tag($0) }
                    }
                    Picker("Eraser Width", selection: $options.eraserWidth) {
                        ForEach([12.0, 24.0, 36.0, 48.0], id: \.self) { Text($0, format: .number).tag($0) }
                    }
                    Toggle("Erase Whole Strokes", isOn: $options.strokeEraser)
                    Toggle("Apple Pencil Only", isOn: $options.stylusOnly)
                    Toggle("Tools at Top", isOn: $options.toolbarTop)
                } label: {
                    Label("Whiteboard Tools", systemImage: "ellipsis.circle")
                }
            }
            Button("Save Drawing", systemImage: "square.and.arrow.down") {
                do {
                    saved = try drawing.save()
                    showSavedFile = true
                } catch {
                    saveError = error.localizedDescription
                }
            }
            .disabled(!drawing.hasInk)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .alert("Drawing Saved", isPresented: $showSavedFile) {
            Button("OK", role: .cancel) {}
        } message: {
            if let saved { Text("Files → On My iPhone or iPad → Hayaki → Whiteboard → \(saved.lastPathComponent)") }
        }
        .alert("Could Not Save Drawing", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: saveError ?? "")
        }
    }

    private var penColor: Binding<Color> {
        Binding {
            Color(uiColor: UIColor(hexRGB: options.penColor) ?? .label)
        } set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            options.penColor = String(format: "%02x%02x%02x", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
    }
}

private extension UIColor {
    convenience init?(hexRGB: String) {
        guard let value = UInt32(hexRGB, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255,
            alpha: 1
        )
    }
}
#endif
