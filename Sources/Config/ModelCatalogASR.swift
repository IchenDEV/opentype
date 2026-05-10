import Foundation
import Hub

extension ModelCatalog {
    static var defaultASRModels: [
        (id: String, displayName: String, hint: String, provider: LocalASRConfiguration.Provider)
    ] {
        [
            (
                LocalASRConfiguration.qwen3DefaultModel,
                "Qwen3-ASR 1.7B",
                L("model.qwen3_asr_quality"),
                .qwen3
            ),
            (
                LocalASRConfiguration.mimoDefaultModel,
                "MiMo-V2.5-ASR",
                L("model.mimo_asr_quality"),
                .mimo
            ),
        ]
    }

    func asrModels(for provider: LocalASRConfiguration.Provider) -> [ModelEntry] {
        asrModels.filter { asrProvider(for: $0.id) == provider }
    }

    func asrProvider(for id: String) -> LocalASRConfiguration.Provider? {
        Self.defaultASRModels.first { $0.id == id }?.provider
    }

    func asrModelPath(for id: String) -> String {
        ModelStorage.asrRepoDir(id)?.path ?? ""
    }

    func mimoTokenizerPath() -> String {
        ModelStorage.asrRepoDir(LocalASRConfiguration.mimoTokenizerModel)?.path ?? ""
    }

    func refreshASRStatus(recheckingErrors: Bool = false) {
        for i in asrModels.indices where !asrModels[i].status.isBusy {
            let id = asrModels[i].id
            let size = asrRepoSize(id)
            asrModels[i].cacheSize = size
            if recheckingErrors || (asrModels[i].status != .ready && !asrModels[i].status.isError) {
                asrModels[i].status = asrRepoIsComplete(id)
                    ? .downloaded
                    : (size > 0 ? .error(L("model.asr_incomplete")) : .notDownloaded)
            }
        }
    }

    func downloadASR(_ id: String) async {
        guard let idx = asrModels.firstIndex(where: { $0.id == id }),
              !asrModels[idx].status.isDownloading else { return }

        if asrRepoIsComplete(id) {
            asrModels[idx].status = .downloaded
            asrModels[idx].cacheSize = asrRepoSize(id)
            asrModels[idx].downloadDetail = ""
            return
        }

        asrModels[idx].status = .downloading
        asrModels[idx].downloadProgress = 0
        asrModels[idx].downloadDetail = ""

        do {
            let repos = asrRequiredRepoIDs(for: id)
            let api = HubApi(downloadBase: ModelStorage.huggingFaceBase)
            for (repoIndex, repoID) in repos.enumerated() {
                _ = try await api.snapshot(from: repoID) { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              let i = self.asrModels.firstIndex(where: { $0.id == id }) else { return }
                        let fraction = (Double(repoIndex) + progress.fractionCompleted) / Double(repos.count)
                        self.asrModels[i].downloadProgress = fraction
                        self.asrModels[i].downloadDetail = "\(Int(fraction * 100))%"
                    }
                }
            }
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = .downloaded
                asrModels[i].cacheSize = asrRepoSize(id)
                asrModels[i].downloadDetail = ""
            }
        } catch is CancellationError {
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = asrRepoIsComplete(id) ? .downloaded : .notDownloaded
                asrModels[i].downloadDetail = ""
            }
        } catch {
            if let i = asrModels.firstIndex(where: { $0.id == id }) {
                asrModels[i].status = .error(error.localizedDescription)
                asrModels[i].cacheSize = asrRepoSize(id)
                asrModels[i].downloadDetail = ""
            }
        }
    }

    func deleteASR(_ id: String) {
        guard let idx = asrModels.firstIndex(where: { $0.id == id }) else { return }
        let provider = asrProvider(for: id)
        for repoID in asrRequiredRepoIDs(for: id) {
            try? FileManager.default.removeItem(at: ModelStorage.hubRepoCacheDir(repoID))
        }
        asrModels[idx].status = .notDownloaded
        asrModels[idx].cacheSize = 0
        asrModels[idx].downloadDetail = ""

        let settings = AppSettings.shared
        if provider == .qwen3, settings.qwenASRModel == id {
            settings.qwenASRModel = nextAvailableASR(for: .qwen3, excluding: id) ?? id
        }
        if provider == .mimo, settings.mimoASRModel == id {
            settings.mimoASRModel = nextAvailableASR(for: .mimo, excluding: id) ?? id
        }
    }

    func nextAvailableASR(for provider: LocalASRConfiguration.Provider, excluding id: String) -> String? {
        asrModels.first {
            $0.id != id &&
            asrProvider(for: $0.id) == provider &&
            ($0.status == .downloaded || $0.status == .ready)
        }?.id
    }

    private func asrRequiredRepoIDs(for id: String) -> [String] {
        if asrProvider(for: id) == .mimo {
            return [id, LocalASRConfiguration.mimoTokenizerModel]
        }
        return [id]
    }

    private func asrRepoIsComplete(_ id: String) -> Bool {
        asrRequiredRepoIDs(for: id).allSatisfy { asrSingleRepoSize($0) > 0 }
    }

    private func asrRepoSize(_ id: String) -> Int64 {
        asrRequiredRepoIDs(for: id).reduce(Int64(0)) { $0 + asrSingleRepoSize($1) }
    }

    private func asrSingleRepoSize(_ id: String) -> Int64 {
        guard let dir = ModelStorage.asrRepoDir(id) else { return 0 }
        return ModelStorage.directorySize(at: dir)
    }
}
