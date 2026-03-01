import Foundation

final class TextProcessor {
    private let llm = LLMEngine()
    private let remoteLLMClient = RemoteLLMClient()
    private let dictionary = PersonalDictionary.shared

    var isLLMReady: Bool {
        get async {
            if AppSettings.shared.useRemoteLLM { return true }
            return await llm.isLoaded
        }
    }

    func warmUpLLM(model: String) async {
        if AppSettings.shared.useRemoteLLM { return }
        do {
            try await llm.loadModel(id: model)
        } catch {
            Log.error("[TextProcessor] LLM warmup failed: \(error.localizedDescription)")
        }
    }

    func basicClean(text: String) -> String {
        var result = text
        result = dictionary.applyReplacements(to: result)
        result = normalizeWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func process(text: String, stylePrompt: String, model: String, screenContext: String = "", memoryContext: String = "") async -> String {
        let settings = AppSettings.shared

        var systemPrompt = PromptBuilder.buildSystemPrompt(
            stylePrompt: stylePrompt,
            screenContext: screenContext,
            memoryContext: memoryContext,
            inputLanguage: settings.inputLanguage
        )

        let rulesDesc = dictionary.activeRulesDescription()
        if !rulesDesc.isEmpty {
            systemPrompt += "\n\n额外编辑规则：\n\(rulesDesc)"
        }

        let userPrompt = PromptBuilder.buildUserPrompt(text: text)

        do {
            var result: String
            if settings.useRemoteLLM {
                result = try await remoteLLMClient.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    baseURL: settings.remoteBaseURL,
                    apiKey: settings.remoteAPIKey,
                    model: settings.remoteModel,
                    provider: settings.remoteProvider
                )
            } else {
                try await llm.loadModel(id: model)
                result = try await llm.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt
                )
            }

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Log.error("[TextProcessor] LLM failed, falling back to basicClean: \(error.localizedDescription)")
            return basicClean(text: text)
        }
    }

    /// Command mode: uses voice command system prompt, higher max tokens.
    func processCommand(text: String, model: String, screenContext: String, memoryContext: String = "") async -> String {
        let settings = AppSettings.shared
        let systemPrompt = PromptBuilder.buildCommandSystemPrompt(
            screenContext: screenContext,
            memoryContext: memoryContext,
            inputLanguage: settings.inputLanguage
        )
        let userPrompt = text

        do {
            var result: String
            if settings.useRemoteLLM {
                result = try await remoteLLMClient.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    baseURL: settings.remoteBaseURL,
                    apiKey: settings.remoteAPIKey,
                    model: settings.remoteModel,
                    provider: settings.remoteProvider,
                    maxTokens: 4096
                )
            } else {
                try await llm.loadModel(id: model)
                result = try await llm.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    maxTokens: 4096
                )
            }

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Log.error("[TextProcessor] Command LLM failed, falling back to basicClean: \(error.localizedDescription)")
            return basicClean(text: text)
        }
    }

    private static let thinkTagNames = [
        "think", "thinking", "thought",
        "reason", "reasoning",
        "reflect", "reflection",
        "inner_monologue", "scratchpad",
    ]

    private static let thinkTagPattern: String = {
        let names = thinkTagNames.joined(separator: "|")
        return "<(?:\(names))>"
    }()

    private func stripThinkingTags(_ text: String) -> String {
        var result = text
        for tag in Self.thinkTagNames {
            // Closed pair: <tag>…</tag>
            result = result.replacingOccurrences(
                of: "<\(tag)>[\\s\\S]*?</\(tag)>",
                with: "",
                options: .regularExpression
            )
        }
        // Unclosed opening tag → strip from tag to end
        result = result.replacingOccurrences(
            of: "\(Self.thinkTagPattern)[\\s\\S]*$",
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
