import Foundation

struct LLMTextValue: Decodable, Equatable {
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
        } else if let value = try? container.decode([LLMTextValue].self) {
            text = Self.describe(array: value)
        } else if let value = try? container.decode([String: LLMTextValue].self) {
            text = Self.describe(object: value)
        } else {
            text = ""
        }
    }
}

private extension LLMTextValue {
    static let singleValueObjectKeys = [
        "text", "value", "instruction", "intent", "preset", "task", "replacement", "name", "type",
    ]
    static let metadataObjectKeys = [
        "confidence", "score", "probability", "reason", "rationale", "note", "notes", "kind", "type",
    ]

    static func describe(array: [LLMTextValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMTextValue]) -> String {
        if object.count == 1,
           let key = singleValueObjectKeys.first(where: { object.value(forCaseInsensitiveKey: $0) != nil }),
           let value = object.value(forCaseInsensitiveKey: key)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        if let semanticValue = singleSemanticValue(in: object) {
            return semanticValue
        }

        return object.keys.sorted().compactMap { key in
            let value = object[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        .joined(separator: "; ")
    }

    static func singleSemanticValue(in object: [String: LLMTextValue]) -> String? {
        for key in singleValueObjectKeys where key != "type" {
            guard let value = object.value(forCaseInsensitiveKey: key)?.text
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else { continue }

            let hasOnlyMetadataBesidesValue = object.allSatisfy { objectKey, objectValue in
                let candidate = objectValue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return candidate.isEmpty
                    || objectKey.localizedCaseInsensitiveCompare(key) == .orderedSame
                    || metadataObjectKeys.contains { $0.localizedCaseInsensitiveCompare(objectKey) == .orderedSame }
            }
            if hasOnlyMetadataBesidesValue {
                return value
            }
        }
        return nil
    }
}

struct LLMNumericConfidence: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let raw = try? container.decode(String.self) {
            value = Self.number(from: raw)
        } else if let object = try? container.decode([String: LLMNumericConfidence].self),
                  let nested = Self.nestedConfidence(in: object) {
            value = nested
        } else {
            value = -1
        }
    }
}

struct LLMResolutionCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private extension LLMNumericConfidence {
    static let confidenceKeys = ["value", "score", "confidence", "probability"]

    static func nestedConfidence(in object: [String: LLMNumericConfidence]) -> Double? {
        for key in confidenceKeys {
            if let confidence = object.value(forCaseInsensitiveKey: key)?.value {
                return confidence
            }
        }
        return nil
    }

    static func number(from raw: String) -> Double {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("%"),
           let percent = Double(normalized.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)) {
            return percent / 100
        }
        return Double(normalized) ?? -1
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

extension KeyedDecodingContainer where Key == LLMResolutionCodingKey {
    func caseInsensitiveKey(_ name: String) -> Key? {
        allKeys.first { $0.stringValue.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    func decodeIfPresentCaseInsensitive<T: Decodable>(_ type: T.Type, forKey name: String) throws -> T? {
        guard let key = caseInsensitiveKey(name) else { return nil }
        return try decodeIfPresent(type, forKey: key)
    }
}
