import Foundation

@MainActor
extension VoicePipeline {
    func unloadWhisper() {
        whisperEngine?.unload()
        whisperEngine = nil
        appState.whisperModelReady = false
        appState.statusMessage = L("pipeline.whisper_unloaded")
    }

    func unloadLLM() {
        processingTask?.cancel()
        processingTask = nil
        replacementTask?.cancel()
        replacementTask = nil
        appState.clearPendingReplacement()
        if appState.phase == .processing {
            appState.phase = .idle
            appState.statusMessage = L("status.ready")
        }
        appState.llmModelReady = false
        Task { await textProcessor.unloadLLM() }
    }

    func unloadLocalASR() {
        qwenSpeechEngine = nil
        mimoSpeechEngine = nil
    }

    func loadLLM() {
        Task {
            await preloadFormattingModel(showFailureInStatus: true)
        }
    }

    func preloadFormattingModel(showFailureInStatus: Bool) async {
        guard !appState.settings.useRemoteLLM else {
            appState.llmModelReady = true
            return
        }

        let model = appState.settings.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }

        appState.statusMessage = L("pipeline.loading_llm")
        let catalog = ModelCatalog.shared
        catalog.updateLLMStatus(model, status: .loading, detail: L("model.loading"))

        let loaded = await textProcessor.warmUpLLM(model: model)
        let ready = await textProcessor.isLLMReady
        appState.llmModelReady = loaded && ready

        if appState.llmModelReady {
            catalog.updateLLMStatus(model, status: .ready)
            Log.info("[VoicePipeline] LLM model loaded into memory, ready for instant inference")
            appState.statusMessage = L("status.ready")
        } else {
            catalog.updateLLMStatus(model, status: .error(L("pipeline.model_load_failed")))
            Log.info("[VoicePipeline] LLM warmup failed, will retry on demand")
            appState.statusMessage = showFailureInStatus ? L("pipeline.model_load_failed") : L("status.ready")
        }
    }

    func ensureEngineLoaded(requestPermission: Bool = true) async {
        switch appState.settings.speechEngine {
        case .whisper:
            await ensureWhisperLoaded()
        case .apple:
            if appleSpeechEngine == nil {
                let locale = Locale(identifier: appState.settings.inputLanguage.localeIdentifier)
                appleSpeechEngine = AppleSpeechEngine(locale: locale)
            }
            if requestPermission, !(appleSpeechEngine?.isReady ?? false) {
                appleSpeechEngine?.requestAccess()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        case .volc:
            let settings = appState.settings
            volcSpeechEngine = VolcSpeechEngine(
                appKey: settings.volcAppKey,
                accessKey: settings.volcAccessKey,
                resourceId: settings.volcResourceId
            )
        case .qwen3:
            let settings = appState.settings
            let catalog = ModelCatalog.shared
            await ensureLocalASRAvailable(modelID: settings.qwenASRModel)
            qwenSpeechEngine = LocalASREngine(configuration: LocalASRConfiguration(
                provider: .qwen3,
                pythonPath: settings.localASRPythonPath,
                modelPath: catalog.asrModelPath(for: settings.qwenASRModel),
                tokenizerPath: "",
                repoPath: ""
            ))
        case .mimo:
            let settings = appState.settings
            let catalog = ModelCatalog.shared
            mimoSpeechEngine = LocalASREngine(configuration: LocalASRConfiguration(
                provider: .mimo,
                pythonPath: settings.localASRPythonPath,
                modelPath: catalog.asrModelPath(for: settings.mimoASRModel),
                tokenizerPath: catalog.mimoTokenizerPath(),
                repoPath: catalog.mimoRepositoryPath()
            ))
        }
    }

    private func ensureLocalASRAvailable(modelID: String) async {
        let catalog = ModelCatalog.shared
        catalog.refreshASRStatus(recheckingErrors: true)
        guard !localASRIsAvailable(modelID) else { return }

        appState.phase = .downloading
        appState.statusMessage = L("pipeline.preparing_model")
        appState.downloadProgress = 0
        await catalog.downloadASR(modelID)
        appState.downloadProgress = 0
        appState.phase = .idle
        appState.statusMessage = localASRIsAvailable(modelID) ? L("status.ready") : L("pipeline.model_load_failed")
    }

    private func localASRIsAvailable(_ modelID: String) -> Bool {
        guard let status = ModelCatalog.shared.asrModels.first(where: { $0.id == modelID })?.status else {
            return false
        }
        return status == .downloaded || status == .ready
    }

    private func ensureWhisperLoaded() async {
        if let engine = whisperEngine {
            if engine.isReady || engine.isLoading { return }
        }

        let modelID = appState.settings.whisperModel
        let engine = WhisperEngine(modelName: modelID)
        whisperEngine = engine
        let catalog = ModelCatalog.shared

        let alreadyDownloaded = catalog.isWhisperDownloaded(modelID)
        appState.phase = .downloading
        appState.statusMessage = L("pipeline.preparing_model")
        appState.downloadProgress = 0
        catalog.updateWhisperStatus(modelID, status: .downloading)

        var lastSpeedText = ""
        var lastSizeText = ""

        do {
            try await engine.loadModel { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.appState.downloadProgress = progress.fraction

                    if !progress.sizeText.isEmpty { lastSizeText = progress.sizeText }
                    if !progress.speedText.isEmpty { lastSpeedText = progress.speedText }

                    switch progress.stage {
                    case .downloading:
                        if alreadyDownloaded {
                            self.appState.statusMessage = L("pipeline.loading_model")
                            self.appState.downloadSizeText = ""
                            self.appState.downloadSpeedText = ""
                            catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                        } else {
                            let pct = Int(min(progress.fraction / 0.6, 1.0) * 100)
                            let speed = lastSpeedText.isEmpty ? "" : " · \(lastSpeedText)"
                            self.appState.statusMessage = L("pipeline.downloading") + " \(pct)%\(speed)"
                            self.appState.downloadSizeText = lastSizeText
                            self.appState.downloadSpeedText = lastSpeedText
                            catalog.updateWhisperStatus(modelID, status: .downloading, detail: "\(pct)%")
                        }
                    case .compiling:
                        self.appState.statusMessage = L("pipeline.loading_model")
                        self.appState.downloadSizeText = ""
                        self.appState.downloadSpeedText = ""
                        catalog.updateWhisperStatus(modelID, status: .compiling, detail: L("model.loading"))
                    case .loading:
                        self.appState.statusMessage = L("pipeline.loading_model")
                        self.appState.downloadSizeText = ""
                        self.appState.downloadSpeedText = ""
                        catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                    case .done:
                        break
                    }
                }
            }

            appState.whisperModelReady = true
            appState.downloadSizeText = ""
            appState.downloadSpeedText = ""
            appState.phase = .idle
            appState.statusMessage = L("status.ready")
            catalog.updateWhisperStatus(modelID, status: .ready)
        } catch let error as WhisperError {
            appState.whisperModelReady = false
            appState.downloadSizeText = ""
            appState.downloadSpeedText = ""

            let message: String
            switch error {
            case .downloadFailed:
                message = L("pipeline.download_failed")
            case .compileFailed:
                message = L("pipeline.compile_failed")
            case .loadFailed:
                message = L("pipeline.load_failed")
            default:
                message = error.localizedDescription
            }
            appState.phase = .error(message)
            appState.statusMessage = message
            catalog.updateWhisperStatus(modelID, status: .error(message))
        } catch {
            appState.whisperModelReady = false
            appState.downloadSizeText = ""
            appState.downloadSpeedText = ""
            let message = L("pipeline.model_load_failed_prefix") + error.localizedDescription
            appState.phase = .error(message)
            appState.statusMessage = message
            catalog.updateWhisperStatus(modelID, status: .error(message))
        }
    }
}
