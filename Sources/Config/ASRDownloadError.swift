import Foundation

enum ASRDownloadError: LocalizedError {
    case incompleteRuntime
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompleteRuntime:
            return L("model.asr_runtime_incomplete")
        case .processFailed(let message):
            return message.isEmpty ? L("model.asr_runtime_download_failed") : message
        }
    }
}
