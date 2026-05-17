import AppKit
import Foundation

@MainActor
extension VoicePipeline {
    func processRecording(
        audioURL: URL?,
        audioActivity: AudioCaptureActivity,
        language: String?,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        defer { audioCapture.cleanupLastRecording() }

        do {
            guard audioActivity.hasMeaningfulAudio else {
                showNoSpeechDetected(reason: "recorded audio energy below threshold")
                return
            }

            let preparedRaw = try await transcribePreparedText(
                audioURL: audioURL,
                audioActivity: audioActivity,
                language: language,
                settings: settings
            )

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

            if DeferredReplacementPolicy.shouldUseDeferredReplacement(
                outputMode: settings.outputMode,
                enableInstantInsert: settings.enableInstantInsert
            ) {
                await handleDeferredSmartFormat(raw: preparedRaw, settings: settings, targetApp: targetApp)
                return
            }

            let finalText = await outputText(for: preparedRaw, settings: settings)

            guard !Task.isCancelled else {
                resetToIdle()
                return
            }

            await insertFinalText(finalText, raw: preparedRaw, settings: settings, targetApp: targetApp)
        } catch VoicePipelineStop.noSpeech {
            return
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

    private func transcribePreparedText(
        audioURL: URL?,
        audioActivity: AudioCaptureActivity,
        language: String?,
        settings: AppSettings
    ) async throws -> String {
        let started = CFAbsoluteTimeGetCurrent()
        let raw: String
        if settings.enableStreamingRecognitionBeta {
            raw = try await currentEngine?.finishListening(audioURL: audioURL, language: language) ?? ""
        } else {
            raw = try await currentEngine?.transcribe(audioURL: audioURL, language: language) ?? ""
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[VoicePipeline] ASR stage finished in \(String(format: "%.2f", elapsed))s")

        guard let prepared = TranscriptionSanitizer.prepare(raw, audioActivity: audioActivity) else {
            showNoSpeechDetected(reason: "transcription has no meaningful content: \(raw)")
            throw VoicePipelineStop.noSpeech
        }

        appState.rawTranscription = prepared
        return prepared
    }

    private func outputText(for raw: String, settings: AppSettings) async -> String {
        switch settings.outputMode {
        case .processed:
            return await processSmartFormat(raw, settings: settings)
        case .command:
            return await processCommand(raw, settings: settings)
        case .direct:
            cancelScreenContextCapture()
            return textProcessor.basicClean(text: raw)
        }
    }

    private func processSmartFormat(_ raw: String, settings: AppSettings) async -> String {
        appState.phase = .processing
        appState.statusMessage = L("pipeline.formatting")

        let started = CFAbsoluteTimeGetCurrent()
        let screenContext = await finishScreenContextCapture()
        guard !Task.isCancelled else { return "" }

        let text = await textProcessor.process(
            text: raw,
            stylePrompt: settings.customStylePrompt,
            model: settings.llmModel,
            screenContext: screenContext,
            memoryContext: ""
        )
        recordFormattingDuration(started, label: "Smart Format")
        return text
    }

    private func processCommand(_ raw: String, settings: AppSettings) async -> String {
        appState.phase = .processing
        appState.statusMessage = L("pipeline.formatting")

        let started = CFAbsoluteTimeGetCurrent()
        let screenContext = await finishScreenContextCapture()
        guard !Task.isCancelled else { return "" }

        let memoryContext = VoicePipelinePolicy.memoryContext(for: .command, settings: settings)
        let text = await textProcessor.processCommand(
            text: raw,
            model: settings.llmModel,
            screenContext: screenContext,
            memoryContext: memoryContext
        )
        recordFormattingDuration(started, label: "Voice Command formatting")
        return text
    }

    private func recordFormattingDuration(_ started: CFAbsoluteTime, label: String) {
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        appState.lastFormattingDurationSeconds = elapsed
        Log.info("[VoicePipeline] \(label) completed in \(String(format: "%.2f", elapsed))s")
    }

    private func insertFinalText(
        _ finalText: String,
        raw: String,
        settings: AppSettings,
        targetApp: NSRunningApplication?
    ) async {
        appState.processedText = finalText
        appState.phase = .inserting
        appState.statusMessage = L("pipeline.inserting")

        Log.sensitive("[VoicePipeline] inserting \(finalText.count) chars")
        let started = CFAbsoluteTimeGetCurrent()
        let result = await textInserter.insert(text: finalText, targetApp: targetApp)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[VoicePipeline] insert stage finished in \(String(format: "%.2f", elapsed))s")

        let wasProcessed = settings.outputMode == .processed || settings.outputMode == .command
        InputHistory.shared.addRecord(rawText: raw, processedText: finalText, wasProcessed: wasProcessed)

        appState.lastInsertedText = finalText
        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
            Log.info("[VoicePipeline] insertion probably failed: \(reason)")
            TextInserter.copyToClipboard(finalText)
            showInsertionFailedAlert(text: finalText, reason: reason)
        }
    }
}

private enum VoicePipelineStop: Error {
    case noSpeech
}
