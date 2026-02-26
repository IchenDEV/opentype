import Foundation
@preconcurrency import Speech
import AVFoundation

final class AppleSpeechEngine: SpeechEngine {
    private var recognizer: SFSpeechRecognizer
    private(set) var isReady = false

    /// Maximum time (seconds) to wait for the recognition task to deliver a final result.
    private static let timeoutSeconds: TimeInterval = 120

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()!

        let status = SFSpeechRecognizer.authorizationStatus()
        isReady = (status == .authorized)
    }

    func startListening() {}

    func requestAccess() {
        guard SFSpeechRecognizer.authorizationStatus() != .authorized else {
            isReady = true
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isReady = (status == .authorized)
            }
        }
    }

    func transcribe(audioURL: URL?, language: String?) async throws -> String {
        guard let url = audioURL else {
            throw AppleSpeechError.noAudioFile
        }

        if !isReady {
            requestAccess()
            try await Task.sleep(nanoseconds: 500_000_000)
            guard isReady else { throw AppleSpeechError.notAuthorized }
        }

        if let lang = language {
            let locale = Locale(identifier: lang == "zh" ? "zh-CN" : "en-US")
            if let newRecognizer = SFSpeechRecognizer(locale: locale) {
                recognizer = newRecognizer
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if #available(macOS 16, *) {
                request.addsPunctuation = true
            }

            var hasResumed = false
            var bestSoFar = ""

            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let result {
                    bestSoFar = result.bestTranscription.formattedString
                    if result.isFinal {
                        hasResumed = true
                        continuation.resume(returning: bestSoFar)
                    }
                }

                if let error, !hasResumed {
                    hasResumed = true
                    if bestSoFar.isEmpty {
                        continuation.resume(throwing: error)
                    } else {
                        Log.info("[AppleSpeech] task ended with error but has partial: \(error.localizedDescription)")
                        continuation.resume(returning: bestSoFar)
                    }
                }
            }

            // Timeout: if recognition hangs, return whatever we have collected.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) {
                guard !hasResumed else { return }
                hasResumed = true
                task.cancel()
                Log.info("[AppleSpeech] timeout after \(Self.timeoutSeconds)s, returning partial (\(bestSoFar.count) chars)")
                continuation.resume(returning: bestSoFar)
            }
        }
    }

}

enum AppleSpeechError: LocalizedError {
    case noAudioFile
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .noAudioFile: return L("error.no_audio_file")
        case .notAuthorized: return L("error.speech_not_authorized")
        }
    }
}
