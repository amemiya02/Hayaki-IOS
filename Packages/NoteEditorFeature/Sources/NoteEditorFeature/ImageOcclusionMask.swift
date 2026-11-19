import AnkiProto
import Foundation

/// Coordinates are relative to the oriented image, from zero to one.
public struct ImageOcclusionMask: Equatable, Identifiable, Sendable {
    typealias Shape = Anki_ImageOcclusion_GetImageOcclusionNoteResponse.ImageOcclusionShape

    public let id = UUID()
    public internal(set) var ordinal: UInt32
    public var kind: String { shape.shape }
    public var label: String { value("text") ?? "" }
    var shape: Shape

    init(ordinal: UInt32, shape: Shape) {
        self.ordinal = ordinal
        self.shape = shape
    }

    init(ordinal: UInt32, rect: CGRect) {
        self.init(ordinal: ordinal, shape: .with { $0.shape = "rect" })
        setRect(rect)
    }

    func value(_ key: String) -> String? {
        shape.properties.first(where: { $0.name == key })?.value
    }

    func number(_ key: String) -> CGFloat { CGFloat(Double(value(key) ?? "") ?? 0) }

    mutating func set(_ key: String, _ value: String) {
        if let index = shape.properties.firstIndex(where: { $0.name == key }) {
            shape.properties[index].value = value
        } else {
            shape.properties.append(.with { $0.name = key; $0.value = value })
        }
    }

    mutating func set(_ key: String, _ value: CGFloat) {
        set(key, String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Double(value)))
    }

    mutating func setRect(_ rect: CGRect) {
        set("left", rect.minX)
        set("top", rect.minY)
        set("width", rect.width)
        set("height", rect.height)
    }

    func cloze(occludeInactive: Bool) -> String {
        var properties = shape.properties.filter { $0.name != "oi" }
        if occludeInactive { properties.append(.with { $0.name = "oi"; $0.value = "1" }) }
        let values = properties.map { property in
            let escaped = property.value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ":", with: "\\:")
            return ":\(property.name)=\(escaped)"
        }.joined()
        return "{{c\(ordinal)::image-occlusion:\(kind)\(values)}}<br>"
    }
}
