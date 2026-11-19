import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why an image could not be attached.
public enum AttachImageError: Error, Equatable, LocalizedError {
    /// The data is not an image the system can read.
    case notAnImage
    /// The core could not store the file in the collection's media.
    case notStored(message: String)

    public var errorDescription: String? {
        switch self {
        case .notAnImage: String(localized: "Choose a readable image.", bundle: .module)
        case .notStored(let message): message
        }
    }
}

/// An image prepared for the collection's media: in a format every Anki
/// client shows, without the location the photo was taken at, and named as
/// desktop Anki names pasted images (`paste-` and a hash of the contents).
struct ImageMedia {
    let data: Data
    let fileName: String
    let mimeType: String

    /// Formats card web views on every platform show, kept as they are.
    private static let keptFormats: [UTType] = [.jpeg, .png, .gif, .webP]

    init?(data original: Data, asPNG: Bool = false) {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let format = UTType(identifier as String),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        let output: (data: Data, format: UTType)
        if asPNG && format != .png {
            guard let png = Self.convert(source, to: .png) else { return nil }
            output = (png, .png)
        } else if Self.keptFormats.contains(format) {
            output = (Self.withoutLocation(source, format: format) ?? original, format)
        } else if let jpeg = Self.convert(source, to: .jpeg) {
            output = (jpeg, .jpeg)
        } else {
            return nil
        }
        data = output.data
        mimeType = output.format.preferredMIMEType ?? "image/jpeg"
        let hash = Insecure.SHA1.hash(data: output.data).map { String(format: "%02x", $0) }.joined()
        let fileExtension = output.format == .jpeg ? "jpg" : output.format.preferredFilenameExtension ?? "jpg"
        fileName = "paste-\(hash).\(fileExtension)"
    }

    /// Applies the oriented preview's crop to the full-resolution image.
    @concurrent
    static func cropped(_ original: Data, to rect: CGRect) async throws -> Data {
        let rect = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !rect.isNull, !rect.isEmpty,
              let source = CGImageSourceCreateWithData(original as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              ] as CFDictionary) else { throw AttachImageError.notAnImage }
        let pixelRect = CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                               width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height)).integral
        guard let cropped = image.cropping(to: pixelRect) else { throw AttachImageError.notAnImage }
        let format = CGImageSourceGetType(source) as String? == UTType.jpeg.identifier ? UTType.jpeg : .png
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.identifier as CFString, 1, nil)
        else { throw AttachImageError.notAnImage }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else { throw AttachImageError.notAnImage }
        return output as Data
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

    private static func convert(_ source: CGImageSource, to format: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.identifier as CFString, 1, nil)
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
