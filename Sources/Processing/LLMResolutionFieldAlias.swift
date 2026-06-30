import Foundation

enum LLMResolutionFieldAlias {
    static let action = ["action", "command", "operation"]
    static let intent = ["intent", "instruction", "task", "preset", "style"]
    static let replacement = [
        "replacement", "replacementText", "replacement_text", "text", "value", "new", "newText", "new_text", "output",
    ]
    static let confidence = ["confidence", "score", "probability"]
}

extension KeyedDecodingContainer where Key == LLMResolutionCodingKey {
    func hasCaseInsensitiveKey(anyOf names: [String]) -> Bool {
        names.contains { caseInsensitiveKey($0) != nil }
    }

    func decodeIfPresentCaseInsensitive<T: Decodable>(_ type: T.Type, forAnyKey names: [String]) throws -> T? {
        guard let name = names.first(where: { caseInsensitiveKey($0) != nil }) else { return nil }
        return try decodeIfPresentCaseInsensitive(type, forKey: name)
    }
}
