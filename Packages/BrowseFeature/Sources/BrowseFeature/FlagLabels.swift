import SwiftUI

extension CardRow.Flag {
    /// The flag's name, as menus show it.
    var name: Text {
        switch self {
        case .red: Text("Red", bundle: .module)
        case .orange: Text("Orange", bundle: .module)
        case .green: Text("Green", bundle: .module)
        case .blue: Text("Blue", bundle: .module)
        case .pink: Text("Pink", bundle: .module)
        case .turquoise: Text("Turquoise", bundle: .module)
        case .purple: Text("Purple", bundle: .module)
        }
    }
}

extension CardBrowserModel {
    func flagName(_ flag: CardRow.Flag) -> Text {
        if let name = flagNames[flag] { Text(verbatim: name) } else { flag.name }
    }
}

struct BrowserFlagLabelsSheet: View {
    let model: CardBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var names: [CardRow.Flag: String]

    init(model: CardBrowserModel) {
        self.model = model
        _names = State(initialValue: model.flagNames)
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(CardRow.Flag.allCases, id: \.self) { flag in
                    HStack {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(flag.color)
                            .accessibilityHidden(true)
                        TextField(text: Binding {
                            names[flag, default: ""]
                        } set: { name in
                            names[flag] = name
                        }) {
                            flag.name
                        }
                    }
                }
            }
            .navigationTitle(Text("Rename Flags", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let updates = names
                        dismiss()
                        Task { await model.saveFlagNames(updates) }
                    } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }
}
