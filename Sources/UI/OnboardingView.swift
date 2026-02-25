import SwiftUI
import AVFoundation
import Speech

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var step = 0
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcomePage
                case 1: permissionsPage
                default: readyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: step)

            Divider()
            navigationBar
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text(L("onboarding.welcome"))
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(L("onboarding.welcome_body"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 24) {
                featureBadge(icon: "mic.fill", label: L("onboarding.voice_input"))
                featureBadge(icon: "brain", label: L("onboarding.smart_format"))
                featureBadge(icon: "lock.shield", label: L("onboarding.local"))
            }
            .padding(.top, 8)

            // Language selector on welcome page
            HStack(spacing: 8) {
                Text(L("onboarding.language"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.uiLanguage) {
                    ForEach(UILanguage.allCases, id: \.self) { Text($0.displayName) }
                }
                .labelsHidden()
                .frame(width: 100)
            }
            .padding(.top, 4)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
    }

    private func featureBadge(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions

    @State private var axGranted = false
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var screenGranted = false

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("onboarding.grant_permissions"))
                    .font(.system(size: 20, weight: .bold))
                Text(L("onboarding.permissions_body"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            VStack(spacing: 0) {
                onboardPermissionRow(
                    icon: "hand.raised.fill",
                    name: L("perm.accessibility"),
                    hint: L("perm.accessibility_hint"),
                    granted: axGranted,
                    required: true
                ) { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
                Divider().padding(.horizontal, 12)
                onboardPermissionRow(
                    icon: "mic.fill",
                    name: L("perm.microphone"),
                    hint: L("perm.microphone_hint"),
                    granted: micGranted,
                    required: true
                ) { AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in refreshPermissions() } } }
                Divider().padding(.horizontal, 12)
                onboardPermissionRow(
                    icon: "waveform",
                    name: L("perm.speech"),
                    hint: L("perm.speech_hint"),
                    granted: speechGranted,
                    required: false
                ) { SFSpeechRecognizer.requestAuthorization { _ in Task { @MainActor in refreshPermissions() } } }
                Divider().padding(.horizontal, 12)
                onboardPermissionRow(
                    icon: "rectangle.dashed.badge.record",
                    name: L("perm.screen"),
                    hint: L("perm.screen_hint"),
                    granted: screenGranted,
                    required: false
                ) {
                    ScreenOCR.requestPermissionIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshPermissions() }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

            HStack {
                Spacer()
                Button {
                    refreshPermissions()
                } label: {
                    Label(L("common.refresh"), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear { refreshPermissions() }
    }

    private func onboardPermissionRow(
        icon: String, name: String, hint: String,
        granted: Bool, required: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 26)
                .foregroundStyle(granted ? .green : (required ? .orange : .secondary))

            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            } else {
                Button(L("perm.grant"), action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func refreshPermissions() {
        axGranted = AXIsProcessTrusted()
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        screenGranted = ScreenOCR.hasScreenCapturePermission
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Ready

    private var readyPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text(L("onboarding.all_set"))
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(L("onboarding.ready_body"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            HStack(spacing: 6) {
                Image(systemName: "fn")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text(L("onboarding.hold_hint"))
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack {
            if step > 0 {
                Button(L("common.back")) { step -= 1 }
                    .controlSize(.regular)
            }
            Spacer()
            stepIndicator
            Spacer()
            if step < 2 {
                Button(L("common.continue")) { step += 1 }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L("onboarding.get_started")) { onComplete() }
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
