import Foundation

enum LLMResolutionFieldAlias {
    static let action = [
        "action", "actionType", "action_type",
        "command", "commandType", "command_type",
        "operation", "operationType", "operation_type",
        "type", "name",
    ]
    static let intent = [
        "intent", "instruction", "task", "preset", "style",
        "format", "category", "targetStyle", "target_style",
    ]
    static let replacement = [
        "replacement", "replacementText", "replacement_text", "text", "value", "new", "newText", "new_text", "output",
        "content", "body", "message", "response", "finalText", "final_text",
    ]
    static let confidence = [
        "confidence", "score", "probability", "certainty",
        "confidenceScore", "confidence_score",
        "percent", "percentage", "pct",
        "confidencePercent", "confidence_percent", "confidencePct", "confidence_pct",
        "confidencePercentage", "confidence_percentage",
    ]
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
