import Foundation

struct LLMTargetValue: Decodable, Equatable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            text = ""
        } else if let value = try? container.decode(String.self) {
            text = value
        } else if let value = try? container.decode([String: LLMTargetValue].self) {
            text = Self.describe(object: value)
        } else if let value = try? container.decode([LLMTargetValue].self) {
            text = Self.describe(array: value)
        } else {
            text = ""
        }
    }
}

private extension LLMTargetValue {
    static let preferredObjectKeys = [
        "target", "scope", "object", "subject", "kind", "type",
        "entity", "name", "value", "text", "selection",
        "targetText", "target_text", "editTarget", "edit_target",
    ]
    static let metadataObjectKeys = [
        "confidence", "score", "probability", "reason", "rationale",
        "description", "explanation", "note", "notes",
    ]

    static func describe(array: [LLMTargetValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMTargetValue]) -> String {
        for key in preferredObjectKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }

            let hasOnlyTargetOrMetadata = object.allSatisfy { objectKey, objectValue in
                let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return candidate.isEmpty
                    || preferredObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                    || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
            }
            if hasOnlyTargetOrMetadata {
                return value
            }
        }
        return ""
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
