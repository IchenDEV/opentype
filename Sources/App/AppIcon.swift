import AppKit

enum AppIcon {

    @MainActor
    static func install() {
        let resource = AppSettings.shared.appIconAppearance.resourceName(systemIsDark: systemIsDark)
        guard let url = Bundle.module.url(forResource: resource, withExtension: "png")
                ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return
        }
        image.size = NSSize(width: 512, height: 512)
        NSApp.applicationIconImage = image
    }

    @MainActor
    private static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
