import Foundation

struct LLMActionValue: Decodable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            text = ""
        } else if let value = try? container.decode(String.self) {
            text = value
        } else if let value = try? container.decode(Int.self) {
            text = String(value)
        } else if let value = try? container.decode(Double.self) {
            text = String(value)
        } else if let value = try? container.decode(Bool.self) {
            text = value ? "true" : "false"
        } else if let value = try? container.decode([LLMActionValue].self) {
            text = Self.describe(array: value)
        } else if let value = try? container.decode([String: LLMActionValue].self) {
            text = Self.describe(object: value)
        } else {
            text = ""
        }
    }
}

private extension LLMActionValue {
    static let preferredObjectKeys = [
        "action", "actionType", "action_type",
        "command", "commandType", "command_type",
        "operation", "operationType", "operation_type",
        "value", "name", "type",
    ]
    static let metadataObjectKeys = [
        "confidence", "score", "probability", "reason", "rationale", "description",
        "explanation", "note", "notes", "kind",
        "percent", "percentage", "pct",
        "confidencePercent", "confidence_percent", "confidencePct", "confidence_pct",
        "confidencePercentage", "confidence_percentage",
    ]

    static func describe(array: [LLMActionValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMActionValue]) -> String {
        if let value = semanticActionValue(in: object) {
            return value
        }

        return object.keys.sorted().compactMap { key in
            let value = object[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        .joined(separator: "; ")
    }

    static func semanticActionValue(in object: [String: LLMActionValue]) -> String? {
        for key in preferredObjectKeys {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }

            let hasOnlyActionOrMetadata = object.allSatisfy { objectKey, objectValue in
                let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return candidate.isEmpty
                    || preferredObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
                    || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
            }
            if hasOnlyActionOrMetadata {
                return value
            }
        }
        return nil
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
