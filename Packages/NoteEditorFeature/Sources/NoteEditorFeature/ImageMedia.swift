import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why an image could not be attached.
public enum AttachImageError: Error, Equatable {
    /// The data is not an image the system can read.
    case notAnImage
    /// The core could not store the file in the collection's media.
    case notStored(message: String)
}

/// An image prepared for the collection's media: in a format every Anki
/// client shows, without the location the photo was taken at, and named as
/// desktop Anki names pasted images (`paste-` and a hash of the contents).
struct ImageMedia {
    let data: Data
    let fileName: String

    /// Formats card web views on every platform show, kept as they are.
    private static let keptFormats: [UTType] = [.jpeg, .png, .gif, .webP]

    init?(data original: Data) {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let format = UTType(identifier as String),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        let output: (data: Data, format: UTType)
        if Self.keptFormats.contains(format) {
            output = (Self.withoutLocation(source, format: format) ?? original, format)
        } else if let jpeg = Self.jpeg(from: source) {
            output = (jpeg, .jpeg)
        } else {
            return nil
        }
        data = output.data
        let hash = Insecure.SHA1.hash(data: output.data).map { String(format: "%02x", $0) }.joined()
        let fileExtension = output.format == .jpeg ? "jpg" : output.format.preferredFilenameExtension ?? "jpg"
        fileName = "paste-\(hash).\(fileExtension)"
    }

    /// The image re-written without its GPS metadata, losslessly. Nil for
    /// formats ImageIO cannot copy this way (then the original is kept).
    private static func withoutLocation(_ source: CGImageSource, format: UTType) -> Data? {
        guard format == .jpeg || format == .png else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageMetadataShouldExcludeGPS: true] as CFDictionary
        guard CGImageDestinationCopyImageSource(destination, source, options, nil) else { return nil }
        return output as Data
    }

    /// The first image of `source` as a JPEG, keeping its orientation but
    /// not its location.
    private static func jpeg(from source: CGImageSource) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyGPSDictionary: kCFNull as Any,
        ] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
