import Foundation

enum RemoteLLMResponseText {
    static func openAI(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = contentText(from: message["content"]) else {
            throw RemoteLLMError.invalidResponse
        }
        return text
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

        if let type = object["type"] as? String,
           !textBlockTypes.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) {
            return nil
        }

        if let text = contentText(from: object["text"]) {
            return text
        }
        if let text = contentText(from: object["content"]) {
            return text
        }
        return contentText(from: object["value"])
    }

    static let textBlockTypes = ["text", "output_text"]

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
