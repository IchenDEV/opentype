import Foundation

/// Lightweight localization helper.
///
/// Loads strings from `Localizable.strings` inside the `.lproj` that matches
/// the user's `uiLanguage` setting (not the system locale).
///
/// Usage: `L("status.ready")`
enum Loc {
    private static var cachedLang: UILanguage?
    private static var cachedBundle: Bundle?

    static func string(_ key: String) -> String {
        // Read UserDefaults directly to avoid circular init with AppSettings.shared
        let lang = UILanguage(rawValue: UserDefaults.standard.string(forKey: "uiLanguage") ?? "") ?? .chinese
        if lang != cachedLang {
            cachedLang = lang
            let code = lang == .chinese ? "zh-Hans" : "en"
            if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                cachedBundle = bundle
            } else {
                cachedBundle = Bundle.module
            }
        }
        return cachedBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

func L(_ key: String) -> String { Loc.string(key) }
