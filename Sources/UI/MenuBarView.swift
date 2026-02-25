import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            header
            if hasVisibleContent {
                Divider()
                mainContent
            }
            Divider()
            bottomActions
        }
        .padding(10)
        .frame(width: 260)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .foregroundStyle(.tint)
            Text("OpenType")
                .font(.system(size: 13, weight: .semibold))
            Text(settings.inputLanguage.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(activationHint)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private var activationHint: String {
        let key = settings.hotkeyType.rawValue
        switch settings.activationMode {
        case .longPress: return "\(key) " + L("menubar.hold")
        case .doubleTap: return "\(key) ×2"
        case .toggle: return "\(key) " + L("menubar.toggle")
        }
    }

    // MARK: - Main content

    private var hasVisibleContent: Bool {
        appState.isRecording || appState.isDownloading || showActiveStatus
            || !appState.lastInsertedText.isEmpty
    }

    private var mainContent: some View {
        VStack(spacing: 6) {
            if appState.isRecording {
                recordingRow
            } else if appState.isDownloading {
                downloadSection
            } else if showActiveStatus {
                activeStatusRow
            } else if !appState.lastInsertedText.isEmpty {
                lastInsertedRow
            }
        }
    }

    private var showActiveStatus: Bool {
        switch appState.phase {
        case .transcribing, .processing, .inserting, .error: return true
        default: return false
        }
    }

    private var recordingRow: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Text(L("menubar.listening"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            WaveformView(level: appState.audioLevel)
                .frame(width: 40, height: 16)
        }
    }

    private var activeStatusRow: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    private var lastInsertedRow: some View {
        HStack(spacing: 6) {
            Text(appState.lastInsertedText)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appState.lastInsertedText, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("common.copy_clipboard"))
        }
    }

    private var downloadSection: some View {
        VStack(spacing: 3) {
            ProgressView(value: appState.downloadProgress)
                .progressViewStyle(.linear)
            HStack {
                Text(appState.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !appState.downloadSpeedText.isEmpty {
                    Text(appState.downloadSpeedText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Bottom

    private var bottomActions: some View {
        HStack {
            Button(action: onOpenSettings) {
                Label(L("common.settings"), systemImage: "gear")
            }
            .buttonStyle(.plain)
            .font(.caption)
            Spacer()
            Button(action: onQuit) {
                Label(L("common.quit"), systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch appState.phase {
        case .transcribing, .processing: return .orange
        case .inserting: return .yellow
        case .error: return .red
        default: return .gray
        }
    }
}
