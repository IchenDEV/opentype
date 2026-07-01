import Foundation

extension LocalASRTranscriptOutput {
    static let typedValueKeys = [
        "value",
    ]
    static let typedValueTranscriptTypes = [
        "text", "punct", "punctuation", "word", "token",
        "pronunciation", "lexical",
    ]

    static func typedValueType(in object: [String: Any]) -> String? {
        for key in ["type", "kind", "element_type", "elementType"] {
            guard let value = object.value(forCaseInsensitiveKey: key) as? String else { continue }
            return normalizedTypedValueType(value)
        }
        return nil
    }

    static func normalizedTypedValueType(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
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
