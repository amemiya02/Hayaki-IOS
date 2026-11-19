import Foundation

/// Search terms for the feature screens linked from More.
enum SettingsTopic: CaseIterable {
    case profiles, general, appearance, accessibility, reviewer, sync, reminders, backups
    case storage, noteTypes, advanced, transfer, help, about
    #if DEBUG
    case developer
    #endif

    func matches(_ query: String, locale: Locale) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let localizations = Bundle.module.localizations
        let language = Bundle.preferredLocalizations(from: localizations, forPreferences: [locale.identifier]).first
        let path = language.flatMap { Bundle.module.url(forResource: $0, withExtension: "lproj") }
        let keywords = path.flatMap(Bundle.init(url:))?.localizedString(forKey: searchKey, value: searchKey, table: nil)
        let indexed = "\(keywords ?? searchKey) \(searchKey)"
        return terms.allSatisfy {
            indexed.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale) != nil
        }
    }

    private var searchKey: String {
        switch self {
        case .profiles: "Profiles switch profile rename delete"
        case .general: "General language editing deck for new cards paste clipboard images PNG show media filenames in browse"
        case .appearance: "Appearance theme system light dark black night deck list background image wallpaper"
        case .accessibility: "Accessibility dynamic type voiceover browse font scaling text size animations"
        case .reviewer: "Reviewer studying controls gestures keyboard controller toolbar action tap timebox rollover start next day learn ahead zoom image answer size rating time hold double tap interval speech frame card"
        case .sync: "Sync AnkiWeb account server timeout media internet certificate network automatic one-way"
        case .reminders: "Daily Reminder Deck Review Reminders notifications schedule alerts permission"
        case .backups: "Backups retention automatic daily weekly monthly restore recovery"
        case .storage: "Manage Space storage collection media check database delete unused"
        case .noteTypes: "Note Types fields card template layout"
        case .advanced: "Advanced script permissions security audio recording external links focus type in answer replace newlines HTML"
        case .transfer: "Transfer Guide import export deck collection package"
        case .help: "Help manual report issue"
        case .about: "About version build engine FSRS acknowledgements license credits source code notices changelog privacy diagnostics"
        #if DEBUG
        case .developer: "Developer Options web inspector debugging test"
        #endif
        }
    }
}
