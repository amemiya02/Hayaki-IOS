#if os(iOS)
import SwiftUI
import UIKit

/// iOS stores the app language and applies it to the app and its system surfaces on launch.
struct LanguageSettingsRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Label {
                Text("Language", bundle: .module)
            } icon: {
                Image(systemName: "globe")
            }
        }
        .accessibilityHint(Text("Choose the language for Hayaki in the Settings app.", bundle: .module))
        .accessibilityIdentifier("app-language-settings")
    }
}
#endif
