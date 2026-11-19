import Foundation

func reviewerLocalized(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .module)
}
