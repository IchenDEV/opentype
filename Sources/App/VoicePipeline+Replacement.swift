import AppKit
import Foundation

@MainActor
extension VoicePipeline {
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
            await replacePendingText(replacement)
        case .copy(let reason):
            guard reason != .notReady else {
                replacement.message = L("pipeline.replacement_not_ready")
                appState.pendingReplacement = replacement
                return
            }
            copyPendingReplacement(&replacement, reason: reason)
        }
    }

    func handleDeferredSmartFormat(
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
        let started = CFAbsoluteTimeGetCurrent()
        let result = await textInserter.insert(text: quickText, targetApp: targetApp)
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        Log.info("[VoicePipeline] instant insert stage finished in \(String(format: "%.2f", elapsed))s")

        InputHistory.shared.addRecord(rawText: raw, processedText: quickText, wasProcessed: false)
        appState.lastInsertedText = quickText
        appState.phase = .done
        appState.statusMessage = L("status.done")
        hideOverlayAfterDelay()

        if case .probablyFailed(let reason) = result {
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

    private func replacePendingText(_ replacement: DeferredReplacement) async {
        guard let formattedText = replacement.formattedText else { return }
        guard let targetApp = replacement.targetApplication else {
            var copied = replacement
            copyPendingReplacement(&copied, reason: .missingTarget)
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
            var copied = replacement
            copied.state = .copied
            copied.message = L("pipeline.replacement_copied_failed")
            appState.pendingReplacement = copied
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
    }

    private func copyPendingReplacement(_ replacement: inout DeferredReplacement, reason: DeferredReplacementCopyReason) {
        guard let formattedText = replacement.formattedText else { return }
        TextInserter.copyToClipboard(formattedText)
        replacement.state = .copied
        replacement.message = replacementCopyMessage(for: reason)
        appState.pendingReplacement = replacement
    }

    private func finishDeferredSmartFormat(
        replacementID: UUID,
        raw: String,
        settings: AppSettings,
        ocrTask: Task<String, Never>?,
        ocrStartedAt: CFAbsoluteTime?
    ) async {
        let started = CFAbsoluteTimeGetCurrent()
        let screenContext = await ocrTask?.value ?? ""
        if let ocrStartedAt {
            let elapsed = CFAbsoluteTimeGetCurrent() - ocrStartedAt
            Log.info("[VoicePipeline] OCR stage finished in \(String(format: "%.2f", elapsed))s")
        }

        guard !Task.isCancelled else { return }

        let formattedText = await textProcessor.process(
            text: raw,
            stylePrompt: settings.customStylePrompt,
            model: settings.llmModel,
            screenContext: screenContext,
            memoryContext: ""
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        appState.lastFormattingDurationSeconds = elapsed
        Log.info("[VoicePipeline] Smart Format completed in \(String(format: "%.2f", elapsed))s")

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
}
