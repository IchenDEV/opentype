import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?
    @State private var showPermissions = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L("tab.general"), systemImage: "gear") }
            ModelManagementView(onUnloadWhisper: onUnloadWhisper, onUnloadLLM: onUnloadLLM)
                .tabItem { Label(L("tab.models"), systemImage: "cpu") }
            DictionaryStyleView()
                .tabItem { Label(L("tab.style"), systemImage: "text.book.closed") }
            HistoryStatsView()
                .tabItem { Label(L("tab.history"), systemImage: "clock.arrow.circlepath") }
            AboutView()
                .tabItem { Label(L("tab.about"), systemImage: "info.circle") }
        }
        .frame(width: 640, height: 520)
        .id(settings.uiLanguage)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section(L("settings.activation")) {
                Picker(L("settings.hotkey"), selection: $settings.hotkeyType) {
                    ForEach(HotkeyType.allCases, id: \.self) { Text($0.rawValue) }
                }
                Picker(L("settings.mode"), selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { Text($0.label) }
                }
                if settings.activationMode == .doubleTap {
                    HStack {
                        Text(L("settings.tap_interval"))
                        Slider(value: $settings.tapInterval, in: 0.2...0.8, step: 0.05)
                        Text("\(settings.tapInterval, specifier: "%.2f")s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }

            Section(L("settings.output")) {
                Picker(L("settings.output_mode"), selection: $settings.outputMode) {
                    ForEach(OutputMode.allCases, id: \.self) { Text($0.label) }
                }
            }

            Section(L("settings.voice_language")) {
                Picker(L("settings.ui_language"), selection: $settings.uiLanguage) {
                    ForEach(UILanguage.allCases, id: \.self) { Text($0.displayName) }
                }
                Picker(L("settings.recognition_language"), selection: $settings.inputLanguage) {
                    ForEach(InputLanguage.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle(L("settings.sound_cues"), isOn: $settings.playSounds)
                microphonePicker
                Toggle(L("settings.screen_context"), isOn: $settings.useScreenContext)
                    .help(L("settings.screen_context_help"))
            }

            Section {
                Button {
                    showPermissions = true
                } label: {
                    Label(L("settings.permissions"), systemImage: "lock.shield")
                }
                .sheet(isPresented: $showPermissions) {
                    PermissionsView()
                        .environmentObject(settings)
                        .frame(width: 480, height: 380)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("common.done")) { showPermissions = false }
                            }
                        }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var microphonePicker: some View {
        let mics = AudioCaptureManager.availableMicrophones()
        return Picker(L("settings.microphone"), selection: $settings.microphoneID) {
            Text(L("settings.system_default")).tag(nil as String?)
            ForEach(mics, id: \.id) { mic in
                Text(mic.name).tag(mic.id as String?)
            }
        }
    }
}
