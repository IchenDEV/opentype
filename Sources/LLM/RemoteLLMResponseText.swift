import Foundation

enum RemoteLLMResponseText {
    static func openAI(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RemoteLLMError.invalidResponse
        }

        if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let text = openAIChoiceText(choice) {
                    return text
                }
            }
        }

        if let text = openAIResponsesText(json) {
            return text
        }

        throw RemoteLLMError.invalidResponse
    }

    static func anthropic(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [Any] else {
            throw RemoteLLMError.invalidResponse
        }

        let text = content
            .compactMap(contentBlockText)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RemoteLLMError.invalidResponse }
        return text
    }
}

private extension RemoteLLMResponseText {
    static func openAIChoiceText(_ choice: [String: Any]) -> String? {
        if let message = choice["message"] as? [String: Any] {
            if let text = contentText(from: message["content"]) {
                return text
            }
            if let text = contentText(from: message["text"]) {
                return text
            }
            if let text = toolCallText(from: message["tool_calls"]) {
                return text
            }
            if let text = toolCallText(from: message["function_call"]) {
                return text
            }
            if let text = structuredPayloadText(from: message["parsed"]) {
                return text
            }
        }

        if let text = contentText(from: choice["content"]) {
            return text
        }
        if let text = contentText(from: choice["text"]) {
            return text
        }
        return structuredPayloadText(from: choice["parsed"])
    }

    static func openAIResponsesText(_ json: [String: Any]) -> String? {
        if let text = contentText(from: json["output_text"]) {
            return text
        }
        if let text = contentText(from: json["output"]) {
            return text
        }
        if let text = contentText(from: json["content"]) {
            return text
        }
        return structuredPayloadText(from: json["output_parsed"])
            ?? structuredPayloadText(from: json["parsed"])
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

        if let type = object["type"] as? String {
            if textBlockTypes.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) {
                return contentText(from: object["text"])
                    ?? contentText(from: object["content"])
                    ?? contentText(from: object["value"])
            }
            if wrapperBlockTypes.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) {
                return contentText(from: object["content"])
                    ?? contentText(from: object["output"])
                    ?? contentText(from: object["value"])
                    ?? structuredPayloadText(from: object["parsed"])
                    ?? structuredPayloadText(from: object["output_parsed"])
            }
            if argumentBlockTypes.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) {
                return toolCallText(from: object)
            }
            return nil
        }

        if let text = contentText(from: object["text"]) {
            return text
        }
        if let text = contentText(from: object["content"]) {
            return text
        }
        if let text = contentText(from: object["value"]) {
            return text
        }
        return jsonString(from: object)
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
        if let function = object["function"] as? [String: Any],
           let text = toolPayloadText(in: function) {
            return text
        }
        return nil
    }

    static func toolPayloadText(in object: [String: Any]) -> String? {
        for key in toolPayloadKeys {
            if let text = structuredPayloadText(from: object[key]) {
                return text
            }
        }
        return nil
    }

    static func structuredPayloadText(from value: Any?) -> String? {
        if let text = contentText(from: value) {
            return text
        }
        return jsonString(from: value)
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

    static let textBlockTypes = ["text", "output_text"]
    static let wrapperBlockTypes = ["message"]
    static let argumentBlockTypes = ["function", "function_call", "tool_call", "tool_use"]
    static let toolPayloadKeys = [
        "parsed_arguments", "parsedArguments", "arguments_json", "argumentsJson",
        "input_json", "inputJson", "parameters_json", "parametersJson",
        "arguments", "input", "parameters", "params", "args", "payload", "data",
    ]

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
