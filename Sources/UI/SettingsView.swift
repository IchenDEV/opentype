import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var onUnloadWhisper: (() -> Void)?
    var onUnloadLLM: (() -> Void)?

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
            aboutTab
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
                Picker(L("settings.recognition_language"), selection: $settings.inputLanguage) {
                    ForEach(InputLanguage.allCases, id: \.self) { Text($0.rawValue) }
                }
            }

            Section(L("settings.audio")) {
                microphonePicker
                Toggle(isOn: $settings.useScreenContext) {
                    Text(L("settings.screen_context"))
                }
                .help(L("settings.screen_context_help"))
                Toggle(isOn: $settings.playSounds) {
                    Text(L("settings.sound_cues"))
                }
            }

            Section(L("settings.memory")) {
                Toggle(isOn: $settings.enableMemory) {
                    Text(L("settings.enable_memory"))
                }
                Picker(L("settings.memory_window"), selection: $settings.memoryWindowMinutes) {
                    Text(String(format: L("settings.memory_minutes_fmt"), 5)).tag(5)
                    Text(String(format: L("settings.memory_minutes_fmt"), 15)).tag(15)
                    Text(String(format: L("settings.memory_minutes_fmt"), 30)).tag(30)
                    Text(String(format: L("settings.memory_minutes_fmt"), 60)).tag(60)
                }
            }

            Section(L("settings.interface")) {
                Picker(L("settings.ui_language"), selection: $settings.uiLanguage) {
                    ForEach(UILanguage.allCases, id: \.self) { Text($0.displayName) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - About (with Permissions)

    private var aboutTab: some View {
        AboutView()
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
