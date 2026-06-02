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
            if let path = lprojNames(for: lang)
                .lazy
                .compactMap({ AppResources.bundle.path(forResource: $0, ofType: "lproj") })
                .first,
               let bundle = Bundle(path: path) {
                cachedBundle = bundle
            } else {
                cachedBundle = AppResources.bundle
            }
        }
        return cachedBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    private static func savedLanguage() -> UILanguage {
        UILanguage(rawValue: UserDefaults.standard.string(forKey: "uiLanguage") ?? "") ?? .chinese
    }

    private static func lprojNames(for language: UILanguage) -> [String] {
        switch language {
        case .chinese: return ["zh-Hans", "zh-hans", "zh"]
        case .english: return ["en"]
        }
    }
}

func L(_ key: String) -> String { Loc.string(key) }
