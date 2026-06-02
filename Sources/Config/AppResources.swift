import Foundation

enum AppResources {
    private static var cachedBundle: Bundle?

    static var bundle: Bundle {
        if let cachedBundle { return cachedBundle }

        let bundleName = "OpenType_OpenType.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
        ].compactMap { $0 }

        for url in candidates {
            if let bundle = Bundle(url: url) {
                cachedBundle = bundle
                return bundle
            }
        }

        let bundle = Bundle.module
        cachedBundle = bundle
        return bundle
    }
}
