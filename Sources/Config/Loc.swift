import Foundation

/// Lightweight localization helper.
///
/// Loads strings from `Localizable.strings` inside the `.lproj` that matches
/// the user's `uiLanguage` setting (not the system locale).
///
/// Usage: `L("status.ready")`
enum Loc {
    private static var selectedLang: UILanguage?
    private static var cachedLang: UILanguage?
    private static var cachedBundle: Bundle?

    static func use(_ language: UILanguage) {
        selectedLang = language
        cachedLang = nil
        cachedBundle = nil
    }

    static func string(_ key: String, language explicitLanguage: UILanguage? = nil) -> String {
        // Fall back to UserDefaults to avoid circular init with AppSettings.shared.
        let lang = explicitLanguage ?? selectedLang ?? savedLanguage()
        if lang != cachedLang {
            cachedLang = lang
            let code = lang == .chinese ? "zh-hans" : "en"
            if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                cachedBundle = bundle
            } else {
                cachedBundle = Bundle.module
            }
        }
        return cachedBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    private static func savedLanguage() -> UILanguage {
        UILanguage(rawValue: UserDefaults.standard.string(forKey: "uiLanguage") ?? "") ?? .chinese
    }
}

func L(_ key: String) -> String { Loc.string(key) }
