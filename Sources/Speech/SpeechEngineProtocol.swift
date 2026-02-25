import Foundation

protocol SpeechEngine: AnyObject {
    var isReady: Bool { get }
    func startListening()
    func transcribe(audioURL: URL?, language: String?) async throws -> String
}
