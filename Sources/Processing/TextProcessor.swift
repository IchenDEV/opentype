import Foundation

final class TextProcessor {
    private let llm = LLMEngine()
    private let remoteLLMClient = RemoteLLMClient()
    private let dictionary = PersonalDictionary.shared
    private struct GenerationOptions {
        let maxTokens: Int
        let temperature: Double
    }

    var isLLMReady: Bool {
        get async {
            if AppSettings.shared.useRemoteLLM { return true }
            return await llm.isLoaded
        }
    }

    func unloadLLM() async {
        await llm.unload()
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
            style: settings.languageStyle,
            stylePrompt: stylePrompt,
            screenContext: screenContext,
            memoryContext: memoryContext,
            inputLanguage: settings.inputLanguage
        )

        let rulesDesc = dictionary.activeRulesDescription()
        if !rulesDesc.isEmpty {
            systemPrompt += "\n\n额外编辑规则：\n\(rulesDesc)"
        }

        let userPrompt = PromptBuilder.buildUserPrompt(text: text, inputLanguage: settings.inputLanguage)
        let options = formattingOptions(for: text, style: settings.languageStyle)

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
                    maxTokens: options.maxTokens,
                    temperature: options.temperature
                )
            } else {
                await ensureModelLoaded(model)
                result = try await llm.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    maxTokens: options.maxTokens,
                    temperature: options.temperature
                )
            }

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return normalizeFormattedOutput(result)
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
                await ensureModelLoaded(model)
                result = try await llm.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    maxTokens: 4096
                )
            }

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return normalizeFormattedOutput(result)
        } catch {
            Log.error("[TextProcessor] Command LLM failed, falling back to basicClean: \(error.localizedDescription)")
            return basicClean(text: text)
        }
    }

    private func ensureModelLoaded(_ model: String) async {
        guard !(await llm.isLoaded) else { return }
        do {
            try await llm.loadModel(id: model)
        } catch {
            Log.error("[TextProcessor] on-demand model load failed: \(error.localizedDescription)")
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

    private func normalizeFormattedOutput(_ text: String) -> String {
        let lines = promoteStructuredBreaks(in: text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var normalized: [String] = []
        var previousWasBlank = false

        for line in lines {
            let isBlank = line.isEmpty
            if isBlank {
                if previousWasBlank { continue }
                normalized.append("")
            } else {
                normalized.append(line)
            }
            previousWasBlank = isBlank
        }

        return normalized
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formattingOptions(for text: String, style: LanguageStyle) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let baseBudget = min(1024, max(96, characterCount + 64))
        let styleBonus: Int
        switch style {
        case .professional:
            styleBonus = 160
        case .custom:
            styleBonus = 96
        case .casual:
            styleBonus = 0
        }

        return GenerationOptions(
            maxTokens: min(1280, baseBudget + styleBonus),
            temperature: style == .casual ? 0.15 : style == .custom ? 0.12 : 0.1
        )
    }

    private func promoteStructuredBreaks(in text: String) -> String {
        guard !text.contains("\n"), text.count >= 48 else { return text }

        let chineseMarkers = ["首先", "其次", "再次", "然后", "最后", "另外", "还有", "第一", "第二", "第三", "第四", "第五"]
        let englishMarkers = ["First", "Second", "Third", "Fourth", "Finally", "Next"]
        let markerCount = chineseMarkers.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
            + englishMarkers.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }

        guard markerCount >= 2 else { return text }

        var result = text
        let patterns = [
            "(?<!^)(?=(首先|其次|再次|然后|最后|另外|还有|第一|第二|第三|第四|第五))",
            "(?<!^)(?=(First\\b|Second\\b|Third\\b|Fourth\\b|Finally\\b|Next\\b))",
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "\n", options: .regularExpression)
        }

        return result
    }
}
