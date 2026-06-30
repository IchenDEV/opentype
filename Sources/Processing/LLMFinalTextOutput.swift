import Foundation

enum LLMFinalTextOutput {
    static func text(from rawText: String) -> String? {
        let candidate = stripWrappingCodeFence(from: rawText)
        guard let data = wholeJSONObjectData(from: candidate),
              let object = try? JSONSerialization.jsonObject(with: data),
              let text = finalText(in: object, allowsAmbiguousKeys: false) else {
            return nil
        }
        return text
    }
}

private extension LLMFinalTextOutput {
    static let explicitTextKeys = [
        "final_text", "finalText", "formatted_text", "formattedText",
        "cleaned_text", "cleanedText", "rewritten_text", "rewrittenText",
    ]
    static let ambiguousTextKeys = [
        "text", "output", "result", "content", "body", "message", "response",
    ]
    static let metadataKeys = [
        "explanation", "reason", "rationale", "note", "notes", "confidence",
        "score", "probability", "language", "locale", "type", "kind",
    ]

    static func wholeJSONObjectData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = LLMStructuredOutput.firstBalancedJSONObjectRange(in: trimmed),
              range.lowerBound == trimmed.startIndex,
              range.upperBound == trimmed.index(before: trimmed.endIndex) else {
            return nil
        }
        return String(trimmed[range]).data(using: .utf8)
    }

    static func finalText(in value: Any, allowsAmbiguousKeys: Bool) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        for key in explicitTextKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let text = finalTextValue(from: rawValue, allowsAmbiguousKeys: true) else {
                continue
            }
            return text
        }

        guard allowsAmbiguousKeys || hasMetadata(in: object) else { return nil }
        for key in ambiguousTextKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let text = finalTextValue(from: rawValue, allowsAmbiguousKeys: true) else {
                continue
            }
            return text
        }
        return nil
    }

    static func finalTextValue(from value: Any, allowsAmbiguousKeys: Bool) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let object = value as? [String: Any] {
            return finalText(in: object, allowsAmbiguousKeys: allowsAmbiguousKeys)
        }
        if let array = value as? [Any] {
            let parts = array.compactMap {
                finalTextValue(from: $0, allowsAmbiguousKeys: allowsAmbiguousKeys)
            }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: "\n")
        }
        return nil
    }

    static func hasMetadata(in object: [String: Any]) -> Bool {
        metadataKeys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
    }

    static func stripWrappingCodeFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2,
              isOpeningCodeFence(lines[0]),
              lines[lines.count - 1].trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
            return trimmed
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    static func isOpeningCodeFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "```" || trimmed.range(of: #"^```[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
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
