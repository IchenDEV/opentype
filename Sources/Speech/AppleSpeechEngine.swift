import Foundation
@preconcurrency import Speech
import AVFoundation

final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    private var recognizer: SFSpeechRecognizer
    private(set) var isReady = false
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var bestSoFar = ""
    private var finishContinuation: CheckedContinuation<String, Error>?
    private let stateQueue = DispatchQueue(label: "opentype.apple-speech")

    /// Maximum time (seconds) to wait for the recognition task to deliver a final result.
    private static let timeoutSeconds: TimeInterval = 120

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()!

        let status = SFSpeechRecognizer.authorizationStatus()
        isReady = (status == .authorized)
    }

    var supportsStreaming: Bool { true }

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

    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        configureRecognizer(language: language)
        cancelListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 16, *) {
            request.addsPunctuation = true
        }

        bestSoFar = ""
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.bestSoFar = text
                onPartialResult(text)
                if result.isFinal {
                    self.finishStreaming(with: .success(text))
                }
            }

            if let error {
                if self.bestSoFar.isEmpty {
                    self.finishStreaming(with: .failure(error))
                } else {
                    Log.info("[AppleSpeech] task ended with error but has partial: \(error.localizedDescription)")
                    self.finishStreaming(with: .success(self.bestSoFar))
                }
            }
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func finishListening(audioURL: URL?, language: String?) async throws -> String {
        if recognitionRequest == nil {
            return try await transcribe(audioURL: audioURL, language: language)
        }

        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                self.finishContinuation = continuation
                self.recognitionRequest?.endAudio()
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) { [weak self] in
                guard let self else { return }
                self.stateQueue.async {
                    guard self.finishContinuation != nil else { return }
                    self.recognitionTask?.cancel()
                    let text = self.bestSoFar
                    self.resolveStreamingContinuation(.success(text))
                    Log.info("[AppleSpeech] timeout after \(Self.timeoutSeconds)s, returning partial (\(text.count) chars)")
                }
            }
        }
    }

    func cancelListening() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        stateQueue.async {
            guard self.finishContinuation != nil else { return }
            self.resolveStreamingContinuation(.success(self.bestSoFar))
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

        configureRecognizer(language: language)

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

    private func configureRecognizer(language: String?) {
        guard let language else { return }
        let localeId: String
        switch language {
        case "zh": localeId = "zh-CN"
        case "ja": localeId = "ja-JP"
        case "ko": localeId = "ko-KR"
        case "yue": localeId = "zh-HK"
        default: localeId = "en-US"
        }

        if let newRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)) {
            recognizer = newRecognizer
        }
    }

    private func finishStreaming(with result: Result<String, Error>) {
        stateQueue.async {
            self.resolveStreamingContinuation(result)
        }
    }

    private func resolveStreamingContinuation(_ result: Result<String, Error>) {
        let continuation = finishContinuation
        finishContinuation = nil
        recognitionTask = nil
        recognitionRequest = nil

        switch result {
        case .success(let text):
            continuation?.resume(returning: text)
        case .failure(let error):
            continuation?.resume(throwing: error)
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
