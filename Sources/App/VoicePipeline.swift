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
    private var volcSpeechEngine: VolcSpeechEngine?
    private var screenOCRTask: Task<String, Never>?
    private var screenOCRStartedAt: CFAbsoluteTime?
    private var processingTask: Task<Void, Never>?
    private var replacementTask: Task<Void, Never>?
    private var hideOverlayTask: Task<Void, Never>?

    private var currentEngine: (any SpeechEngine)? {
        switch appState.settings.speechEngine {
        case .whisper: return whisperEngine
        case .apple: return appleSpeechEngine
        case .volc: return volcSpeechEngine
        }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func warmUp() async {
        await ensureEngineLoaded(requestPermission: false)

        let needsLLM = appState.settings.outputMode == .processed || appState.settings.outputMode == .command
        guard needsLLM, !appState.settings.useRemoteLLM else {
            appState.statusMessage = L("status.ready")
            return
        }

        appState.statusMessage = L("pipeline.loading_llm")
        let model = appState.settings.llmModel

        await textProcessor.warmUpLLM(model: model)
        appState.llmModelReady = await textProcessor.isLLMReady

        if appState.llmModelReady {
            Log.info("[VoicePipeline] LLM model loaded into memory, ready for instant inference")
        } else {
            Log.info("[VoicePipeline] LLM warmup failed, will retry on demand")
        }

        appState.statusMessage = L("status.ready")
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
            await ensureEngineLoaded(requestPermission: true)
        }

        guard currentEngine?.isReady ?? false else {
            appState.phase = .error(L("pipeline.model_not_ready"))
            appState.statusMessage = L("pipeline.model_load_failed")
            return
        }

        processingTask?.cancel()
        processingTask = nil
        replacementTask?.cancel()
        replacementTask = nil
        screenOCRTask?.cancel()
        screenOCRTask = nil
        screenOCRStartedAt = nil
        hideOverlayTask?.cancel()
        hideOverlayTask = nil

        appState.reset()
        appState.phase = .recording
        appState.statusMessage = L("pipeline.recording")

        let needsScreenContext = VoicePipelinePolicy.shouldCaptureScreenContext(
            outputMode: appState.settings.outputMode,
            useScreenContext: appState.settings.useScreenContext
        )
        if needsScreenContext {
            if ScreenOCR.hasScreenCapturePermission {
                screenOCRStartedAt = CFAbsoluteTimeGetCurrent()
                screenOCRTask = Task.detached(priority: .utility) {
                    await ScreenOCR.captureAndRecognize()
                }
            } else {
                Log.info("[VoicePipeline] screen capture permission not granted, skipping OCR")
                screenOCRTask = nil
                screenOCRStartedAt = nil
            }
        } else {
            screenOCRTask = nil
            screenOCRStartedAt = nil
        }

        soundPlayer.playStart()
        overlay.show(appState: appState)

        let micID = appState.settings.microphoneID
        let language = appState.settings.inputLanguage.whisperCode
        let streamingEnabled = appState.settings.enableStreamingRecognitionBeta
        if streamingEnabled {
            currentEngine?.startListening(language: language) { [weak self] partialText in
                Task { @MainActor in
                    guard let self, self.appState.isRecording else { return }
                    self.appState.rawTranscription = partialText
                }
            }
        }

        let micStarted = audioCapture.start(
            deviceID: micID,
            levelUpdate: { [weak self] level in
                Task { @MainActor in
                    self?.appState.audioLevel = level
                }
            },
            bufferUpdate: { [weak self] buffer in
                guard streamingEnabled else { return }
                self?.currentEngine?.appendAudioBuffer(buffer)
            }
        )
        guard micStarted else {
            currentEngine?.cancelListening()
            appState.phase = .error(L("pipeline.mic_failed_permissions"))
            appState.statusMessage = L("pipeline.mic_unavailable")
            overlay.hide()
            return
        }
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
        language: String?,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        defer { audioCapture.cleanupLastRecording() }

        do {
            let asrStarted = CFAbsoluteTimeGetCurrent()
            let raw: String
            if settings.enableStreamingRecognitionBeta {
                raw = try await currentEngine?.finishListening(audioURL: audioURL, language: language) ?? ""
            } else {
                raw = try await currentEngine?.transcribe(audioURL: audioURL, language: language) ?? ""
            }
            let asrElapsed = CFAbsoluteTimeGetCurrent() - asrStarted
            Log.info("[VoicePipeline] ASR stage finished in \(String(format: "%.2f", asrElapsed))s")
            appState.rawTranscription = raw

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

            if raw.isEmpty {
                Log.info("[VoicePipeline] empty transcription, no speech detected")
                appState.phase = .idle
                appState.statusMessage = L("status.no_speech_detected")
                hideOverlayAfterDelay()
                return
            }

            if DeferredReplacementPolicy.shouldUseDeferredReplacement(
                outputMode: settings.outputMode,
                enableInstantInsert: settings.enableInstantInsert
            ) {
                await handleDeferredSmartFormat(raw: raw, settings: settings, targetApp: targetApp)
                return
            }

            let finalText: String
            switch settings.outputMode {
            case .processed:
                appState.phase = .processing
                appState.statusMessage = L("pipeline.formatting")

                let formattingStarted = CFAbsoluteTimeGetCurrent()
                let screenContext = await screenOCRTask?.value ?? ""
                if let screenOCRStartedAt {
                    let ocrElapsed = CFAbsoluteTimeGetCurrent() - screenOCRStartedAt
                    Log.info("[VoicePipeline] OCR stage finished in \(String(format: "%.2f", ocrElapsed))s")
                }
                screenOCRTask = nil
                screenOCRStartedAt = nil

                guard !Task.isCancelled else {
                    resetToIdle()
                    return
                }

                finalText = await textProcessor.process(
                    text: raw,
                    stylePrompt: settings.customStylePrompt,
                    model: settings.llmModel,
                    screenContext: screenContext,
                    memoryContext: ""
                )
                let formattingElapsed = CFAbsoluteTimeGetCurrent() - formattingStarted
                appState.lastFormattingDurationSeconds = formattingElapsed
                Log.info("[VoicePipeline] Smart Format completed in \(String(format: "%.2f", formattingElapsed))s")
            case .command:
                appState.phase = .processing
                appState.statusMessage = L("pipeline.formatting")

                let formattingStarted = CFAbsoluteTimeGetCurrent()
                let screenContext = await screenOCRTask?.value ?? ""
                if let screenOCRStartedAt {
                    let ocrElapsed = CFAbsoluteTimeGetCurrent() - screenOCRStartedAt
                    Log.info("[VoicePipeline] OCR stage finished in \(String(format: "%.2f", ocrElapsed))s")
                }
                screenOCRTask = nil
                screenOCRStartedAt = nil

                guard !Task.isCancelled else {
                    resetToIdle()
                    return
                }

                let memoryContext = VoicePipelinePolicy.memoryContext(for: .command, settings: settings)
                finalText = await textProcessor.processCommand(
                    text: raw,
                    model: settings.llmModel,
                    screenContext: screenContext,
                    memoryContext: memoryContext
                )
                let formattingElapsed = CFAbsoluteTimeGetCurrent() - formattingStarted
                appState.lastFormattingDurationSeconds = formattingElapsed
                Log.info("[VoicePipeline] Voice Command formatting completed in \(String(format: "%.2f", formattingElapsed))s")
            case .direct:
                screenOCRTask?.cancel()
                screenOCRTask = nil
                screenOCRStartedAt = nil
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
            let insertStarted = CFAbsoluteTimeGetCurrent()
            let insertResult = await textInserter.insert(text: finalText, targetApp: targetApp)
            let insertElapsed = CFAbsoluteTimeGetCurrent() - insertStarted
            Log.info("[VoicePipeline] insert stage finished in \(String(format: "%.2f", insertElapsed))s")

            let wasProcessed = settings.outputMode == .processed || settings.outputMode == .command
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
            currentEngine?.cancelListening()
            if Task.isCancelled {
                resetToIdle()
                return
            }
            let message = userFacingErrorMessage(for: error)
            Log.error("[VoicePipeline] error: \(error.localizedDescription)")
            appState.phase = .error(message)
            appState.statusMessage = L("pipeline.error_prefix") + message
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

    func refreshPendingReplacement() {
        guard var replacement = appState.pendingReplacement else { return }
        guard replacement.state == .ready, Date() >= replacement.expiresAt else { return }
        replacement.state = .expired
        replacement.message = L("pipeline.replacement_expired")
        appState.pendingReplacement = replacement
    }

    func applyPendingReplacement() async {
        refreshPendingReplacement()

        guard var replacement = appState.pendingReplacement else { return }
        let decision = DeferredReplacementPolicy.decision(
            for: replacement,
            currentBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )

        switch decision {
        case .replace:
            guard let formattedText = replacement.formattedText else { return }
            guard let targetApp = replacement.targetApplication else {
                TextInserter.copyToClipboard(formattedText)
                replacement.state = .copied
                replacement.message = replacementCopyMessage(for: .missingTarget)
                appState.pendingReplacement = replacement
                return
            }

            appState.phase = .inserting
            appState.statusMessage = L("pipeline.replacing")

            let result = await textInserter.replaceRecentInsertion(
                text: formattedText,
                targetApp: targetApp
            )

            if case .probablyFailed = result {
                TextInserter.copyToClipboard(formattedText)
                replacement.state = .copied
                replacement.message = L("pipeline.replacement_copied_failed")
                appState.pendingReplacement = replacement
                appState.phase = .done
                appState.statusMessage = L("status.done")
                return
            }

            appState.processedText = formattedText
            appState.lastInsertedText = formattedText
            InputHistory.shared.replaceLatestRecord(
                rawText: replacement.rawText,
                processedText: formattedText,
                wasProcessed: true
            )
            appState.clearPendingReplacement()
            appState.phase = .done
            appState.statusMessage = L("status.done")
        case .copy(let reason):
            guard reason != .notReady else {
                replacement.message = L("pipeline.replacement_not_ready")
                appState.pendingReplacement = replacement
                return
            }
            guard let formattedText = replacement.formattedText else { return }
            TextInserter.copyToClipboard(formattedText)
            replacement.state = .copied
            replacement.message = replacementCopyMessage(for: reason)
            appState.pendingReplacement = replacement
        }
    }

    func loadLLM() {
        guard !appState.settings.useRemoteLLM else { return }
        let model = appState.settings.llmModel
        guard !model.isEmpty else { return }
        Task {
            appState.statusMessage = L("pipeline.loading_llm")
            await textProcessor.warmUpLLM(model: model)
            appState.llmModelReady = await textProcessor.isLLMReady
            appState.statusMessage = appState.llmModelReady ? L("status.ready") : L("pipeline.model_load_failed")
        }
    }

    // MARK: - Engine loading

    private func ensureEngineLoaded(requestPermission: Bool = true) async {
        switch appState.settings.speechEngine {
        case .whisper: await ensureWhisperLoaded()
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
            let s = appState.settings
            volcSpeechEngine = VolcSpeechEngine(
                appKey: s.volcAppKey,
                accessKey: s.volcAccessKey,
                resourceId: s.volcResourceId
            )
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

        let alreadyDownloaded = catalog.isWhisperDownloaded(modelID)
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
                        if alreadyDownloaded {
                            self.appState.statusMessage = L("pipeline.loading_model")
                            self.appState.downloadSizeText = ""
                            self.appState.downloadSpeedText = ""
                            catalog.updateWhisperStatus(modelID, status: .loading, detail: L("model.loading"))
                        } else {
                            let pct = Int(min(dp.fraction / 0.6, 1.0) * 100)
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

    private func handleDeferredSmartFormat(
        raw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        let quickText = immediateInsertText(from: raw, settings: settings)
        let ocrTask = screenOCRTask
        let ocrStartedAt = screenOCRStartedAt
        screenOCRTask = nil
        screenOCRStartedAt = nil

        appState.processedText = quickText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.inserting")

        Log.sensitive("[VoicePipeline] instant insert \(quickText.count) chars")
        let insertStarted = CFAbsoluteTimeGetCurrent()
        let insertResult = await textInserter.insert(text: quickText, targetApp: targetApp)
        let insertElapsed = CFAbsoluteTimeGetCurrent() - insertStarted
        Log.info("[VoicePipeline] instant insert stage finished in \(String(format: "%.2f", insertElapsed))s")

        InputHistory.shared.addRecord(rawText: raw, processedText: quickText, wasProcessed: false)
        appState.lastInsertedText = quickText
        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = insertResult {
            Log.info("[VoicePipeline] instant insertion probably failed: \(reason)")
            TextInserter.copyToClipboard(quickText)
            showInsertionFailedAlert(text: quickText, reason: reason)
            return
        }

        let replacement = DeferredReplacement(
            rawText: raw,
            insertedText: quickText,
            targetApp: targetApp,
            message: L("pipeline.background_formatting")
        )
        appState.pendingReplacement = replacement

        replacementTask?.cancel()
        replacementTask = Task { @MainActor [weak self] in
            await self?.finishDeferredSmartFormat(
                replacementID: replacement.id,
                raw: raw,
                settings: settings,
                ocrTask: ocrTask,
                ocrStartedAt: ocrStartedAt
            )
        }
    }

    private func finishDeferredSmartFormat(
        replacementID: UUID,
        raw: String,
        settings: AppSettings,
        ocrTask: Task<String, Never>?,
        ocrStartedAt: CFAbsoluteTime?
    ) async {
        let formattingStarted = CFAbsoluteTimeGetCurrent()
        let screenContext = await ocrTask?.value ?? ""
        if let ocrStartedAt {
            let ocrElapsed = CFAbsoluteTimeGetCurrent() - ocrStartedAt
            Log.info("[VoicePipeline] OCR stage finished in \(String(format: "%.2f", ocrElapsed))s")
        }

        guard !Task.isCancelled else { return }

        let formattedText = await textProcessor.process(
            text: raw,
            stylePrompt: settings.customStylePrompt,
            model: settings.llmModel,
            screenContext: screenContext,
            memoryContext: ""
        )
        let formattingElapsed = CFAbsoluteTimeGetCurrent() - formattingStarted
        appState.lastFormattingDurationSeconds = formattingElapsed
        Log.info("[VoicePipeline] Smart Format completed in \(String(format: "%.2f", formattingElapsed))s")

        guard !Task.isCancelled else { return }
        guard var replacement = appState.pendingReplacement, replacement.id == replacementID else { return }

        replacement.formattedText = formattedText
        replacement.state = .ready
        replacement.message = L("pipeline.formatted_ready")
        appState.pendingReplacement = replacement
    }

    private func immediateInsertText(from raw: String, settings: AppSettings) -> String {
        let cleaned = textProcessor.preCleanForFormatting(text: raw, inputLanguage: settings.inputLanguage)
        let fallback = textProcessor.basicClean(text: raw)
        if !cleaned.isEmpty { return cleaned }
        if !fallback.isEmpty { return fallback }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacementCopyMessage(for reason: DeferredReplacementCopyReason) -> String {
        switch reason {
        case .expired:
            return L("pipeline.replacement_copied_expired")
        case .missingTarget:
            return L("pipeline.replacement_copied_missing_target")
        case .appChanged:
            return L("pipeline.replacement_copied_app_changed")
        case .notReady:
            return L("pipeline.replacement_not_ready")
        }
    }

    private func hideOverlayAfterDelay() {
        hideOverlayTask?.cancel()
        hideOverlayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, !appState.isRecording else { return }
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

    private func userFacingErrorMessage(for error: Error) -> String {
        switch error {
        case let error as VolcASRError:
            return error.localizedDescription
        case let error as WhisperError:
            return error.localizedDescription
        case let error as AppleSpeechError:
            return error.localizedDescription
        case is URLError:
            return L("error.network_request_failed")
        default:
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain || nsError.domain.hasPrefix("Network.") {
                return L("error.network_request_failed")
            }
            return L("error.operation_failed")
        }
    }
}
