import SwiftUI

/// The quick filters: common searches the learner reaches without typing
/// Anki's search syntax. Choosing one replaces the search.
struct QuickFilterMenu: View {
    let model: CardBrowserModel

    var body: some View {
        Menu {
            Menu {
                ForEach(model.choices.decks, id: \.self) { deck in
                    filterButton(.deck(deck)) {
                        Text(verbatim: deck)
                    }
                }
            } label: {
                Label {
                    Text("Deck", bundle: .module)
                } icon: {
                    Image(systemName: "rectangle.stack")
                }
            }
            .disabled(model.choices.decks.isEmpty)
            Menu {
                ForEach(model.choices.tags, id: \.self) { tag in
                    filterButton(.tag(tag)) {
                        Text(verbatim: tag)
                    }
                }
            } label: {
                Label {
                    Text("Tag", bundle: .module)
                } icon: {
                    Image(systemName: "tag")
                }
            }
            .disabled(model.choices.tags.isEmpty)
            Menu {
                ForEach(CardRow.Flag.allCases, id: \.self) { flag in
                    filterButton(.flag(flag)) {
                        Label {
                            flag.name
                        } icon: {
                            Image(systemName: "flag.fill")
                        }
                    }
                    .tint(flag.color)
                }
            } label: {
                Label {
                    Text("Flag", bundle: .module)
                } icon: {
                    Image(systemName: "flag")
                }
            }
            Divider()
            filterButton(.suspended) {
                Label {
                    Text("Suspended", bundle: .module)
                } icon: {
                    Image(systemName: "pause.circle")
                }
            }
            filterButton(.dueToday) {
                Label {
                    Text("Due Today", bundle: .module)
                } icon: {
                    Image(systemName: "calendar")
                }
            }
        } label: {
            Label {
                Text("Filter", bundle: .module)
            } icon: {
                Image(systemName: "line.3.horizontal.decrease")
            }
        }
    }

    private func filterButton(_ filter: QuickFilter, @ViewBuilder label: () -> some View) -> some View {
        Button {
            Task { await model.applyFilter(filter) }
        } label: {
            label()
        }
    }
}

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
