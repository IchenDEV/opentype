import Foundation
import AVFoundation

protocol SpeechEngine: AnyObject {
    var isReady: Bool { get }
    var supportsStreaming: Bool { get }
    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void)
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func finishListening(audioURL: URL?, language: String?) async throws -> String
    func cancelListening()
    func transcribe(audioURL: URL?, language: String?) async throws -> String
}

extension SpeechEngine {
    var supportsStreaming: Bool { false }

    func startListening(language: String?, onPartialResult: @escaping @Sendable (String) -> Void) {
        let _ = language
        let _ = onPartialResult
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let _ = buffer
    }

    func finishListening(audioURL: URL?, language: String?) async throws -> String {
        try await transcribe(audioURL: audioURL, language: language)
    }

    func cancelListening() {}
}
