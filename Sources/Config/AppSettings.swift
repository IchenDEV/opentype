import Foundation
import Combine

enum UILanguage: String, Codable, CaseIterable {
    case chinese = "zh"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum OutputMode: String, Codable, CaseIterable {
    case direct = "direct"
    case processed = "processed"
    case command = "command"

    var label: String {
        switch self {
        case .direct: return L("mode.verbatim")
        case .processed: return L("mode.smart_format")
        case .command: return L("mode.voice_command")
        }
    }
}

enum SpeechEngineType: String, Codable, CaseIterable {
    case whisper = "whisper"
    case apple = "apple"

    var label: String {
        switch self {
        case .whisper: return "WhisperKit"
        case .apple: return L("engine.apple_speech")
        }
    }
}

enum LanguageStyle: String, Codable, CaseIterable {
    case concise = "concise"
    case formal = "formal"
    case professional = "professional"
    case casual = "casual"

    var label: String {
        switch self {
        case .concise: return L("style.concise")
        case .formal: return L("style.formal")
        case .professional: return L("style.professional")
        case .casual: return L("style.casual")
        }
    }

    var defaultPrompt: String {
        switch self {
        case .concise: return L("style.prompt.concise")
        case .formal: return L("style.prompt.formal")
        case .professional: return L("style.prompt.professional")
        case .casual: return L("style.prompt.casual")
        }
    }

    var icon: String {
        switch self {
        case .concise: return "scissors"
        case .formal: return "doc.text"
        case .professional: return "list.number"
        case .casual: return "bubble.left"
        }
    }
}

enum HotkeyType: String, Codable, CaseIterable {
    case ctrl = "Ctrl"
    case shift = "Shift"
    case option = "Option"
    case fn = "Fn"
}

enum ActivationMode: String, Codable, CaseIterable {
    case longPress = "longPress"
    case doubleTap = "doubleTap"
    case toggle = "toggle"

    var label: String {
        switch self {
        case .longPress: return L("mode.hold_record")
        case .doubleTap: return L("mode.double_tap")
        case .toggle: return L("mode.tap_toggle")
        }
    }
}

enum HistoryRetention: String, Codable, CaseIterable {
    case forever = "forever"
    case threeDays = "threeDays"
    case sevenDays = "sevenDays"
    case oneMonth = "oneMonth"

    var label: String {
        switch self {
        case .forever: return L("retention.forever")
        case .threeDays: return L("retention.three_days")
        case .sevenDays: return L("retention.seven_days")
        case .oneMonth: return L("retention.one_month")
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .forever: return nil
        case .threeDays: return 3 * 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .oneMonth: return 30 * 24 * 3600
        }
    }
}

enum InputLanguage: String, Codable, CaseIterable {
    case chinese = "中文"
    case english = "English"

    var whisperCode: String {
        switch self {
        case .chinese: return "zh"
        case .english: return "en"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hotkeyType: HotkeyType
    @Published var activationMode: ActivationMode
    @Published var tapInterval: Double
    @Published var speechEngine: SpeechEngineType
    @Published var whisperModel: String
    @Published var llmModel: String
    @Published var microphoneID: String?
    @Published var outputMode: OutputMode
    @Published var languageStyle: LanguageStyle
    @Published var customStylePrompt: String
    @Published var playSounds: Bool
    @Published var inputLanguage: InputLanguage
    @Published var useScreenContext: Bool
    @Published var hasCompletedOnboarding: Bool
    @Published var uiLanguage: UILanguage
    @Published var historyRetention: HistoryRetention
    @Published var enableMemory: Bool
    @Published var memoryWindowMinutes: Int
    @Published var useRemoteLLM: Bool
    @Published var remoteProvider: RemoteProvider
    @Published var remoteAPIKey: String
    @Published var remoteBaseURL: String
    @Published var remoteModel: String

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private enum Key: String {
        case hotkeyType, activationMode, tapInterval, speechEngine, whisperModel, llmModel
        case microphoneID, outputMode, languageStyle, customStylePrompt, playSounds
        case inputLanguage, useScreenContext, hasCompletedOnboarding, uiLanguage, historyRetention
        case enableMemory, memoryWindowMinutes
        case useRemoteLLM, remoteProvider, remoteAPIKey, remoteBaseURL, remoteModel
    }

    private init() {
        let ud = UserDefaults.standard
        hotkeyType = HotkeyType(rawValue: ud.string(forKey: Key.hotkeyType.rawValue) ?? "") ?? .fn
        let savedMode = ud.string(forKey: Key.activationMode.rawValue) ?? ""
        activationMode = ActivationMode(rawValue: savedMode)
            ?? (savedMode.contains("长按") ? .longPress : savedMode.contains("双击") ? .doubleTap : savedMode.contains("单击") ? .toggle : nil)
            ?? .longPress
        tapInterval = ud.double(forKey: Key.tapInterval.rawValue).nonZero ?? 0.4
        let savedEngine = ud.string(forKey: Key.speechEngine.rawValue) ?? ""
        speechEngine = SpeechEngineType(rawValue: savedEngine)
            ?? (savedEngine.contains("Whisper") || savedEngine.contains("whisper") ? .whisper : nil)
            ?? .apple
        whisperModel = ud.string(forKey: Key.whisperModel.rawValue) ?? "large-v3"
        llmModel = ud.string(forKey: Key.llmModel.rawValue) ?? "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
        microphoneID = ud.string(forKey: Key.microphoneID.rawValue)
        let savedOutput = ud.string(forKey: Key.outputMode.rawValue) ?? ""
        outputMode = OutputMode(rawValue: savedOutput)
            ?? (savedOutput.contains("整理") ? .processed : nil)
            ?? .processed
        let savedStyle = ud.string(forKey: Key.languageStyle.rawValue) ?? ""
        let style = LanguageStyle(rawValue: savedStyle)
            ?? (savedStyle.contains("简洁") ? .concise : savedStyle.contains("正式") ? .formal : savedStyle.contains("口语") ? .casual : nil)
            ?? .concise
        languageStyle = style
        if let savedPrompt = ud.string(forKey: Key.customStylePrompt.rawValue), !savedPrompt.isEmpty {
            customStylePrompt = savedPrompt
        } else {
            customStylePrompt = style.defaultPrompt
        }
        playSounds = ud.object(forKey: Key.playSounds.rawValue) as? Bool ?? true
        inputLanguage = InputLanguage(rawValue: ud.string(forKey: Key.inputLanguage.rawValue) ?? "") ?? .chinese
        useScreenContext = ud.object(forKey: Key.useScreenContext.rawValue) as? Bool ?? true
        hasCompletedOnboarding = ud.bool(forKey: Key.hasCompletedOnboarding.rawValue)
        uiLanguage = UILanguage(rawValue: ud.string(forKey: Key.uiLanguage.rawValue) ?? "") ?? .chinese
        historyRetention = HistoryRetention(rawValue: ud.string(forKey: Key.historyRetention.rawValue) ?? "") ?? .forever
        enableMemory = ud.object(forKey: Key.enableMemory.rawValue) as? Bool ?? true
        memoryWindowMinutes = (ud.integer(forKey: Key.memoryWindowMinutes.rawValue)).nonZeroInt ?? 30
        useRemoteLLM = ud.bool(forKey: Key.useRemoteLLM.rawValue)
        remoteProvider = RemoteProvider(rawValue: ud.string(forKey: Key.remoteProvider.rawValue) ?? "") ?? .custom
        remoteAPIKey = ud.string(forKey: Key.remoteAPIKey.rawValue) ?? ""
        remoteBaseURL = ud.string(forKey: Key.remoteBaseURL.rawValue) ?? ""
        remoteModel = ud.string(forKey: Key.remoteModel.rawValue) ?? ""

        setupPersistence()
    }

    private func setupPersistence() {
        $hotkeyType.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.hotkeyType.rawValue) }.store(in: &cancellables)
        $activationMode.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.activationMode.rawValue) }.store(in: &cancellables)
        $tapInterval.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.tapInterval.rawValue) }.store(in: &cancellables)
        $speechEngine.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.speechEngine.rawValue) }.store(in: &cancellables)
        $whisperModel.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.whisperModel.rawValue) }.store(in: &cancellables)
        $llmModel.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.llmModel.rawValue) }.store(in: &cancellables)
        $microphoneID.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.microphoneID.rawValue) }.store(in: &cancellables)
        $outputMode.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.outputMode.rawValue) }.store(in: &cancellables)
        $languageStyle.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.languageStyle.rawValue) }.store(in: &cancellables)
        $customStylePrompt.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.customStylePrompt.rawValue) }.store(in: &cancellables)
        $playSounds.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.playSounds.rawValue) }.store(in: &cancellables)
        $inputLanguage.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.inputLanguage.rawValue) }.store(in: &cancellables)
        $useScreenContext.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.useScreenContext.rawValue) }.store(in: &cancellables)
        $hasCompletedOnboarding.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.hasCompletedOnboarding.rawValue) }.store(in: &cancellables)
        $uiLanguage.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.uiLanguage.rawValue) }.store(in: &cancellables)
        $historyRetention.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.historyRetention.rawValue) }.store(in: &cancellables)
        $enableMemory.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.enableMemory.rawValue) }.store(in: &cancellables)
        $memoryWindowMinutes.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.memoryWindowMinutes.rawValue) }.store(in: &cancellables)
        $useRemoteLLM.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.useRemoteLLM.rawValue) }.store(in: &cancellables)
        $remoteProvider.dropFirst().sink { [defaults] in defaults.set($0.rawValue, forKey: Key.remoteProvider.rawValue) }.store(in: &cancellables)
        $remoteAPIKey.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.remoteAPIKey.rawValue) }.store(in: &cancellables)
        $remoteBaseURL.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.remoteBaseURL.rawValue) }.store(in: &cancellables)
        $remoteModel.dropFirst().sink { [defaults] in defaults.set($0, forKey: Key.remoteModel.rawValue) }.store(in: &cancellables)
    }

    var zh: Bool { uiLanguage == .chinese }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZeroInt: Int? { self == 0 ? nil : self }
}
