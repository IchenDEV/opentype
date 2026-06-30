import Foundation

enum LocalASRConfidence {
    static func value(in object: [String: Any]) -> Double? {
        for key in confidenceKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let confidence = parse(rawValue) else {
                continue
            }
            return confidence
        }
        return nil
    }
}

private extension LocalASRConfidence {
    static let confidenceKeys = [
        "confidence", "score", "probability", "certainty",
        "confidence_score", "confidenceScore",
    ]
    static let envelopeValueKeys = [
        "value", "normalized", "normalized_value", "normalizedValue",
    ]

    static func parse(_ value: Any) -> Double? {
        if value is Bool {
            return nil
        }
        if let number = value as? NSNumber {
            return normalized(number.doubleValue)
        }
        if let text = value as? String {
            return parse(text)
        }
        if let object = value as? [String: Any] {
            return self.value(in: object) ?? envelopeValue(in: object)
        }
        return nil
    }

    static func envelopeValue(in object: [String: Any]) -> Double? {
        for key in envelopeValueKeys {
            guard let rawValue = object.value(forCaseInsensitiveKey: key),
                  let confidence = parse(rawValue) else {
                continue
            }
            return confidence
        }
        return nil
    }

    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%"),
           let percent = Double(trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)),
           (0...100).contains(percent) {
            return percent / 100
        }
        guard let number = Double(trimmed) else { return nil }
        return normalized(number)
    }

    static func normalized(_ number: Double) -> Double? {
        if (0...1).contains(number) {
            return number
        }
        if number > 1, number <= 100 {
            return number / 100
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
