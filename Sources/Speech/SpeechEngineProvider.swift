import Foundation

@MainActor
final class SpeechEngineProvider {
    private var whisperEngine: WhisperEngine?
    private var appleSpeechEngine: AppleSpeechEngine?
    private var volcSpeechEngine: VolcSpeechEngine?
    private var qwenSpeechEngine: LocalASREngine?
    private var mimoSpeechEngine: LocalASREngine?

    func engine(settings: AppSettings, requestPermission: Bool = true) async -> (any SpeechEngine)? {
        await ensureEngineLoaded(settings: settings, requestPermission: requestPermission)
        return currentEngine(for: settings.speechEngine)
    }

    private func currentEngine(for type: SpeechEngineType) -> (any SpeechEngine)? {
        switch type {
        case .whisper: return whisperEngine
        case .apple: return appleSpeechEngine
        case .volc: return volcSpeechEngine
        case .qwen3: return qwenSpeechEngine
        case .mimo: return mimoSpeechEngine
        }
    }

    private func ensureEngineLoaded(settings: AppSettings, requestPermission: Bool) async {
        switch settings.speechEngine {
        case .whisper:
            await ensureWhisperLoaded(modelID: settings.whisperModel)
        case .apple:
            if appleSpeechEngine == nil {
                let locale = Locale(identifier: settings.inputLanguage.localeIdentifier)
                appleSpeechEngine = AppleSpeechEngine(locale: locale)
            }
            if requestPermission, !(appleSpeechEngine?.isReady ?? false) {
                appleSpeechEngine?.requestAccess()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        case .volc:
            volcSpeechEngine = VolcSpeechEngine(
                appKey: settings.volcAppKey,
                accessKey: settings.volcAccessKey,
                resourceId: settings.volcResourceId
            )
        case .qwen3:
            await ensureLocalASRAvailable(modelID: settings.qwenASRModel)
            qwenSpeechEngine = LocalASREngine(configuration: LocalASRConfiguration(
                provider: .qwen3,
                pythonPath: settings.localASRPythonPath,
                modelPath: ModelCatalog.shared.asrModelPath(for: settings.qwenASRModel),
                tokenizerPath: "",
                repoPath: ""
            ))
        case .mimo:
            await ensureLocalASRAvailable(modelID: settings.mimoASRModel)
            mimoSpeechEngine = LocalASREngine(configuration: LocalASRConfiguration(
                provider: .mimo,
                pythonPath: settings.localASRPythonPath,
                modelPath: ModelCatalog.shared.asrModelPath(for: settings.mimoASRModel),
                tokenizerPath: ModelCatalog.shared.mimoTokenizerPath(),
                repoPath: ModelCatalog.shared.mimoRepositoryPath()
            ))
        }
    }

    private func ensureWhisperLoaded(modelID: String) async {
        if let engine = whisperEngine, engine.isReady || engine.isLoading {
            return
        }

        let engine = WhisperEngine(modelName: modelID)
        whisperEngine = engine
        let catalog = ModelCatalog.shared
        let alreadyDownloaded = catalog.isWhisperDownloaded(modelID)
        catalog.updateWhisperStatus(modelID, status: alreadyDownloaded ? .loading : .downloading)

        do {
            try await engine.loadModel { progress in
                switch progress.stage {
                case .downloading:
                    if alreadyDownloaded {
                        catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                    } else {
                        let pct = Int(min(progress.fraction / 0.6, 1.0) * 100)
                        catalog.updateWhisperStatus(modelID, status: .downloading, detail: "\(pct)%")
                    }
                case .compiling:
                    catalog.updateWhisperStatus(modelID, status: .compiling, detail: L("model.loading"))
                case .loading:
                    catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                case .done:
                    break
                }
            }
            catalog.updateWhisperStatus(modelID, status: .ready)
        } catch {
            catalog.updateWhisperStatus(modelID, status: .error(error.localizedDescription))
            Log.error("[SpeechEngineProvider] Whisper load failed: \(error.localizedDescription)")
        }
    }

    private func ensureLocalASRAvailable(modelID: String) async {
        let catalog = ModelCatalog.shared
        catalog.refreshASRStatus(recheckingErrors: true)
        guard !localASRIsAvailable(modelID) else { return }
        await catalog.downloadASR(modelID)
    }

    private func localASRIsAvailable(_ modelID: String) -> Bool {
        guard let status = ModelCatalog.shared.asrModels.first(where: { $0.id == modelID })?.status else {
            return false
        }
        return status == .downloaded || status == .ready
    }
}
