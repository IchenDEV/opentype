import Foundation

enum StartupModelPreloadPolicy {
    static func shouldPreloadSpeechModel(
        enabled: Bool,
        speechEngine: SpeechEngineType
    ) -> Bool {
        enabled && speechEngine == .whisper
    }

    static func shouldPreloadFormattingModel(
        enabled: Bool,
        useRemoteLLM: Bool,
        modelID: String
    ) -> Bool {
        enabled && !useRemoteLLM && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
