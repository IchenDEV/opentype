import Foundation

@MainActor
extension VoicePipeline {
    func startScreenContextCaptureIfNeeded() {
        let needsScreenContext = VoicePipelinePolicy.shouldCaptureScreenContext(
            outputMode: appState.settings.outputMode,
            useScreenContext: appState.settings.useScreenContext
        )
        guard needsScreenContext else {
            cancelScreenContextCapture()
            return
        }

        guard ScreenOCR.hasScreenCapturePermission else {
            Log.info("[VoicePipeline] screen capture permission not granted, skipping OCR")
            cancelScreenContextCapture()
            return
        }

        screenOCRStartedAt = CFAbsoluteTimeGetCurrent()
        screenOCRTask = Task.detached(priority: .utility) {
            await ScreenOCR.captureAndRecognize()
        }
    }

    func finishScreenContextCapture() async -> String {
        let context = await screenOCRTask?.value ?? ""
        if let screenOCRStartedAt {
            let elapsed = CFAbsoluteTimeGetCurrent() - screenOCRStartedAt
            Log.info("[VoicePipeline] OCR stage finished in \(String(format: "%.2f", elapsed))s")
        }
        screenOCRTask = nil
        screenOCRStartedAt = nil
        return context
    }

    func cancelScreenContextCapture() {
        screenOCRTask?.cancel()
        screenOCRTask = nil
        screenOCRStartedAt = nil
    }
}
