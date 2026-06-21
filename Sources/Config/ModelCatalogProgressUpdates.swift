import Foundation

@MainActor
extension ModelCatalog {
    func updateLLMDownloadProgress(_ id: String, info: DownloadProgressInfo) {
        guard let i = llmModels.firstIndex(where: { $0.id == id }) else { return }
        llmModels[i].status = .downloading
        llmModels[i].downloadProgress = info.fraction
        llmModels[i].downloadDetail = info.detailText
    }
}
