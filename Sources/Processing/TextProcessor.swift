import Foundation

final class TextProcessor {
    private let llm = LLMEngine()
    private let dictionary = PersonalDictionary.shared

    var isLLMReady: Bool {
        get async { await llm.isLoaded }
    }

    /// Pure filler sounds and unambiguous filler phrases — safe to always remove.
    private static let fillerWords: [String] = [
        "嗯嗯", "啊啊", "哦哦", "呃呃",
        "嗯", "啊", "哦", "呃",
        "那个啥", "就是那个", "怎么说呢", "怎么说",
        "你知道吗", "我跟你说", "那什么",
    ]

    /// Words that CAN be filler but also appear in legitimate sentences.
    /// Only removed when they form filler-like patterns (sentence-initial, repeated, etc.)
    private static let ambiguousFillers: [String] = [
        "这个", "那个", "就是", "然后", "的话",
        "呀", "呢", "嘛", "哈",
    ]

    func warmUpLLM(model: String) async {
        do {
            try await llm.loadModel(id: model)
        } catch {
            Log.error("[TextProcessor] LLM warmup failed: \(error.localizedDescription)")
        }
    }

    func basicClean(text: String) -> String {
        var result = text
        result = removeFillerWords(result)
        result = dictionary.applyReplacements(to: result)
        result = normalizeWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func process(text: String, stylePrompt: String, model: String, screenContext: String = "") async -> String {
        do {
            try await llm.loadModel(id: model)

            var systemPrompt = PromptBuilder.buildSystemPrompt(
                stylePrompt: stylePrompt,
                screenContext: screenContext
            )

            let rulesDesc = dictionary.activeRulesDescription()
            if !rulesDesc.isEmpty {
                systemPrompt += "\n\n额外编辑规则：\n\(rulesDesc)"
            }

            let userPrompt = PromptBuilder.buildUserPrompt(text: text)
            var result = try await llm.generate(
                prompt: userPrompt,
                systemPrompt: systemPrompt
            )

            result = stripThinkingTags(result)
            result = dictionary.applyReplacements(to: result)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Log.error("[TextProcessor] LLM failed, falling back to basicClean: \(error.localizedDescription)")
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

    private func removeFillerWords(_ text: String) -> String {
        var result = text
        for word in Self.fillerWords {
            result = result.replacingOccurrences(of: word, with: "")
        }
        result = removeAmbiguousFillers(result)
        return result
    }

    /// Removes ambiguous fillers only at sentence/clause boundaries (start of text,
    /// after punctuation) — not in the middle of meaningful phrases.
    private func removeAmbiguousFillers(_ text: String) -> String {
        var result = text
        for word in Self.ambiguousFillers {
            let startPattern = "^(\(NSRegularExpression.escapedPattern(for: word)))([，,。.！!？?\\s]|$)"
            result = result.replacingOccurrences(of: startPattern, with: "$2", options: .regularExpression)

            let afterPuncPattern = "([，,。.！!？?])(\(NSRegularExpression.escapedPattern(for: word)))([，,。.！!？?\\s]|$)"
            result = result.replacingOccurrences(of: afterPuncPattern, with: "$1$3", options: .regularExpression)
        }
        return result
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
