import AppKit
import SwiftUI

final class OverlayPanel {
    private var window: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    @MainActor
    func show(appState: AppState) {
        let initialLayout = OverlayLayout(appState: appState)

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: initialLayout.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = OverlayContentView { [weak self] layout in
                Task { @MainActor in
                    self?.apply(layout: layout, animated: true)
                }
            }
            .environmentObject(appState)

            let hostingView = NSHostingView(rootView: AnyView(view))
            hostingView.frame = NSRect(origin: .zero, size: initialLayout.panelSize)
            panel.contentView = hostingView

            self.window = panel
            self.hostingView = hostingView
        }

        apply(layout: initialLayout, animated: false)
        window?.orderFrontRegardless()
    }

    @MainActor
    func hide() {
        window?.close()
        window = nil
        hostingView = nil
    }

    @MainActor
    private func apply(layout: OverlayLayout, animated: Bool) {
        guard let window, let hostingView else { return }
        let frame = frame(for: layout.panelSize, window: window)

        hostingView.frame = NSRect(origin: .zero, size: layout.panelSize)
        window.setFrame(frame, display: true, animate: animated)
    }

    @MainActor
    private func frame(for size: CGSize, window: NSWindow) -> NSRect {
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - 28
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}
