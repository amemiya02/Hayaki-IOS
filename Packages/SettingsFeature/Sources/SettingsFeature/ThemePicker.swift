import HayakiAppearance
import SwiftUI

/// Each theme as a small preview card, drawn in the current appearance.
struct ThemePicker: View {
    @Binding var selection: Theme
    @Environment(\.hayakiTheme) private var current
    @ScaledMetric(relativeTo: .footnote) private var cardWidth: CGFloat = 92

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cardWidth), spacing: 12)], spacing: 12) {
            ForEach(Theme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    ThemeCard(theme: HayakiTheme(theme, current.appearance), isSelected: theme == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(theme == selection ? .isSelected : [])
                .accessibilityIdentifier("theme-\(theme.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ThemeCard: View {
    let theme: HayakiTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            preview
                .aspectRatio(1.3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? theme.accent : Color.secondary.opacity(0.3),
                                      lineWidth: isSelected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, theme.accent)
                            .font(.body)
                            .padding(6)
                    }
                }
            theme.theme.title
                .font(.footnote)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The study canvas with a card surface, two lines of text and an accent button.
    private var preview: some View {
        ZStack {
            Color(hayakiRGB: theme.canvasRGB)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color.primary.opacity(0.55)).frame(width: 34, height: 5)
                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 48, height: 5)
                Spacer(minLength: 0)
                Capsule().fill(theme.accent).frame(height: 12)
            }
            .padding(9)
            .background(theme.surface, in: .rect(cornerRadius: 8))
            .padding(8)
        }
        .accessibilityHidden(true)
    }
}

extension Theme {
    var title: Text {
        switch self {
        case .hayaki: Text("Hayaki", bundle: .module)
        case .sakura: Text("Sakura", bundle: .module)
        case .matcha: Text("Matcha", bundle: .module)
        case .ocean: Text("Ocean", bundle: .module)
        case .indigo: Text("Indigo", bundle: .module)
        case .wisteria: Text("Wisteria", bundle: .module)
        case .amber: Text("Amber", bundle: .module)
        case .sumi: Text("Sumi", bundle: .module)
        case .paper: Text("Paper", bundle: .module)
        case .midnight: Text("Midnight", bundle: .module)
        }
    }
}
