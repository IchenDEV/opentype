import Foundation

enum LocalASRTokenControl {
    static func textIfNotControl(_ rawText: String) -> String? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isControlTokenText(text) else { return nil }
        return text
    }

    static func shouldIgnore(_ object: [String: Any]) -> Bool {
        if controlFlag(in: object) == true {
            return true
        }
        if controlType(in: object) == true {
            return true
        }
        return false
    }
}

private extension LocalASRTokenControl {
    static let controlFlagKeys = [
        "special", "is_special", "isSpecial",
        "is_control", "isControl",
    ]
    static let controlTypeKeys = [
        "type", "kind", "token_type", "tokenType",
    ]
    static let controlTypes = [
        "special", "control", "metadata", "timestamp", "timestamp_token",
    ]
    static let bracketedControlTokens = [
        "<s>", "</s>", "<pad>", "<unk>", "<bos>", "<eos>",
        "[cls]", "[sep]", "[pad]", "[unk]", "[bos]", "[eos]",
    ]

    static func controlFlag(in object: [String: Any]) -> Bool? {
        for key in controlFlagKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let flag = boolValue(from: value) else {
                continue
            }
            return flag
        }
        return nil
    }

    static func controlType(in object: [String: Any]) -> Bool? {
        for key in controlTypeKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = textValue(from: value) else {
                continue
            }
            return controlTypes.contains(normalizedType(text))
        }
        return nil
    }

    static func isControlTokenText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("<|"), lowercased.hasSuffix("|>") {
            return true
        }
        return bracketedControlTokens.contains(lowercased)
    }

    static func normalizedType(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    static func boolValue(from value: Any) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        if let text = textValue(from: value) {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    static func textValue(from value: Any) -> String? {
        value as? String
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
