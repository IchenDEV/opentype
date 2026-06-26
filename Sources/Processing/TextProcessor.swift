import CoreGraphics
import Foundation

final class TextProcessor {
    let llm = LLMEngine()
    let vlm = VLMEngine()
    let remoteLLMClient = RemoteLLMClient()
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
        await vlm.unload()
    }

    @discardableResult
    func warmUpLLM(
        model: String,
        estimatedDownloadBytes: Int64? = nil,
        progress: (@Sendable (DownloadProgressInfo) -> Void)? = nil
    ) async -> Bool {
        if AppSettings.shared.useRemoteLLM { return true }
        do {
            try await llm.loadModel(
                id: model,
                estimatedDownloadBytes: estimatedDownloadBytes,
                progress: progress
            )
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

    func process(
        text: String,
        stylePrompt: String,
        model: String,
        screenContext: String = "",
        screenImage: CGImage? = nil,
        memoryContext: String = ""
    ) async -> String {
        let settings = AppSettings.shared
        var options = TextProcessingOptions(settings: settings)
        options.customStylePrompt = stylePrompt
        options.llmModel = model
        return await process(
            text: text,
            options: options,
            screenContext: screenContext,
            screenImage: screenImage,
            memoryContext: memoryContext
        )
    }

    func process(
        text: String,
        options: TextProcessingOptions,
        screenContext: String = "",
        screenImage: CGImage? = nil,
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
            screenImageAvailable: shouldUseScreenImage(options: options, image: screenImage),
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
            if let screenImage, shouldUseScreenImage(options: options, image: screenImage) {
                do {
                    result = try await generateWithScreenImage(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
                        model: options.llmModel,
                        image: screenImage,
                        maxTokens: generationOptions.maxTokens,
                        temperature: generationOptions.temperature
                    )
                } catch {
                    Log.error("[TextProcessor] VLM failed, falling back to text LLM: \(error.localizedDescription)")
                    result = try await generateText(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
                        options: options,
                        maxTokens: generationOptions.maxTokens,
                        temperature: generationOptions.temperature
                    )
                }
            } else {
                result = try await generateText(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    options: options,
                    maxTokens: generationOptions.maxTokens,
                    temperature: generationOptions.temperature
                )
            }
            let llmElapsed = CFAbsoluteTimeGetCurrent() - llmStarted
            Log.info("[TextProcessor] formatting LLM completed in \(String(format: "%.2f", llmElapsed))s with budget \(generationOptions.maxTokens) tokens")

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return FormattedOutputCleaner.clean(result)
        } catch {
            Log.error("[TextProcessor] LLM failed, falling back to pre-cleaned text: \(error.localizedDescription)")
            return FormattedOutputCleaner.clean(cleanedText)
        }
    }

    /// Command mode: uses voice command system prompt, higher max tokens.
    func processCommand(
        text: String,
        model: String,
        screenContext: String,
        screenImage: CGImage? = nil,
        memoryContext: String = ""
    ) async -> String {
        let settings = AppSettings.shared
        var options = TextProcessingOptions(settings: settings)
        options.llmModel = model
        return await processCommand(
            text: text,
            options: options,
            screenContext: screenContext,
            screenImage: screenImage,
            memoryContext: memoryContext
        )
    }

    func processCommand(
        text: String,
        options: TextProcessingOptions,
        screenContext: String,
        screenImage: CGImage? = nil,
        memoryContext: String = ""
    ) async -> String {
        let systemPrompt = PromptBuilder.buildCommandSystemPrompt(
            screenContext: screenContext,
            screenImageAvailable: shouldUseScreenImage(options: options, image: screenImage),
            memoryContext: memoryContext,
            inputLanguage: options.inputLanguage
        )
        let userPrompt = text

        do {
            var result: String
            if let screenImage, shouldUseScreenImage(options: options, image: screenImage) {
                do {
                    result = try await generateWithScreenImage(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
                        model: options.llmModel,
                        image: screenImage,
                        maxTokens: 4096,
                        temperature: 0.3
                    )
                } catch {
                    Log.error("[TextProcessor] Command VLM failed, falling back to text LLM: \(error.localizedDescription)")
                    result = try await generateText(
                        prompt: userPrompt,
                        systemPrompt: systemPrompt,
                        options: options,
                        maxTokens: 4096,
                        temperature: 0.3
                    )
                }
            } else {
                result = try await generateText(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    options: options,
                    maxTokens: 4096,
                    temperature: 0.3
                )
            }

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return FormattedOutputCleaner.clean(result)
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
        FormattingHeuristics.normalizeInput(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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

}
