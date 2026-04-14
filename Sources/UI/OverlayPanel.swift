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
    @State private var fakeProgress: Double = 0
    @State private var progressTimer: Timer?

    private var showsProgress: Bool {
        switch appState.phase {
        case .transcribing, .processing, .inserting: return true
        default: return false
        }
    }

    private var livePreview: String? {
        guard appState.isRecording else { return nil }
        let text = appState.rawTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.vertical, showsProgress ? 8 : 10)

            if let livePreview {
                Text(livePreview)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if showsProgress {
                GeometryReader { geo in
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.orange)
                                .frame(width: geo.size.width * fakeProgress, height: 3)
                        }
                }
                .frame(height: 3)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .onChange(of: appState.phase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .animation(.easeInOut(duration: 0.3), value: fakeProgress)
        .animation(.easeInOut(duration: 0.2), value: showsProgress)
    }

    private func handlePhaseChange(_ phase: AppPhase) {
        progressTimer?.invalidate()
        progressTimer = nil

        switch phase {
        case .transcribing:
            fakeProgress = 0.05
            startProgressTimer(target: 0.3, step: 0.04, interval: 0.15)
        case .processing:
            if fakeProgress < 0.3 { fakeProgress = 0.3 }
            startProgressTimer(target: 0.92, step: 0.01, interval: 0.3)
        case .inserting:
            fakeProgress = 0.95
        case .done:
            fakeProgress = 1.0
        default:
            fakeProgress = 0
        }
    }

    private func startProgressTimer(target: Double, step: Double, interval: TimeInterval) {
        progressTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                if fakeProgress < target {
                    fakeProgress = min(fakeProgress + step, target)
                }
            }
        }
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
            case .processing, .inserting:
                Image(systemName: "brain")
                    .foregroundStyle(.orange)
            case .downloading:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
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
