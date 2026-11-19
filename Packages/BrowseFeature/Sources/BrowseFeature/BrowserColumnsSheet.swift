import SwiftUI

struct BrowserColumnsSheet: View {
    let model: CardBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String]

    init(model: CardBrowserModel) {
        self.model = model
        _selected = State(initialValue: model.visibleColumnIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selected, id: \.self) { id in
                        HStack {
                            Text(model.availableColumns.first { $0.id == id }?.label ?? id)
                            Spacer()
                            Button {
                                selected.removeAll { $0 == id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Remove Column", bundle: .module))
                            .disabled(selected.count == 1)
                        }
                    }
                    .onMove { offsets, destination in selected.move(fromOffsets: offsets, toOffset: destination) }
                } header: {
                    Text("Shown Columns", bundle: .module)
                }
                Section {
                    ForEach(model.availableColumns.filter { !selected.contains($0.id) }) { column in
                        Button {
                            selected.append(column.id)
                        } label: {
                            Label(column.label, systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Available Columns", bundle: .module)
                }
            }
            .navigationTitle(Text("Columns", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Cancel", bundle: .module) }
                }
                #if os(iOS)
                ToolbarItem(placement: .automatic) { EditButton() }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let columns = selected
                        dismiss()
                        Task { await model.setColumns(columns) }
                    } label: { Text("Done", bundle: .module) }
                }
            }
        }
    }
}
