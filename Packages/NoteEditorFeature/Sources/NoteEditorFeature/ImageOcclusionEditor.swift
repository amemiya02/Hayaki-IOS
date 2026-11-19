#if os(iOS)
import SwiftUI
import UIKit

struct ImageOcclusionEditor: View {
    let model: NoteEditorModel
    let data: Data
    @State private var image: UIImage?
    @State private var tool = Tool.rectangle
    @State private var selection: Set<UUID> = []
    @State private var drag: CGRect?
    @State private var polygon: [CGPoint] = []
    @State private var textPoint = CGPoint.zero
    @State private var label = ""
    @State private var editingLabelID: UUID?
    @State private var zoom: CGFloat = 1
    @State private var translucent = false
    @State private var fillColor = Color(red: 1, green: 0.92, blue: 0.64)
    @State private var showsFill = false
    @State private var asksForLabel = false
    @State private var undo: [[ImageOcclusionMask]] = []
    @State private var redo: [[ImageOcclusionMask]] = []

    private enum Tool: String, CaseIterable {
        case select, rectangle, ellipse, polygon, text, pan

        var icon: String {
            switch self {
            case .select: "cursorarrow"
            case .rectangle: "rectangle"
            case .ellipse: "oval"
            case .polygon: "pentagon"
            case .text: "textformat"
            case .pan: "hand.draw"
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .select: LocalizedStringResource("Select Mask", bundle: .atURL(Bundle.module.bundleURL))
            case .rectangle: LocalizedStringResource("Rectangle", bundle: .atURL(Bundle.module.bundleURL))
            case .ellipse: LocalizedStringResource("Ellipse", bundle: .atURL(Bundle.module.bundleURL))
            case .polygon: LocalizedStringResource("Polygon", bundle: .atURL(Bundle.module.bundleURL))
            case .text: LocalizedStringResource("Text Label", bundle: .atURL(Bundle.module.bundleURL))
            case .pan: LocalizedStringResource("Pan Image", bundle: .atURL(Bundle.module.bundleURL))
            }
        }
    }

    var body: some View {
        Section {
            if let image {
                canvas(image)
                controls
                if showsFill, !selection.isEmpty {
                    HStack {
                        ColorPicker(selection: $fillColor, supportsOpacity: false) {
                            Text("Mask Color", bundle: .module)
                        }
                        Button {
                            fillSelection()
                            showsFill = false
                        } label: {
                            Text("Apply", bundle: .module)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if tool == .polygon, !polygon.isEmpty {
                    Button {
                        apply { model.addOcclusionPolygon(polygon) }
                        polygon = []
                    } label: {
                        Text("Finish Polygon", bundle: .module)
                    }
                    .disabled(polygon.count < 3)
                }
                if tool == .select, !model.occlusionMasks.isEmpty {
                    Menu {
                        ForEach(Array(model.occlusionMasks.enumerated()), id: \.element.id) { offset, mask in
                            Button {
                                toggle(mask.id)
                            } label: {
                                Label {
                                    Text("Mask \(offset + 1)", bundle: .module)
                                } icon: {
                                    Image(systemName: selection.contains(mask.id) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    } label: {
                        Text("Select Masks", bundle: .module)
                    }
                }
            } else {
                Text("The image could not be displayed.", bundle: .module)
            }
            Toggle(isOn: Binding(get: { model.occludesInactiveMasks }, set: { model.setOccludesInactiveMasks($0) })) {
                Text("Hide All Masks on the Question", bundle: .module)
            }
        } header: {
            Text("Image Occlusion", bundle: .module)
        } footer: {
            switch tool {
            case .select: Text("Tap masks to select them. Drag a mask to move it or drag its lower corner to resize it.", bundle: .module)
            case .rectangle, .ellipse: Text("Drag on the image to draw a mask.", bundle: .module)
            case .polygon: Text("Tap the corners of the mask, then finish the polygon.", bundle: .module)
            case .text: Text("Tap the image to place a label.", bundle: .module)
            case .pan: Text("Drag to pan the zoomed image.", bundle: .module)
            }
        }
        .task(id: data) {
            image = UIImage(data: data)
        }
        .onChange(of: tool) { _, _ in
            polygon = []
            selection = []
        }
        .alert(Text("Text Label", bundle: .module), isPresented: $asksForLabel) {
            TextField(text: $label) { Text("Label", bundle: .module) }
            Button(role: .cancel) {}
            Button {
                if let editingLabelID {
                    apply { model.updateOcclusionLabel(editingLabelID, label: label) }
                } else {
                    apply { model.addOcclusionLabel(label, at: textPoint) }
                }
            } label: {
                if editingLabelID == nil { Text("Add", bundle: .module) }
                else { Text("Save", bundle: .module) }
            }
        }
    }

    private var controls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Tool.allCases, id: \.self) { item in
                    Button {
                        tool = item
                    } label: {
                        Image(systemName: item.icon)
                            .frame(minWidth: 32, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(tool == item ? .accentColor : .secondary)
                    .accessibilityLabel(Text(item.title))
                    .accessibilityAddTraits(tool == item ? .isSelected : [])
                }
                Divider()
                Button {
                    redo.append(model.occlusionMasks)
                    model.setOcclusionMasks(undo.removeLast())
                    selection = []
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel(Text("Undo", bundle: .module))
                .disabled(undo.isEmpty)
                Button {
                    undo.append(model.occlusionMasks)
                    model.setOcclusionMasks(redo.removeLast())
                    selection = []
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .accessibilityLabel(Text("Redo", bundle: .module))
                .disabled(redo.isEmpty)
                Menu {
                    Button {
                        zoom = max(1, zoom / 1.35)
                    } label: { Label { Text("Zoom Out", bundle: .module) } icon: { Image(systemName: "minus.magnifyingglass") } }
                    .disabled(zoom <= 1)
                    Button {
                        zoom = min(5, zoom * 1.35)
                    } label: { Label { Text("Zoom In", bundle: .module) } icon: { Image(systemName: "plus.magnifyingglass") } }
                    .disabled(zoom >= 5)
                    Button {
                        zoom = 1
                    } label: { Text("Fit Image", bundle: .module) }
                    .disabled(zoom <= 1)
                    Toggle(isOn: $translucent) { Text("Translucent Masks", bundle: .module) }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(Text("View Options", bundle: .module))
                if tool == .select {
                    selectionActions
                    Button {
                        apply { model.groupOcclusionMasks(selection) }
                    } label: {
                        Image(systemName: "square.stack")
                    }
                    .accessibilityLabel(Text("Group Masks", bundle: .module))
                    .disabled(selection.count < 2)
                    Button {
                        apply { model.ungroupOcclusionMasks(selection) }
                    } label: {
                        Image(systemName: "square.on.square")
                    }
                    .accessibilityLabel(Text("Ungroup Masks", bundle: .module))
                    .disabled(selection.isEmpty)
                    Button(role: .destructive) {
                        apply { model.setOcclusionMasks(model.occlusionMasks.filter { !selection.contains($0.id) }) }
                        selection = []
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text("Delete Selected Masks", bundle: .module))
                    .disabled(selection.isEmpty)
                }
            }
            .buttonStyle(.borderless)
        }
        .scrollIndicators(.hidden)
    }

    private var selectionActions: some View {
        Menu {
            Button {
                selection = Set(model.occlusionMasks.map(\.id))
            } label: { Text("Select All", bundle: .module) }
            Button {
                apply { model.duplicateOcclusionMasks(selection) }
            } label: { Text("Duplicate Masks", bundle: .module) }
            .disabled(selection.isEmpty)
            Button {
                showsFill.toggle()
            } label: { Text("Mask Color", bundle: .module) }
            .disabled(selection.isEmpty)
            if let mask = selectedMasks.first, selectedMasks.count == 1, mask.kind == "text" {
                Button {
                    editingLabelID = mask.id
                    label = mask.label
                    asksForLabel = true
                } label: { Text("Edit Label", bundle: .module) }
            }
            Menu {
                ForEach(AlignmentEdge.allCases, id: \.self) { edge in
                    Button { align(edge) } label: { Text(edge.title) }
                }
            } label: {
                Text("Align Masks", bundle: .module)
            }
            .disabled(selectedMasks.count < 2)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("Mask Options", bundle: .module))
    }

    private enum AlignmentEdge: CaseIterable {
        case left, right, top, bottom, horizontalCenter, verticalCenter

        var title: LocalizedStringResource {
            let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)
            return switch self {
            case .left: LocalizedStringResource("Align Left", bundle: bundle)
            case .right: LocalizedStringResource("Align Right", bundle: bundle)
            case .top: LocalizedStringResource("Align Top", bundle: bundle)
            case .bottom: LocalizedStringResource("Align Bottom", bundle: bundle)
            case .horizontalCenter: LocalizedStringResource("Align Centers Horizontally", bundle: bundle)
            case .verticalCenter: LocalizedStringResource("Align Centers Vertically", bundle: bundle)
            }
        }
    }

    private var selectedMasks: [ImageOcclusionMask] { model.occlusionMasks.filter { selection.contains($0.id) } }

    private func align(_ edge: AlignmentEdge) {
        let masks = selectedMasks
        guard let first = masks.first else { return }
        let bounds = masks.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        apply {
            model.setOcclusionMasks(model.occlusionMasks.map { original in
                guard selection.contains(original.id) else { return original }
                var mask = original
                let rect = mask.rect
                let offset: CGSize = switch edge {
                case .left: CGSize(width: bounds.minX - rect.minX, height: 0)
                case .right: CGSize(width: bounds.maxX - rect.maxX, height: 0)
                case .top: CGSize(width: 0, height: bounds.minY - rect.minY)
                case .bottom: CGSize(width: 0, height: bounds.maxY - rect.maxY)
                case .horizontalCenter: CGSize(width: bounds.midX - rect.midX, height: 0)
                case .verticalCenter: CGSize(width: 0, height: bounds.midY - rect.midY)
                }
                mask.setRect(rect.offsetBy(dx: offset.width, dy: offset.height))
                return mask
            })
        }
    }

    private func fillSelection() {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        guard UIColor(fillColor).getRed(&r, green: &g, blue: &b, alpha: nil) else { return }
        let hex = String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
        apply {
            model.setOcclusionMasks(model.occlusionMasks.map { original in
                guard selection.contains(original.id) else { return original }
                var mask = original
                mask.set("fill", hex)
                return mask
            })
        }
    }

    private func canvas(_ image: UIImage) -> some View {
        let ratio = max(0.05, image.size.width / max(1, image.size.height))
        return GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                let width = min(geometry.size.width, geometry.size.height * ratio) * zoom
                let size = CGSize(width: width, height: width / ratio)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .overlay {
                        Canvas { context, _ in
                            for mask in model.occlusionMasks {
                                draw(mask, in: context, size: size)
                            }
                            if let drag {
                                let rect = scale(drag, to: size)
                                let path = tool == .ellipse ? Path(ellipseIn: rect) : Path(rect)
                                context.fill(path, with: .color(.yellow.opacity(0.55)))
                                context.stroke(path, with: .color(.yellow), lineWidth: 2)
                            }
                            if let first = polygon.first {
                                var path = Path()
                                path.move(to: position(first, in: size))
                                for point in polygon.dropFirst() { path.addLine(to: position(point, in: size)) }
                                context.stroke(path, with: .color(.yellow), lineWidth: 3)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                        if tool == .rectangle || tool == .ellipse {
                            drag = rectangle(gesture, in: size)
                        }
                    }.onEnded { gesture in
                        applyGesture(gesture, in: size)
                    }, including: tool == .pan ? .none : .all)
                    .accessibilityLabel(Text("Image Occlusion Canvas", bundle: .module))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .scrollDisabled(zoom <= 1)
        }
        .frame(height: min(420, max(220, 380 / ratio)))
    }

    private func draw(_ mask: ImageOcclusionMask, in context: GraphicsContext, size: CGSize) {
        let rect = scale(mask.rect, to: size)
        let isSelected = selection.contains(mask.id)
        var context = context
        if mask.kind != "polygon" {
            context.translateBy(x: rect.minX, y: rect.minY)
            context.rotate(by: .degrees(Double(mask.number("angle")) * 360 / 10_000))
            context.translateBy(x: -rect.minX, y: -rect.minY)
        }
        let color = mask.value("fill").flatMap { value -> Color? in
            guard value.count == 7, value.hasPrefix("#"), let hex = UInt32(value.dropFirst(), radix: 16) else { return nil }
            return Color(red: Double((hex >> 16) & 255) / 255,
                         green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
        }
        if mask.kind == "text" {
            context.fill(Path(rect), with: .color(.white))
            let fontSize = mask.number("fs") * size.height * max(0.1, mask.number("scale"))
            context.draw(Text(mask.label).font(.system(size: max(12, fontSize)))
                .foregroundStyle(color ?? .black), at: rect.origin, anchor: .topLeading)
        } else {
            let path: Path
            if mask.kind == "ellipse" {
                path = Path(ellipseIn: rect)
            } else if mask.kind == "polygon", let first = mask.polygon.first {
                path = Path { path in
                    path.move(to: position(first, in: size))
                    for point in mask.polygon.dropFirst() { path.addLine(to: position(point, in: size)) }
                    path.closeSubpath()
                }
            } else {
                path = Path(rect)
            }
            let fill = color ?? Color(red: 1, green: 0.92, blue: 0.64)
            context.fill(path, with: .color(fill.opacity(translucent ? 0.25 : 0.9)))
            context.stroke(path, with: .color(isSelected ? .blue : .black.opacity(0.65)), lineWidth: 1.5)
        }
        if isSelected {
            let corner = CGRect(x: rect.maxX - 4, y: rect.maxY - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: corner), with: .color(.blue))
        }
    }

    private func applyGesture(_ gesture: DragGesture.Value, in size: CGSize) {
        let start = normalized(gesture.startLocation, in: size)
        let end = normalized(gesture.location, in: size)
        switch tool {
        case .pan: break
        case .rectangle, .ellipse:
            let rect = rectangle(gesture, in: size)
            drag = nil
            if rect.width * size.width >= 5, rect.height * size.height >= 5 {
                apply { model.addOcclusionMask(in: rect, ellipse: tool == .ellipse) }
            }
        case .polygon:
            polygon.append(end)
        case .text:
            textPoint = end
            editingLabelID = nil
            label = ""
            asksForLabel = true
        case .select:
            let mask = model.occlusionMasks.reversed().first {
                $0.rect.insetBy(dx: -10 / size.width, dy: -10 / size.height).contains(start)
            }
            guard let mask else { selection = []; return }
            if abs(gesture.translation.width) + abs(gesture.translation.height) < 6 {
                toggle(mask.id)
                return
            }
            let rect = mask.rect
            selection.insert(mask.id)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let corner = abs(start.x - rect.maxX) < 12 / size.width && abs(start.y - rect.maxY) < 12 / size.height
            let target = corner
                ? CGRect(x: rect.minX, y: rect.minY, width: max(0.01, rect.width + dx), height: max(0.01, rect.height + dy))
                : rect.offsetBy(dx: min(1 - rect.maxX, max(-rect.minX, dx)), dy: min(1 - rect.maxY, max(-rect.minY, dy)))
            apply { model.replaceOcclusionMask(mask.id, with: target) }
        }
    }

    private func rectangle(_ gesture: DragGesture.Value, in size: CGSize) -> CGRect {
        let a = normalized(gesture.startLocation, in: size)
        let b = normalized(gesture.location, in: size)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func normalized(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x / size.width)), y: min(1, max(0, point.y / size.height)))
    }

    private func position(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func scale(_ rect: CGRect, to size: CGSize) -> CGRect {
        CGRect(origin: position(rect.origin, in: size),
               size: CGSize(width: rect.width * size.width, height: rect.height * size.height))
    }

    private func apply(_ edit: () -> Void) {
        let previous = model.occlusionMasks
        edit()
        if model.occlusionMasks != previous {
            undo.append(previous)
            redo = []
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) }
        else { selection.insert(id) }
    }
}
#endif
