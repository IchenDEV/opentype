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
    private static let maxFocusedContextLength = 500

    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let screenContext: String?
    let textBeforeSelection: String?
    let selectedText: String?
    let textAfterSelection: String?
    let outputMode: OutputMode
    let inputLanguage: InputLanguage
    let source: InputSource

    init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        windowTitle: String? = nil,
        screenContext: String? = nil,
        textBeforeSelection: String? = nil,
        selectedText: String? = nil,
        textAfterSelection: String? = nil,
        outputMode: OutputMode,
        inputLanguage: InputLanguage,
        source: InputSource
    ) {
        self.appName = Self.normalized(appName)
        self.bundleIdentifier = Self.normalized(bundleIdentifier)
        self.windowTitle = Self.normalized(windowTitle, limit: Self.maxWindowTitleLength)
        self.screenContext = Self.normalized(screenContext, limit: Self.maxScreenContextLength)
        self.textBeforeSelection = Self.normalized(textBeforeSelection, limit: Self.maxFocusedContextLength)
        self.selectedText = Self.normalized(selectedText, limit: Self.maxFocusedContextLength)
        self.textAfterSelection = Self.normalized(textAfterSelection, limit: Self.maxFocusedContextLength)
        self.outputMode = outputMode
        self.inputLanguage = inputLanguage
        self.source = source
    }

    @MainActor
    static func capture(
        targetApp: NSRunningApplication?,
        screenContext: String,
        selectedTextOverride: String? = nil,
        outputMode: OutputMode,
        inputLanguage: InputLanguage,
        source: InputSource
    ) -> InputContext {
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication
        let focusedText = focusedTextContext(for: app)
        let selectedText = normalized(selectedTextOverride, limit: maxFocusedContextLength)
            ?? focusedText?.selectedText
        return InputContext(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            windowTitle: windowTitle(for: app),
            screenContext: screenContext,
            textBeforeSelection: focusedText?.textBeforeSelection,
            selectedText: selectedText,
            textAfterSelection: focusedText?.textAfterSelection,
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

    @MainActor
    private static func focusedTextContext(for app: NSRunningApplication?) -> FocusedTextContext? {
        guard let app, AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedElement = focusedValue,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedAXElement = focusedElement as! AXUIElement
        guard let valueText = focusedText(from: focusedAXElement) else {
            return focusedSelectionOnly(from: focusedAXElement)
        }

        var range = CFRange(location: 0, length: 0)
        guard let rangeValue = selectedTextRange(from: focusedAXElement),
              AXValueGetValue(rangeValue, .cfRange, &range) else {
            return FocusedTextContext(
                textBeforeSelection: nil,
                selectedText: focusedSelectionText(from: focusedAXElement),
                textAfterSelection: nil
            )
        }

        return focusedTextContext(text: valueText, range: range)
    }

    private static func focusedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func focusedSelectionOnly(from element: AXUIElement) -> FocusedTextContext? {
        guard let selectedText = focusedSelectionText(from: element) else { return nil }
        return FocusedTextContext(
            textBeforeSelection: nil,
            selectedText: selectedText,
            textAfterSelection: nil
        )
    }

    private static func focusedSelectionText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return normalized(value as? String, limit: maxFocusedContextLength)
    }

    private static func selectedTextRange(from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success else {
            return nil
        }
        guard let rangeValue = value, CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }
        return (rangeValue as! AXValue)
    }

    private static func focusedTextContext(text: String, range: CFRange) -> FocusedTextContext {
        let nsText = text as NSString
        let textLength = nsText.length
        let start = min(max(range.location, 0), textLength)
        let selectionLength = max(range.length, 0)
        let end = min(start + selectionLength, textLength)
        let beforeStart = max(0, start - maxFocusedContextLength)
        let afterEnd = min(textLength, end + maxFocusedContextLength)

        let before = nsText.substring(with: NSRange(location: beforeStart, length: start - beforeStart))
        let selected = nsText.substring(with: NSRange(location: start, length: end - start))
        let after = nsText.substring(with: NSRange(location: end, length: afterEnd - end))

        return FocusedTextContext(
            textBeforeSelection: before,
            selectedText: selected,
            textAfterSelection: after
        )
    }
}

private struct FocusedTextContext {
    let textBeforeSelection: String?
    let selectedText: String?
    let textAfterSelection: String?
}
