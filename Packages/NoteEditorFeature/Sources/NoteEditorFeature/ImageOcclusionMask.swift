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

    init(ordinal: UInt32, rect: CGRect, ellipse: Bool) {
        self.init(ordinal: ordinal, shape: .with { $0.shape = ellipse ? "ellipse" : "rect" })
        setRect(rect)
    }

    init(ordinal: UInt32, points: [CGPoint]) {
        self.init(ordinal: ordinal, shape: .with { $0.shape = "polygon" })
        let bounds = Self.bounds(of: points)
        set("left", bounds.minX)
        set("top", bounds.minY)
        setPoints(points)
    }

    init(label: String, point: CGPoint) {
        self.init(ordinal: 0, shape: .with { $0.shape = "text" })
        set("left", point.x)
        set("top", point.y)
        set("text", label)
        set("scale", 1)
        set("fs", 0.06)
    }

    var rect: CGRect {
        let origin = CGPoint(x: number("left"), y: number("top"))
        let size = switch kind {
        case "ellipse": CGSize(width: number("rx") * 2, height: number("ry") * 2)
        case "polygon": Self.bounds(of: rawPolygon).size
        case "text":
            CGSize(width: min(0.4, max(0.06, CGFloat(label.count) * 0.032)) * max(0.1, number("scale")),
                   height: max(0.06, number("fs")) * max(0.1, number("scale")))
        default: CGSize(width: number("width"), height: number("height"))
        }
        return CGRect(origin: origin, size: size)
    }

    var polygon: [CGPoint] {
        let points = rawPolygon
        let bounds = Self.bounds(of: points)
        return points.map { CGPoint(x: $0.x + number("left") - bounds.minX,
                                    y: $0.y + number("top") - bounds.minY) }
    }

    private var rawPolygon: [CGPoint] {
        (value("points") ?? "").split(separator: " ").compactMap { point in
            let coords = point.split(separator: ",")
            guard coords.count == 2, let x = Double(coords[0]), let y = Double(coords[1]),
                  x.isFinite, y.isFinite else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var bounds = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() { bounds = bounds.union(CGRect(origin: point, size: .zero)) }
        return bounds
    }

    func value(_ key: String) -> String? {
        shape.properties.first(where: { $0.name == key })?.value
    }

    func number(_ key: String) -> CGFloat {
        guard let number = Double(value(key) ?? ""), number.isFinite else { return 0 }
        return CGFloat(number)
    }

    mutating func set(_ key: String, _ value: String) {
        if let index = shape.properties.firstIndex(where: { $0.name == key }) {
            shape.properties[index].value = value
        } else {
            shape.properties.append(.with { $0.name = key; $0.value = value })
        }
    }

    mutating func set(_ key: String, _ value: CGFloat) {
        set(key, Self.formatted(value))
    }

    mutating func setRect(_ rect: CGRect) {
        let previous = self.rect
        let points = polygon
        set("left", rect.minX)
        set("top", rect.minY)
        switch kind {
        case "ellipse":
            set("rx", rect.width / 2)
            set("ry", rect.height / 2)
        case "polygon":
            guard previous.width > 0, previous.height > 0 else { return }
            setPoints(points.map {
                CGPoint(x: rect.minX + ($0.x - previous.minX) / previous.width * rect.width,
                        y: rect.minY + ($0.y - previous.minY) / previous.height * rect.height)
            })
        case "text":
            let scale = max(0.1, number("scale"))
            set("scale", scale * rect.height / previous.height)
        default:
            set("width", rect.width)
            set("height", rect.height)
        }
    }

    private mutating func setPoints(_ points: [CGPoint]) {
        set("points", points.map { "\(Self.formatted($0.x)),\(Self.formatted($0.y))" }.joined(separator: " "))
    }

    private static func formatted(_ value: CGFloat) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
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
