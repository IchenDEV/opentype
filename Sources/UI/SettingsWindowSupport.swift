import CoreGraphics

enum SettingsWindowLayout {
    static let width: CGFloat = 760
    static let height: CGFloat = 540
}

enum SettingsWindowTitle {
    static var current: String {
        text(for: AppSettings.shared.uiLanguage)
    }

    static func text(for language: UILanguage) -> String {
        Loc.string("settings.window_title", language: language)
    }
}
