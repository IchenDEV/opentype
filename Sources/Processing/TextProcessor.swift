import Foundation

final class TextProcessor {
    private let llm = LLMEngine()
    private let remoteLLMClient = RemoteLLMClient()
    private let dictionary = PersonalDictionary.shared
    struct GenerationOptions {
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

    @discardableResult
    func warmUpLLM(model: String) async -> Bool {
        if AppSettings.shared.useRemoteLLM { return true }
        do {
            try await llm.loadModel(id: model)
            return true
        } catch {
            Log.error("[TextProcessor] LLM warmup failed: \(error.localizedDescription)")
            return false
        }
    }

    func basicClean(text: String) -> String {
        var result = text
        result = dictionary.applyReplacements(to: result)
        result = normalizeWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func preCleanForFormatting(text: String, inputLanguage: InputLanguage) -> String {
        var result = text
        result = dictionary.applyReplacements(to: result)
        result = FormattingHeuristics.preClean(text: result, inputLanguage: inputLanguage)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func process(text: String, stylePrompt: String, model: String, screenContext: String = "", memoryContext: String = "") async -> String {
        let settings = AppSettings.shared
        var options = TextProcessingOptions(settings: settings)
        options.customStylePrompt = stylePrompt
        options.llmModel = model
        return await process(text: text, options: options, screenContext: screenContext, memoryContext: memoryContext)
    }

    func process(
        text: String,
        options: TextProcessingOptions,
        screenContext: String = "",
        memoryContext: String = ""
    ) async -> String {
        let preCleanStarted = CFAbsoluteTimeGetCurrent()
        let cleanedText = preCleanForFormatting(text: text, inputLanguage: options.inputLanguage)
        let preCleanElapsed = CFAbsoluteTimeGetCurrent() - preCleanStarted
        Log.info("[TextProcessor] pre-cleaned \(text.count) chars to \(cleanedText.count) chars in \(String(format: "%.2f", preCleanElapsed))s")

        var systemPrompt = PromptBuilder.buildSystemPrompt(
            style: options.languageStyle,
            stylePrompt: options.customStylePrompt,
            screenContext: screenContext,
            memoryContext: memoryContext,
            inputLanguage: options.inputLanguage
        )

        let rulesDesc = dictionary.activeRulesDescription()
        if !rulesDesc.isEmpty {
            let rulesPrefix = options.inputLanguage == .english ? "Extra edit rules:" : "额外编辑规则："
            systemPrompt += "\n\n\(rulesPrefix)\n\(rulesDesc)"
        }

        let userPrompt = PromptBuilder.buildUserPrompt(text: cleanedText, inputLanguage: options.inputLanguage)
        let generationOptions = formattingOptions(for: cleanedText, style: options.languageStyle)

        do {
            var result: String
            let llmStarted = CFAbsoluteTimeGetCurrent()
            if options.useRemoteLLM {
                result = try await remoteLLMClient.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    baseURL: options.remoteBaseURL,
                    apiKey: options.remoteAPIKey,
                    model: options.remoteModel,
                    provider: options.remoteProvider,
                    maxTokens: generationOptions.maxTokens,
                    temperature: generationOptions.temperature
                )
            } else {
                await ensureModelLoaded(options.llmModel)
                result = try await llm.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    maxTokens: generationOptions.maxTokens,
                    temperature: generationOptions.temperature
                )
            }
            let llmElapsed = CFAbsoluteTimeGetCurrent() - llmStarted
            Log.info("[TextProcessor] formatting LLM completed in \(String(format: "%.2f", llmElapsed))s with budget \(generationOptions.maxTokens) tokens")

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return normalizeFormattedOutput(result)
        } catch {
            Log.error("[TextProcessor] LLM failed, falling back to pre-cleaned text: \(error.localizedDescription)")
            return normalizeFormattedOutput(cleanedText)
        }
    }

    /// Command mode: uses voice command system prompt, higher max tokens.
    func processCommand(text: String, model: String, screenContext: String, memoryContext: String = "") async -> String {
        let settings = AppSettings.shared
        var options = TextProcessingOptions(settings: settings)
        options.llmModel = model
        return await processCommand(text: text, options: options, screenContext: screenContext, memoryContext: memoryContext)
    }

    func processCommand(
        text: String,
        options: TextProcessingOptions,
        screenContext: String,
        memoryContext: String = ""
    ) async -> String {
        let systemPrompt = PromptBuilder.buildCommandSystemPrompt(
            screenContext: screenContext,
            memoryContext: memoryContext,
            inputLanguage: options.inputLanguage
        )
        let userPrompt = text

        do {
            var result: String
            if options.useRemoteLLM {
                result = try await remoteLLMClient.generate(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    baseURL: options.remoteBaseURL,
                    apiKey: options.remoteAPIKey,
                    model: options.remoteModel,
                    provider: options.remoteProvider,
                    maxTokens: 4096
                )
            } else {
                await ensureModelLoaded(options.llmModel)
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
        FormattingHeuristics.normalizeInput(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizeFormattedOutput(_ text: String) -> String {
        let cleaned = stripOutputScaffolding(from: text)
        let lines = promoteStructuredBreaks(in: cleaned)
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

    func formattingOptions(for text: String, style: LanguageStyle) -> GenerationOptions {
        let characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count

        let maxTokens: Int
        switch (style, characterCount) {
        case (.professional, 0...80), (.custom, 0...80):
            maxTokens = 224
        case (.professional, 81...220), (.custom, 81...220):
            maxTokens = 384
        case (.professional, _), (.custom, _):
            maxTokens = 640
        case (.casual, 0...80):
            maxTokens = 160
        case (.casual, 81...220):
            maxTokens = 256
        case (.casual, _):
            maxTokens = 384
        }

        let temperature: Double
        switch style {
        case .casual:
            temperature = 0.08
        case .professional, .custom:
            temperature = 0.10
        }

        return GenerationOptions(
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    private func stripOutputScaffolding(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scaffoldingPatterns = [
            "^(整理后|最终文本|润色后|输出结果)[：:]\\s*",
            "^(Final text|Rewritten text|Output)[:]\\s*"
        ]

        for pattern in scaffoldingPatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        return result
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
