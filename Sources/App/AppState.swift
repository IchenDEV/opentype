import Foundation
import Combine

enum AppPhase: Equatable {
    case idle
    case downloading
    case recording
    case transcribing
    case processing
    case inserting
    case done
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle
    @Published var rawTranscription: String = ""
    @Published var processedText: String = ""
    @Published var audioLevel: Float = 0
    @Published var whisperModelReady = false
    @Published var llmModelReady = false
    @Published var downloadProgress: Double = 0
    @Published var downloadSizeText: String = ""
    @Published var downloadSpeedText: String = ""
    @Published var statusMessage: String = L("status.ready")
    @Published var lastInsertedText: String = ""

    let settings = AppSettings.shared

    var isRecording: Bool { phase == .recording }
    var isDownloading: Bool { phase == .downloading }

    var isBusy: Bool {
        switch phase {
        case .idle, .done, .error: return false
        default: return true
        }
    }

    func reset() {
        phase = .idle
        rawTranscription = ""
        processedText = ""
        audioLevel = 0
        statusMessage = L("status.ready")
    }
}
