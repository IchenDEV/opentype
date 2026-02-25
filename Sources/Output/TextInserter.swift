import Foundation
import AppKit
import CoreGraphics
import Carbon.HIToolbox

enum InsertResult {
    case success
    case probablyFailed(reason: String)
}

@MainActor
struct TextInserter {

    func insert(text: String, targetApp: NSRunningApplication? = nil) async -> InsertResult {
        guard AXIsProcessTrusted() else {
            Log.error("[TextInserter] no AX trust")
            return .probablyFailed(reason: "Accessibility permission not granted")
        }

        await activateTarget(targetApp)

        let front = NSWorkspace.shared.frontmostApplication
        let targetPID = targetApp?.processIdentifier
        let activated = targetPID == nil || front?.processIdentifier == targetPID

        let result = await insertViaClipboard(text: text)

        if !activated || !result {
            let reason = activated
                ? "Paste command may not have reached the target"
                : "Could not activate target application"
            Log.info("[TextInserter] probably failed: \(reason)")
            return .probablyFailed(reason: reason)
        }
        return .success
    }

    // MARK: - Activate target

    private func activateTarget(_ app: NSRunningApplication?) async {
        guard let app, !app.isTerminated else { return }

        NSApp.yieldActivation(to: app)
        app.activate()

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                break
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Clipboard + Cmd+V

    /// Returns true if at least one paste method was executed without errors.
    private func insertViaClipboard(text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let prevChange = pasteboard.changeCount
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(nanoseconds: 50_000_000)

        let pasteOK: Bool
        if await simulatePaste() {
            pasteOK = true
        } else {
            Log.info("[TextInserter] CGEvent failed, trying AppleScript")
            pasteOK = pasteViaAppleScript()
        }

        try? await Task.sleep(nanoseconds: 300_000_000)

        if pasteboard.changeCount == prevChange + 1 {
            pasteboard.clearContents()
            if let prev = previousContents {
                pasteboard.setString(prev, forType: .string)
            }
        }

        return pasteOK
    }

    @discardableResult
    private func simulatePaste() async -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source,
                                     virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source,
                                   virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        try? await Task.sleep(nanoseconds: 12_000_000)
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        return true
    }

    private func pasteViaAppleScript() -> Bool {
        let script = NSAppleScript(source: """
        tell application "System Events" to keystroke "v" using command down
        """)
        var errInfo: NSDictionary?
        script?.executeAndReturnError(&errInfo)
        if let errInfo {
            Log.error("[TextInserter] AppleScript error: \(errInfo)")
            return false
        }
        return true
    }

    /// Place text on the clipboard so the user can manually Cmd+V.
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
