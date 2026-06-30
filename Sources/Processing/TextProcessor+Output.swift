import Foundation

extension TextProcessor {
    private static let thinkTagNames = [
        "analysis",
        "think", "thinking", "thought",
        "reason", "reasoning",
        "reflect", "reflection",
        "inner_monologue", "scratchpad",
    ]

    private static let thinkTagPattern: String = {
        let names = thinkTagNames.joined(separator: "|")
        return "<(?:\(names))>"
    }()

    func stripThinkingTags(_ text: String) -> String {
        if let finalText = LLMScaffoldedOutput.finalText(from: text) {
            return finalText
        }

        var result = text
        for tag in Self.thinkTagNames {
            result = result.replacingOccurrences(
                of: "<\(tag)>[\\s\\S]*?</\(tag)>",
                with: "",
                options: .regularExpression
            )
        }
        result = result.replacingOccurrences(
            of: "\(Self.thinkTagPattern)[\\s\\S]*$",
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
