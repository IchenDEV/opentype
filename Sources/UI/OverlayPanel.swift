import SwiftUI
import AppKit

final class OverlayPanel {
    private var window: NSPanel?

    @MainActor
    func show(appState: AppState) {
        guard window == nil else { return }

        let panelWidth: CGFloat = 240
        let panelHeight: CGFloat = 48

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = OverlayContentView()
            .frame(width: panelWidth, height: panelHeight)
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let x = screen.frame.midX - panelWidth / 2
            let y = screen.frame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        window = panel
    }

    @MainActor
    func hide() {
        window?.close()
        window = nil
    }
}

private struct OverlayContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 16, height: 16)
            Text(appState.statusMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if appState.isRecording {
                WaveformView(level: appState.audioLevel)
                    .frame(width: 30, height: 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private var statusIcon: some View {
        Group {
            switch appState.phase {
            case .recording:
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
            case .transcribing:
                Image(systemName: "ellipsis")
                    .foregroundStyle(.yellow)
                    .symbolEffect(.variableColor.iterative)
            case .processing:
                Image(systemName: "brain")
                    .foregroundStyle(.orange)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            default:
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 14))
    }
}
