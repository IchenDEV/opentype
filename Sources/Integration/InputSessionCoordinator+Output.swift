import Foundation

@MainActor
extension InputSessionCoordinator {
    func outputText(for raw: String, active: ActiveSession) async -> String {
        let options = TextProcessingOptions(settings: settings, inputLanguage: active.inputLanguage)
        let text: String
        let context: InputContext

        switch active.mode {
        case .direct:
            active.screenContextTask?.cancel()
            context = inputContext(for: active, screenContext: "", mode: .direct)
            text = textProcessor.basicClean(text: raw)
        case .processed:
            let screenContext = await screenContext(from: active)
            context = inputContext(for: active, screenContext: screenContext, mode: .processed)
            let memoryContext = VoicePipelinePolicy.memoryContext(
                for: .processed,
                settings: settings,
                currentContext: context
            )
            text = await textProcessor.process(
                text: raw,
                options: options,
                screenContext: screenContext,
                memoryContext: memoryContext
            )
        case .command:
            let screenContext = await screenContext(from: active)
            context = inputContext(for: active, screenContext: screenContext, mode: .command)
            let memoryContext = VoicePipelinePolicy.memoryContext(
                for: .command,
                settings: settings,
                currentContext: context
            )
            text = await textProcessor.processCommand(
                text: raw,
                options: options,
                screenContext: screenContext,
                memoryContext: memoryContext
            )
        }

        InputHistory.shared.addRecord(
            rawText: raw,
            processedText: text,
            wasProcessed: active.mode != .direct,
            context: context
        )
        return text
    }

    private func inputContext(
        for active: ActiveSession,
        screenContext: String,
        mode: OutputMode
    ) -> InputContext {
        InputContext(
            appName: active.client?.displayName,
            bundleIdentifier: active.client?.bundleIdentifier,
            screenContext: screenContext,
            outputMode: mode,
            inputLanguage: active.inputLanguage,
            source: .integration
        )
    }

    private func screenContext(from active: ActiveSession) async -> String {
        await active.screenContextTask?.value ?? ""
    }
}
