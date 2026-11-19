import SwiftUI

enum EditorToolbarLayout: String, CaseIterable {
    case scroll, stack, hidden

    var title: Text {
        switch self {
        case .scroll: Text("Scroll", bundle: .module)
        case .stack: Text("Stack", bundle: .module)
        case .hidden: Text("Hidden", bundle: .module)
        }
    }
}

enum EditorTextFormat {
    case bold, italic, underline, inlineMath, displayMath, heading(Int), fontSize(Int), horizontalRule
    case cloze(reuseLast: Bool)
    case custom(prefix: String, suffix: String)

    func wrapper(fields: [EditableField]) -> (prefix: String, suffix: String) {
        switch self {
        case .bold: ("<b>", "</b>")
        case .italic: ("<i>", "</i>")
        case .underline: ("<u>", "</u>")
        case .inlineMath: ("\\(", "\\)")
        case .displayMath: ("\\[", "\\]")
        case .heading(let level): ("<h\(level)>", "</h\(level)>")
        case .fontSize(let size): ("<span style=\"font-size: \(size)px\">", "</span>")
        case .horizontalRule: ("<hr>", "")
        case .cloze(let reuseLast):
            ("{{c\(Self.clozeNumber(in: fields, reuseLast: reuseLast))::", "}}")
        case .custom(let prefix, let suffix): (prefix, suffix)
        }
    }

    private static func clozeNumber(in fields: [EditableField], reuseLast: Bool) -> Int {
        let last = fields.flatMap { field in
            field.content.matches(of: /\{\{c([1-9][0-9]*)::/).compactMap { UInt16($0.output.1) }
        }.max() ?? 0
        return reuseLast ? max(1, Int(last)) : min(Int(last) + 1, Int(UInt16.max))
    }
}

struct EditorFormattingToolbar: View {
    let layout: EditorToolbarLayout
    let isCloze: Bool
    let format: (EditorTextFormat) -> Void
    @AppStorage("noteEditorCustomFormats") private var storedButtons = Data()
    @State private var isEditingButton = false
    @State private var editedButton: ToolbarButton?
    @State private var buttonName = ""
    @State private var prefix = ""
    @State private var suffix = ""

    var body: some View {
        switch layout {
        case .hidden:
            EmptyView()
        case .scroll, .stack:
            controls
                .padding(.horizontal, 8)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
                .alert(Text("Toolbar Button", bundle: .module), isPresented: $isEditingButton) {
                    TextField(text: $buttonName) { Text("Label", bundle: .module) }
                    TextField(text: $prefix) { Text("Before Text", bundle: .module) }
                    TextField(text: $suffix) { Text("After Text", bundle: .module) }
                    Button { saveButton() } label: { Text("Save", bundle: .module) }
                        .disabled(buttonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (prefix.isEmpty && suffix.isEmpty))
                    Button(role: .cancel) {}
                }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if layout == .scroll {
            ScrollView(.horizontal) {
                HStack(spacing: 0) { buttons }
            }
            .scrollIndicators(.hidden)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 0)], spacing: 0) {
                buttons
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if isCloze {
            Button { format(.cloze(reuseLast: false)) } label: {
                toolIcon("curlybraces", label: Text("New Cloze", bundle: .module))
            }
            Button { format(.cloze(reuseLast: true)) } label: {
                toolIcon("equal", label: Text("Repeat Cloze Number", bundle: .module))
            }
        }
        formatButton(.bold, icon: "bold", label: Text("Bold", bundle: .module))
        formatButton(.italic, icon: "italic", label: Text("Italic", bundle: .module))
        formatButton(.underline, icon: "underline", label: Text("Underline", bundle: .module))
        Menu {
            Button { format(.inlineMath) } label: { Text("Inline MathJax", bundle: .module) }
            Button { format(.displayMath) } label: { Text("Display MathJax", bundle: .module) }
        } label: {
            toolIcon("sum", label: Text("MathJax", bundle: .module))
        }
        Menu {
            ForEach(1...6, id: \.self) { level in
                Button { format(.heading(level)) } label: { Text("Heading \(level)", bundle: .module) }
            }
        } label: {
            toolIcon("textformat", label: Text("Heading", bundle: .module))
        }
        Menu {
            ForEach([12, 16, 20, 24, 32, 48], id: \.self) { size in
                Button { format(.fontSize(size)) } label: { Text(size.formatted()) }
            }
        } label: {
            toolIcon("textformat.size", label: Text("Font Size", bundle: .module))
        }
        formatButton(.horizontalRule, icon: "minus", label: Text("Horizontal Line", bundle: .module))
        ForEach(customButtons) { button in
            Button { format(.custom(prefix: button.prefix, suffix: button.suffix)) } label: {
                Text(verbatim: button.name)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .contextMenu {
                Button { edit(button) } label: { Text("Edit Toolbar Button", bundle: .module) }
                Button(role: .destructive) {
                    storedButtons = (try? JSONEncoder().encode(customButtons.filter { $0.id != button.id })) ?? Data()
                } label: {
                    Text("Remove Toolbar Button", bundle: .module)
                }
            }
        }
        Button { edit(nil) } label: {
            toolIcon("plus", label: Text("Add Toolbar Button", bundle: .module))
        }
    }

    private func formatButton(_ action: EditorTextFormat, icon: String, label: Text) -> some View {
        Button { format(action) } label: { toolIcon(icon, label: label) }
    }

    private func toolIcon(_ icon: String, label: Text) -> some View {
        Image(systemName: icon)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(label)
    }

    private var customButtons: [ToolbarButton] {
        (try? JSONDecoder().decode([ToolbarButton].self, from: storedButtons)) ?? []
    }

    private func edit(_ button: ToolbarButton?) {
        editedButton = button
        buttonName = button?.name ?? ""
        prefix = button?.prefix ?? ""
        suffix = button?.suffix ?? ""
        isEditingButton = true
    }

    private func saveButton() {
        var buttons = customButtons
        let button = ToolbarButton(
            id: editedButton?.id ?? UUID(), name: buttonName.trimmingCharacters(in: .whitespacesAndNewlines),
            prefix: prefix, suffix: suffix
        )
        if let index = buttons.firstIndex(where: { $0.id == button.id }) {
            buttons[index] = button
        } else {
            buttons.append(button)
        }
        storedButtons = (try? JSONEncoder().encode(buttons)) ?? Data()
    }
}

private struct ToolbarButton: Codable, Identifiable {
    let id: UUID
    let name: String
    let prefix: String
    let suffix: String
}
