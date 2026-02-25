import Foundation
import AppKit

@MainActor
final class VoicePipeline {
    private let appState: AppState
    private let soundPlayer = SoundPlayer()
    private let audioCapture = AudioCaptureManager()
    private let textInserter = TextInserter()
    private let textProcessor = TextProcessor()
    private let overlay = OverlayPanel()
    private var whisperEngine: WhisperEngine?
    private var appleSpeechEngine: AppleSpeechEngine?
    private var screenOCRTask: Task<String, Never>?
    private var processingTask: Task<Void, Never>?

    private var currentEngine: (any SpeechEngine)? {
        switch appState.settings.speechEngine {
        case .whisper: return whisperEngine
        case .apple: return appleSpeechEngine
        }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func warmUp() async {
        await ensureEngineLoaded()

        if appState.settings.outputMode == .processed {
            appState.statusMessage = L("pipeline.loading_llm")
            await textProcessor.warmUpLLM(model: appState.settings.llmModel)
            appState.llmModelReady = await textProcessor.isLLMReady
        }

        if currentEngine?.isReady ?? false {
            appState.statusMessage = L("status.ready")
        }
    }

    // MARK: - Recording

    func start() async {
        if appState.isBusy {
            Log.info("[VoicePipeline] start: busy (\(appState.phase)), ignoring")
            showBusyHint()
            return
        }

        if appState.isDownloading { return }

        if !(currentEngine?.isReady ?? false) {
            await ensureEngineLoaded()
        }

        guard currentEngine?.isReady ?? false else {
            appState.phase = .error(L("pipeline.model_not_ready"))
            appState.statusMessage = L("pipeline.model_load_failed")
            return
        }

        processingTask?.cancel()
        processingTask = nil

        appState.reset()
        appState.phase = .recording
        appState.statusMessage = L("pipeline.recording")

        if appState.settings.useScreenContext && appState.settings.outputMode == .processed {
            if ScreenOCR.hasScreenCapturePermission {
                screenOCRTask = Task.detached(priority: .utility) {
                    await ScreenOCR.captureAndRecognize()
                }
            } else {
                Log.info("[VoicePipeline] screen capture permission not granted, skipping OCR")
                screenOCRTask = nil
            }
        } else {
            screenOCRTask = nil
        }

        soundPlayer.playStart()
        overlay.show(appState: appState)

        let micID = appState.settings.microphoneID
        let micStarted = audioCapture.start(deviceID: micID) { [weak self] level in
            Task { @MainActor in
                self?.appState.audioLevel = level
            }
        }
        guard micStarted else {
            appState.phase = .error(L("pipeline.mic_failed_permissions"))
            appState.statusMessage = L("pipeline.mic_unavailable")
            overlay.hide()
            return
        }
        currentEngine?.startListening()
    }

    func stop(targetApp: NSRunningApplication? = nil) async {
        guard appState.isRecording else {
            Log.info("[VoicePipeline] stop: not recording (\(appState.phase)), ignoring")
            return
        }

        soundPlayer.playStop()
        audioCapture.stop()

        appState.phase = .transcribing
        appState.statusMessage = L("pipeline.transcribing")

        let language = appState.settings.inputLanguage.whisperCode
        let audioURL = audioCapture.lastRecordingURL
        let settings = appState.settings

        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processRecording(
                audioURL: audioURL,
                language: language,
                settings: settings,
                targetApp: targetApp
            )
        }
    }

    /// Runs transcription → LLM → text insertion. Separated from stop() so it can be cancelled.
    private func processRecording(
        audioURL: URL?,
        language: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        defer { audioCapture.cleanupLastRecording() }

        do {
            let raw = try await currentEngine?.transcribe(audioURL: audioURL, language: language) ?? ""
            appState.rawTranscription = raw

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

            if raw.isEmpty {
                Log.info("[VoicePipeline] empty transcription, resetting")
                appState.phase = .idle
                appState.statusMessage = L("status.ready")
                overlay.hide()
                return
            }

            let finalText: String
            if settings.outputMode == .processed {
                appState.phase = .processing
                appState.statusMessage = L("pipeline.formatting")

                let screenContext = await screenOCRTask?.value ?? ""
                screenOCRTask = nil

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

                finalText = await textProcessor.process(
                    text: raw,
                    stylePrompt: settings.customStylePrompt,
                    model: settings.llmModel,
                    screenContext: screenContext
                )
            } else {
                screenOCRTask?.cancel()
                screenOCRTask = nil
                finalText = textProcessor.basicClean(text: raw)
            }

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

            appState.processedText = finalText
            appState.phase = .inserting
            appState.statusMessage = L("pipeline.inserting")

            Log.sensitive("[VoicePipeline] inserting \(finalText.count) chars")
            let insertResult = await textInserter.insert(text: finalText, targetApp: targetApp)

            let wasProcessed = settings.outputMode == .processed
            InputHistory.shared.addRecord(rawText: raw, processedText: finalText, wasProcessed: wasProcessed)

            appState.lastInsertedText = finalText
            appState.phase = .done
            appState.statusMessage = L("status.done")
            hideOverlayAfterDelay()

            if case .probablyFailed(let reason) = insertResult {
                Log.info("[VoicePipeline] insertion probably failed: \(reason)")
                TextInserter.copyToClipboard(finalText)
                showInsertionFailedAlert(text: finalText, reason: reason)
            }
        } catch {
            if Task.isCancelled {
                resetToIdle()
                return
            }
            Log.error("[VoicePipeline] error: \(error.localizedDescription)")
            appState.phase = .error(error.localizedDescription)
            appState.statusMessage = L("pipeline.error_prefix") + error.localizedDescription
            hideOverlayAfterDelay()
        }
    }

    // MARK: - Model management

    func unloadWhisper() {
        whisperEngine?.unload()
        whisperEngine = nil
        appState.whisperModelReady = false
        appState.statusMessage = L("pipeline.whisper_unloaded")
    }

    func unloadLLM() {
        appState.llmModelReady = false
        appState.statusMessage = L("pipeline.llm_unloaded")
    }

    // MARK: - Engine loading

    private func ensureEngineLoaded() async {
        switch appState.settings.speechEngine {
        case .whisper: await ensureWhisperLoaded()
        case .apple:
            if appleSpeechEngine == nil { appleSpeechEngine = AppleSpeechEngine() }
        }
    }

    private func ensureWhisperLoaded() async {
        if let engine = whisperEngine {
            if engine.isReady || engine.isLoading { return }
        }

        let modelID = appState.settings.whisperModel
        let engine = WhisperEngine(modelName: modelID)
        whisperEngine = engine
        let catalog = ModelCatalog.shared

        appState.phase = .downloading
        appState.statusMessage = L("pipeline.preparing_model")
        appState.downloadProgress = 0
        catalog.updateWhisperStatus(modelID, status: .downloading)

        var lastSpeedText = ""
        var lastSizeText = ""

        do {
            try await engine.loadModel { [weak self] dp in
                Task { @MainActor in
                    guard let self else { return }
                    self.appState.downloadProgress = dp.fraction

                    if !dp.sizeText.isEmpty { lastSizeText = dp.sizeText }
                    if !dp.speedText.isEmpty { lastSpeedText = dp.speedText }

                    switch dp.stage {
                    case .downloading:
                        let pct = Int(min(dp.fraction / 0.6, 1.0) * 100)
                        let speed = lastSpeedText.isEmpty ? "" : " · \(lastSpeedText)"
                        self.appState.statusMessage = L("pipeline.downloading") + " \(pct)%\(speed)"
                        self.appState.downloadSizeText = lastSizeText
                        self.appState.downloadSpeedText = lastSpeedText
                        catalog.updateWhisperStatus(modelID, status: .downloading, detail: "\(pct)%")
                    case .compiling:
                        self.appState.statusMessage = L("pipeline.compiling")
                        self.appState.downloadSizeText = ""
                        self.appState.downloadSpeedText = ""
                        catalog.updateWhisperStatus(modelID, status: .compiling, detail: L("model.compiling"))
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

            let msg: String
            switch error {
            case .downloadFailed:
                msg = L("pipeline.download_failed")
            case .compileFailed:
                msg = L("pipeline.compile_failed")
            case .loadFailed:
                msg = L("pipeline.load_failed")
            default:
                msg = error.localizedDescription
            }
            appState.phase = .error(msg)
            appState.statusMessage = msg
            catalog.updateWhisperStatus(modelID, status: .error(msg))
        } catch {
            appState.whisperModelReady = false
            appState.downloadSizeText = ""
            appState.downloadSpeedText = ""
            let msg = L("pipeline.model_load_failed_prefix") + error.localizedDescription
            appState.phase = .error(msg)
            appState.statusMessage = msg
            catalog.updateWhisperStatus(modelID, status: .error(msg))
        }
    }

    private func resetToIdle() {
        appState.phase = .idle
        appState.statusMessage = L("status.ready")
        overlay.hide()
    }

    private func hideOverlayAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            overlay.hide()
        }
    }

    private func showBusyHint() {
        let saved = appState.statusMessage
        appState.statusMessage = L("pipeline.busy")
        soundPlayer.playStop()
        overlay.show(appState: appState)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if appState.statusMessage == L("pipeline.busy") {
                appState.statusMessage = saved
            }
        }
    }

    private func showInsertionFailedAlert(text: String, reason: String) {
        let alert = NSAlert()
        alert.messageText = L("pipeline.insert_failed_title")
        alert.informativeText = L("pipeline.insert_failed_body") + reason
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("common.ok"))
        alert.icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        alert.runModal()
    }
}
