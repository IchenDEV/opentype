import AppKit
import ApplicationServices
import Foundation

enum InputSource: String, Codable, Equatable {
    case menuBar
    case integration
}

struct InputContext: Codable, Equatable {
    private static let maxScreenContextLength = 1_200
    private static let maxWindowTitleLength = 160

    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let screenContext: String?
    let outputMode: OutputMode
    let inputLanguage: InputLanguage
    let source: InputSource

    init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        screenContext: String? = nil,
        outputMode: OutputMode,
        inputLanguage: InputLanguage,
        source: InputSource
    ) {
        self.appName = Self.normalized(appName)
        self.bundleIdentifier = Self.normalized(bundleIdentifier)
        self.windowTitle = Self.normalized(windowTitle, limit: Self.maxWindowTitleLength)
        self.screenContext = Self.normalized(screenContext, limit: Self.maxScreenContextLength)
        self.outputMode = outputMode
        self.inputLanguage = inputLanguage
        self.source = source
    }

    @MainActor
    static func capture(
        targetApp: NSRunningApplication?,
        screenContext: String,
        outputMode: OutputMode,
        inputLanguage: InputLanguage,
        source: InputSource
    ) -> InputContext {
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication
        return InputContext(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            windowTitle: windowTitle(for: app),
            screenContext: screenContext,
            outputMode: outputMode,
            inputLanguage: inputLanguage,
            source: source
        )
    }

    private static func normalized(_ text: String?, limit: Int = .max) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }

    @MainActor
    private static func windowTitle(for app: NSRunningApplication?) -> String? {
        guard let app, AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let title = title(from: axApp, attribute: attribute as CFString) {
                return title
            }
        }
        return nil
    }

    private static func title(from app: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute, &value) == .success,
              let window = value,
              CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }

        var titleValue: CFTypeRef?
        let windowElement = window as! AXUIElement
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleValue) == .success else {
            return nil
        }
        return normalized(titleValue as? String, limit: maxWindowTitleLength)
    }
}
