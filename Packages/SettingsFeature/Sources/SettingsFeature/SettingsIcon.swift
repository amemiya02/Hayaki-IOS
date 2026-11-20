import SwiftUI

/// The colored rounded-square icon for a row on More, as in iOS Settings.
///
/// The fill colors are fixed system colors, never the theme accent, so every row keeps its
/// color in all themes and in light, dark and black appearance. The glyph is always white.
struct SettingsIcon: Hashable, Sendable {
    let symbol: String
    let color: Color

    static let profiles = SettingsIcon(symbol: "person.fill", color: .gray)

    static let general = SettingsIcon(symbol: "gearshape.fill", color: .gray)
    static let appearance = SettingsIcon(symbol: "circle.lefthalf.filled", color: .blue)
    static let accessibility = SettingsIcon(symbol: "accessibility", color: .blue)
    static let reviewer = SettingsIcon(symbol: "rectangle.portrait.on.rectangle.portrait.fill", color: .indigo)

    static let sync = SettingsIcon(symbol: "arrow.triangle.2.circlepath", color: .green)
    static let backups = SettingsIcon(symbol: "clock.arrow.circlepath", color: .teal)
    static let storage = SettingsIcon(symbol: "internaldrive.fill", color: .gray)

    static let dailyReminder = SettingsIcon(symbol: "bell.fill", color: .red)
    static let deckReminders = SettingsIcon(symbol: "bell.badge.fill", color: .orange)

    static let noteTypes = SettingsIcon(symbol: "list.bullet.rectangle.portrait.fill", color: .purple)
    static let advanced = SettingsIcon(symbol: "gearshape.2.fill", color: .gray)
    static let developer = SettingsIcon(symbol: "hammer.fill", color: .brown)

    static let transfer = SettingsIcon(symbol: "arrow.left.arrow.right", color: .cyan)
    static let help = SettingsIcon(symbol: "questionmark", color: .blue)
    static let about = SettingsIcon(symbol: "info", color: .gray)

    static let all: [SettingsIcon] = [
        .profiles, .general, .appearance, .accessibility, .reviewer, .sync, .backups, .storage,
        .dailyReminder, .deckReminders, .noteTypes, .advanced, .developer, .transfer, .help, .about,
    ]
}

/// Draws a row's label with its ``SettingsIcon`` in place of whatever icon the row brought.
///
/// Rows owned by other packages (Sync, reminders, Profiles) keep their own labels; More only
/// decides how they look here.
struct SettingsIconLabelStyle: LabelStyle {
    let icon: SettingsIcon
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 29

    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
        } icon: {
            Image(systemName: icon.symbol)
                .font(.system(size: side * 0.55, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(icon.color.gradient, in: .rect(cornerRadius: side * 0.24, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Shows every label in this row with the given More icon.
    func settingsIcon(_ icon: SettingsIcon) -> some View {
        labelStyle(SettingsIconLabelStyle(icon: icon))
            .labeledContentStyle(SettingsIconLabeledContentStyle(icon: icon))
    }
}

/// Lays out a row that pairs its label with a value (Profiles, Sync, Daily Reminder) the way
/// the system does, and gives the label the More icon: the system's own style does not pass
/// the row's label style on to the label.
struct SettingsIconLabeledContentStyle: LabeledContentStyle {
    let icon: SettingsIcon

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .labelStyle(SettingsIconLabelStyle(icon: icon))
            Spacer()
            configuration.content
                .foregroundStyle(.secondary)
        }
    }
}
