import Foundation
import SwiftUI

/// How Han characters on cards are drawn: the Card Kanji/Hanzi Style
/// setting. It sets the card page's `<html lang>`, so WebKit picks Hiragino
/// Sans (Japanese) or PingFang (Chinese) glyph forms, such as those of 直 and
/// 骨. Fonts a card's template names are left alone.
public enum CardGlyphStyle: String, CaseIterable, Sendable {
    case followAppLanguage
    case japanese
    case simplifiedChinese
    case traditionalChinese

    public static let preferenceKey = "hayaki.reviewer.cardGlyphStyle"
    public static let `default` = CardGlyphStyle.followAppLanguage

    /// The language the app's interface is shown in.
    static var appLanguage: String? {
        Bundle.main.preferredLocalizations.first
    }

    /// The BCP 47 language for the card page, or an empty string for none.
    public func cardLanguage(appLanguage: String?) -> String {
        switch self {
        case .followAppLanguage:
            (appLanguage ?? "").replacingOccurrences(of: "_", with: "-")
        case .japanese: "ja"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        }
    }
}

/// The Card Kanji/Hanzi Style picker for study settings.
struct CardGlyphStylePicker: View {
    @AppStorage(CardGlyphStyle.preferenceKey) private var style = CardGlyphStyle.default

    var body: some View {
        Picker(selection: $style) {
            Text("Follow App Language", bundle: .module).tag(CardGlyphStyle.followAppLanguage)
            // Each language is named in itself, as in the system language list.
            Text(verbatim: "日本語").tag(CardGlyphStyle.japanese)
            Text(verbatim: "简体中文").tag(CardGlyphStyle.simplifiedChinese)
            Text(verbatim: "繁體中文").tag(CardGlyphStyle.traditionalChinese)
        } label: {
            Text("Card Kanji/Hanzi Style", bundle: .module)
        }
        .accessibilityIdentifier("card-glyph-style")
    }
}
