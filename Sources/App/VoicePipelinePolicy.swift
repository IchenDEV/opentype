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
        currentContext: InputContext? = nil,
        recentContextProvider: ((Int, InputContext?) -> String)? = nil
    ) -> String {
        guard settings.enableMemory else { return "" }
        guard outputMode != .direct else { return "" }
        let provider = recentContextProvider ?? { MemoryStore.recentContext(windowMinutes: $0, currentContext: $1) }
        return provider(settings.memoryWindowMinutes, currentContext)
    }
}
