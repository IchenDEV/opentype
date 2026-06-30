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

    static func describe(array: [LLMTextValue]) -> String {
        array
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func describe(object: [String: LLMTextValue]) -> String {
        let lowercasedObject = Dictionary(
            uniqueKeysWithValues: object.map { ($0.key.lowercased(), $0.value) }
        )
        if object.count == 1,
           let key = singleValueObjectKeys.first(where: { lowercasedObject[$0] != nil }),
           let value = lowercasedObject[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        return object.keys.sorted().compactMap { key in
            let value = object[key]?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        .joined(separator: "; ")
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

private extension LLMNumericConfidence {
    static let confidenceKeys = ["value", "score", "confidence", "probability"]

    static func nestedConfidence(in object: [String: LLMNumericConfidence]) -> Double? {
        let lowercasedObject = Dictionary(
            uniqueKeysWithValues: object.map { ($0.key.lowercased(), $0.value) }
        )
        for key in confidenceKeys {
            if let confidence = lowercasedObject[key]?.value {
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
