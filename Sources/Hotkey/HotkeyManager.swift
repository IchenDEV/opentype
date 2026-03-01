import Foundation
import CoreGraphics
import AppKit

final class HotkeyManager {
    private let settings: AppSettings
    private let onStart: () -> Void
    private let onStop: () -> Void
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var hasPrompted = false

    private var lastPressTime: Date = .distantPast
    private var tapCount = 0
    private var wasPressed = false
    private var isHolding = false
    private var retryCount = 0
    private let maxRetries = 20

    init(settings: AppSettings, onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.settings = settings
        self.onStart = onStart
        self.onStop = onStop
    }

    func start() {
        if AXIsProcessTrusted() {
            createEventTap()
            setupGlobalMonitor()
            return
        }

        // Only prompt once per install — use UserDefaults to avoid nagging on every launch
        let key = "hotkeyAccessibilityPrompted"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        } else {
            Log.info("[HotkeyManager] Accessibility not granted, waiting silently (user was prompted before)")
        }

        setupGlobalMonitor()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.retryIfTrusted()
        }
    }

    private func retryIfTrusted() {
        guard eventTap == nil, retryCount < maxRetries else { return }
        retryCount += 1
        if AXIsProcessTrusted() {
            createEventTap()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.retryIfTrusted()
            }
        }
    }

    private func createEventTap() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyEventCallback,
            userInfo: refcon
        ) else {
            Log.info("[HotkeyManager] CGEvent tap failed, NSEvent fallback only")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func setupGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEventFlags(event)
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
    }

    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let pressed = isTargetKeyPressed(flags: flags)
        DispatchQueue.main.async { [weak self] in
            self?.processKeyState(isPressed: pressed)
        }
    }

    private func handleNSEventFlags(_ event: NSEvent) {
        guard eventTap == nil else { return }
        let flags = event.modifierFlags
        let pressed: Bool
        switch settings.hotkeyType {
        case .ctrl:   pressed = flags.contains(.control)
        case .shift:  pressed = flags.contains(.shift)
        case .option: pressed = flags.contains(.option)
        case .fn:     pressed = flags.contains(.function)
        }
        if Thread.isMainThread {
            processKeyState(isPressed: pressed)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.processKeyState(isPressed: pressed)
            }
        }
    }

    private func processKeyState(isPressed: Bool) {
        switch settings.activationMode {
        case .longPress:
            handleLongPress(isPressed: isPressed)
        case .doubleTap:
            handleDoubleTap(isPressed: isPressed)
        case .toggle:
            handleToggle(isPressed: isPressed)
        }
        wasPressed = isPressed
    }

    // MARK: - Long Press

    private func handleLongPress(isPressed: Bool) {
        if isPressed && !wasPressed && !isHolding {
            isHolding = true
            onStart()
        } else if !isPressed && wasPressed && isHolding {
            isHolding = false
            onStop()
        }
    }

    // MARK: - Double Tap

    private func handleDoubleTap(isPressed: Bool) {
        if isPressed && !wasPressed {
            let now = Date()
            if now.timeIntervalSince(lastPressTime) < settings.tapInterval {
                tapCount += 1
            } else {
                tapCount = 1
            }
            lastPressTime = now

            if tapCount >= 2 {
                tapCount = 0
                if isHolding {
                    isHolding = false
                    onStop()
                } else {
                    isHolding = true
                    onStart()
                }
            }
        }
    }

    // MARK: - Toggle (single tap)

    private func handleToggle(isPressed: Bool) {
        if isPressed && !wasPressed {
            if isHolding {
                isHolding = false
                onStop()
            } else {
                isHolding = true
                onStart()
            }
        }
    }

    private func isTargetKeyPressed(flags: CGEventFlags) -> Bool {
        switch settings.hotkeyType {
        case .ctrl:   return flags.contains(.maskControl)
        case .shift:  return flags.contains(.maskShift)
        case .option: return flags.contains(.maskAlternate)
        case .fn:     return flags.contains(.maskSecondaryFn)
        }
    }

    deinit { stop() }
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    manager.handleFlagsChanged(event)
    return Unmanaged.passRetained(event)
}
