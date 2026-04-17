import Foundation

enum VoicePipelinePolicy {
    static func shouldCaptureScreenContext(outputMode: OutputMode, useScreenContext: Bool) -> Bool {
        switch outputMode {
        case .processed:
            return useScreenContext
        case .command:
            return true
        case .direct:
            return false
        }
    }

    @MainActor
    static func memoryContext(
        for outputMode: OutputMode,
        settings: AppSettings,
        recentContextProvider: ((Int) -> String)? = nil
    ) -> String {
        guard settings.enableMemory else { return "" }
        guard outputMode == .command else { return "" }
        let provider = recentContextProvider ?? { MemoryStore.recentContext(windowMinutes: $0) }
        return provider(settings.memoryWindowMinutes)
    }
}
