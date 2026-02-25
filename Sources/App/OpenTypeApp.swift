import SwiftUI
import AppKit
import Combine

@main
struct OpenTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let appState = AppState()
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var hotkeyManager: HotkeyManager?
    private var pipeline: VoicePipeline?
    private var settingsWindow: NSWindow?
    private var settingsWindowDelegate: SettingsWindowDelegate?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var iconTimer: Timer?
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIcon.install()
        setupMenuBar()
        setupPipeline()
        setupHotkey()
        observePhaseForIcon()

        if !AppSettings.shared.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = Self.micIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        let contentView = MenuBarView(
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        .environmentObject(appState)
        .environmentObject(AppSettings.shared)

        popover.contentSize = NSSize(width: 260, height: 160)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupPipeline() {
        pipeline = VoicePipeline(appState: appState)
        Task { await pipeline?.warmUp() }
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager(
            settings: AppSettings.shared,
            onStart: { [weak self] in
                Task { @MainActor in self?.startRecording() }
            },
            onStop: { [weak self] in
                Task { @MainActor in self?.stopRecording() }
            }
        )
        hotkeyManager?.start()
    }

    private func observePhaseForIcon() {
        appState.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .recording:
                    self.startAnimatingIcon()
                default:
                    self.stopAnimatingIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func startAnimatingIcon() {
        iconTimer?.invalidate()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.statusItem?.button?.image = Self.recordingIcon(level: self.appState.audioLevel)
            }
        }
    }

    private func stopAnimatingIcon() {
        iconTimer?.invalidate()
        iconTimer = nil
        statusItem?.button?.image = Self.micIcon()
    }

    // MARK: - Icon drawing

    private static func micIcon() -> NSImage {
        guard let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "OpenType") else {
            return NSImage()
        }
        img.isTemplate = true
        return img
    }

    private static func recordingIcon(level: Float) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let bgRect = rect.insetBy(dx: 0.5, dy: 0.5)
            NSColor.systemYellow.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()

            let barCount = 5
            let barWidth: CGFloat = 1.5
            let spacing: CGFloat = 1.2
            let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
            let startX = (rect.width - totalW) / 2
            let maxH: CGFloat = rect.height - 6
            let time = Date().timeIntervalSinceReferenceDate

            NSColor.black.withAlphaComponent(0.75).setFill()
            for i in 0..<barCount {
                let offset = Double(i) / Double(barCount) * .pi * 2
                let wave = (sin(time * 10 + offset) + 1) / 2
                let normalized = CGFloat(max(level, 0.15))
                let barH = max(2, normalized * maxH * CGFloat(wave))
                let x = startX + CGFloat(i) * (barWidth + spacing)
                let y = (rect.height - barH) / 2
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barH), xRadius: 0.5, yRadius: 0.5).fill()
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            savePreviousApp()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func savePreviousApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
    }

    private func startRecording() {
        savePreviousApp()
        if popover.isShown { popover.performClose(nil) }
        Task { await pipeline?.start() }
    }

    private func stopRecording() {
        Task { await pipeline?.stop(targetApp: previousApp) }
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        let view = OnboardingView {
            AppSettings.shared.hasCompletedOnboarding = true
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenType"
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false

        onboardingWindow = window

        NSApp.setActivationPolicy(.regular)
        AppIcon.install()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    private func openSettings() {
        if popover.isShown { popover.performClose(nil) }

        if let existing = settingsWindow, existing.isVisible {
            NSApp.setActivationPolicy(.regular)
            AppIcon.install()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            onUnloadWhisper: { [weak self] in self?.pipeline?.unloadWhisper() },
            onUnloadLLM: { [weak self] in self?.pipeline?.unloadLLM() }
        )
        .environmentObject(appState)
        .environmentObject(AppSettings.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenType Settings"
        window.center()
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false

        let delegate = SettingsWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = delegate
        settingsWindowDelegate = delegate
        settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        AppIcon.install()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
