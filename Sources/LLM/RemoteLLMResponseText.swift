import Foundation

enum RemoteLLMResponseText {
    static func openAI(from data: Data) throws -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = openAIText(in: json) {
                return text
            }
            throw RemoteLLMError.invalidResponse
        }

        if let text = RemoteLLMEventStreamText.openAI(from: data) {
            return text
        }

        throw RemoteLLMError.invalidResponse
    }

    static func openAIText(in json: [String: Any]) -> String? {
        if let choices = json.value(forCaseInsensitiveKey: "choices") as? [Any] {
            for case let choice as [String: Any] in choices {
                if let text = openAIChoiceText(choice) {
                    return text
                }
            }
        }

        if let text = openAIResponsesText(json) {
            return text
        }

        return nil
    }

    static func anthropic(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json.value(forCaseInsensitiveKey: "content") else {
            throw RemoteLLMError.invalidResponse
        }

        if let text = toolCallText(from: content) {
            return text
        }

        guard let text = contentText(from: content) else { throw RemoteLLMError.invalidResponse }
        return text
    }
}

private extension RemoteLLMResponseText {
    static func openAIChoiceText(_ choice: [String: Any]) -> String? {
        for key in ["message", "delta"] {
            guard let payload = choice.value(forCaseInsensitiveKey: key) as? [String: Any],
                  let text = openAITextPayload(payload) else {
                continue
            }
            return text
        }

        return openAITextPayload(choice)
    }

    static func openAITextPayload(_ payload: [String: Any]) -> String? {
        toolCallText(from: payload.value(forCaseInsensitiveKey: "tool_calls"))
            ?? toolCallText(from: payload.value(forCaseInsensitiveKey: "function_call"))
            ?? structuredPayloadText(from: payload.value(forCaseInsensitiveKey: "parsed"))
            ?? structuredPayloadText(from: payload.value(forCaseInsensitiveKey: "output_parsed"))
            ?? contentText(from: payload.value(forCaseInsensitiveKey: "content"))
            ?? contentText(from: payload.value(forCaseInsensitiveKey: "text"))
    }

    static func openAIResponsesText(_ json: [String: Any]) -> String? {
        if let text = structuredPayloadText(from: json.value(forCaseInsensitiveKey: "output_parsed")) {
            return text
        }
        if let text = structuredPayloadText(from: json.value(forCaseInsensitiveKey: "parsed")) {
            return text
        }
        if let text = toolCallText(from: json.value(forCaseInsensitiveKey: "output")) {
            return text
        }
        if let text = contentText(from: json.value(forCaseInsensitiveKey: "output_text")) {
            return text
        }
        if let text = contentText(from: json.value(forCaseInsensitiveKey: "output")) {
            return text
        }
        if let text = contentText(from: json.value(forCaseInsensitiveKey: "content")) {
            return text
        }
        return nil
    }

    static func contentText(from value: Any?) -> String? {
        if let text = value as? String {
            return nonEmpty(text)
        }
        if let blocks = value as? [Any] {
            let text = blocks
                .compactMap(contentBlockText)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if let object = value as? [String: Any] {
            return contentBlockText(object)
        }
        return nil
    }

    static func contentBlockText(_ value: Any) -> String? {
        guard let object = value as? [String: Any] else {
            return contentText(from: value)
        }

        if let type = object.value(forCaseInsensitiveKey: "type") as? String {
            if matchesBlockType(type, in: textBlockTypes) {
                return contentText(from: object.value(forCaseInsensitiveKey: "text"))
                    ?? contentText(from: object.value(forCaseInsensitiveKey: "content"))
                    ?? contentText(from: object.value(forCaseInsensitiveKey: "value"))
            }
            if matchesBlockType(type, in: wrapperBlockTypes) {
                return toolCallText(from: object.value(forCaseInsensitiveKey: "tool_calls"))
                    ?? toolCallText(from: object.value(forCaseInsensitiveKey: "function_call"))
                    ?? structuredPayloadText(from: object.value(forCaseInsensitiveKey: "parsed"))
                    ?? structuredPayloadText(from: object.value(forCaseInsensitiveKey: "output_parsed"))
                    ?? contentText(from: object.value(forCaseInsensitiveKey: "content"))
                    ?? contentText(from: object.value(forCaseInsensitiveKey: "output"))
                    ?? contentText(from: object.value(forCaseInsensitiveKey: "value"))
            }
            if matchesBlockType(type, in: argumentBlockTypes) {
                return toolCallText(from: object)
            }
            if matchesBlockType(type, in: structuredBlockTypes) {
                return structuredContentBlockText(object)
            }
            return nil
        }

        if let text = contentText(from: object.value(forCaseInsensitiveKey: "text")) {
            return text
        }
        if let text = contentText(from: object.value(forCaseInsensitiveKey: "content")) {
            return text
        }
        if let text = contentText(from: object.value(forCaseInsensitiveKey: "value")) {
            return text
        }
        return actionableJSONText(from: object)
    }

    static func toolCallText(from value: Any?) -> String? {
        if let blocks = value as? [Any] {
            let text = blocks
                .compactMap(toolCallText)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        guard let object = value as? [String: Any] else {
            return contentText(from: value)
        }

        if let text = toolPayloadText(in: object) {
            return text
        }
        if let function = object.value(forCaseInsensitiveKey: "function") as? [String: Any],
           let text = toolPayloadText(in: function) {
            return text
        }
        return nil
    }

    static func toolPayloadText(in object: [String: Any]) -> String? {
        for key in toolPayloadKeys {
            if let text = structuredPayloadText(from: object.value(forCaseInsensitiveKey: key)),
               isActionableOutputPayload(text) {
                return text
            }
        }
        return nil
    }

    static func structuredContentBlockText(_ object: [String: Any]) -> String? {
        for key in structuredBlockPayloadKeys {
            if let text = structuredPayloadText(from: object.value(forCaseInsensitiveKey: key)),
               isActionableOutputPayload(text) {
                return text
            }
        }
        if let text = jsonString(from: object),
           isActionableOutputPayload(text) {
            return text
        }
        return nil
    }

    static func isActionableOutputPayload(_ text: String) -> Bool {
        LLMFinalTextOutput.text(from: text) != nil
            || SpokenEditCommandLLMResolver.command(from: text) != nil
    }

    static func structuredPayloadText(from value: Any?) -> String? {
        if let text = contentText(from: value) {
            return text
        }
        return jsonString(from: value)
    }

    static func actionableJSONText(from value: Any?) -> String? {
        guard let text = jsonString(from: value),
              isActionableOutputPayload(text) else {
            return nil
        }
        return text
    }

    static func jsonString(from value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return nonEmpty(text)
    }

    static let textBlockTypes = [
        "text", "output_text", "final_text", "formatted_text", "cleaned_text",
        "rewritten_text", "result_text",
    ]
    static let wrapperBlockTypes = ["message"]
    static let argumentBlockTypes = ["function", "function_call", "tool_call", "tool_use"]
    static let structuredBlockTypes = ["json", "output_json", "input_json"]
    static let structuredBlockPayloadKeys = [
        "json", "parsed", "output_parsed", "content", "value", "data", "payload",
    ]
    static let toolPayloadKeys = [
        "parsed_arguments", "parsedArguments", "arguments_json", "argumentsJson",
        "input_json", "inputJson", "parameters_json", "parametersJson",
        "arguments", "input", "parameters", "params", "args", "payload", "data",
    ]

    static func matchesBlockType(_ type: String, in candidates: [String]) -> Bool {
        let normalized = normalizedBlockType(type)
        return candidates.contains { normalizedBlockType($0) == normalized }
    }

    static func normalizedBlockType(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Dictionary where Key == String {
    func value(forCaseInsensitiveKey key: String) -> Value? {
        if let value = self[key] {
            return value
        }
        return first { $0.key.localizedCaseInsensitiveCompare(key) == .orderedSame }?.value
    }
}
