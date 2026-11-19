import Foundation
import ImageIO
import PencilKit
import UniformTypeIdentifiers

/// Renders a drawing alone, preserving its transparency, and writes it in Files.
@MainActor
public enum WhiteboardExport {
    public static func save(_ drawing: PKDrawing, in documents: URL = .documentsDirectory) throws -> URL {
        guard !drawing.strokes.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let exportBounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        let scale = min(2, 4096 / max(exportBounds.width, exportBounds.height))
        let image = drawing.image(from: exportBounds, scale: scale)
        #if os(iOS)
        let bitmap = image.cgImage
        #else
        let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let bitmap else { throw CocoaError(.fileWriteUnknown) }
        let png = NSMutableData()
        guard let renderer = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(renderer, bitmap, nil)
        guard CGImageDestinationFinalize(renderer) else { throw CocoaError(.fileWriteUnknown) }

        let folder = documents.appending(path: "Whiteboard", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Whiteboard-\(UUID().uuidString).png")
        try (png as Data).write(to: url, options: .atomic)
        return url
    }
}
