import Foundation
import Speech
import AVFoundation

final class AppleSpeechEngine: SpeechEngine {
    private var recognizer: SFSpeechRecognizer
    private(set) var isReady = false

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()!
        requestAuthorization()
    }

    func startListening() {}

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let url = audioURL else {
            throw AppleSpeechError.noAudioFile
        }
        guard isReady else {
            throw AppleSpeechError.notAuthorized
        }

        if let lang = language {
            let locale = Locale(identifier: lang == "zh" ? "zh-CN" : "en-US")
            if let newRecognizer = SFSpeechRecognizer(locale: locale) {
                recognizer = newRecognizer
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isReady = (status == .authorized)
            }
        }
    }
}

enum AppleSpeechError: LocalizedError {
    case noAudioFile
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .noAudioFile: return "没有录音文件"
        case .notAuthorized: return "语音识别未授权"
        }
    }
}
