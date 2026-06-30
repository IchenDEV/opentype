import Foundation

enum LocalASRTranscriptOutput {
    static func text(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var bestText: String?
        var bestPriority = 0
        for data in LLMStructuredOutput.jsonValueDataCandidates(from: trimmed) {
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let candidate = transcriptCandidate(in: object),
                  candidate.priority >= bestPriority else {
                continue
            }
            bestText = candidate.text
            bestPriority = candidate.priority
        }

        return bestText
    }
}

private extension LocalASRTranscriptOutput {
    static let textKeys = [
        "text", "transcript", "transcription",
    ]
    static let nestedKeys = [
        "result", "data", "output", "response",
    ]
    static let arrayKeys = [
        "segments", "chunks", "results", "utterances",
    ]
    static let alternativeKeys = [
        "alternatives", "hypotheses", "nbest", "n_best",
    ]

    static func transcriptCandidate(in value: Any) -> (text: String, priority: Int)? {
        guard let text = transcriptText(in: value) else { return nil }
        guard let object = value as? [String: Any] else { return (text, 1) }
        let priority = (containsAny(arrayKeys, in: object) || containsAny(nestedKeys, in: object)) ? 2 : 1
        return (text, priority)
    }

    static func transcriptText(in value: Any) -> String? {
        if let text = value as? String {
            return nonEmpty(text)
        }
        if let object = value as? [String: Any] {
            return transcriptText(in: object)
        }
        if let array = value as? [Any] {
            return transcriptText(in: array)
        }
        return nil
    }

    static func transcriptText(in object: [String: Any]) -> String? {
        for key in textKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = transcriptText(in: value) else {
                continue
            }
            return text
        }

        for key in nestedKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = transcriptText(in: value) else {
                continue
            }
            return text
        }

        for key in arrayKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = transcriptText(in: value) else {
                continue
            }
            return text
        }

        for key in alternativeKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = firstAlternativeText(in: value) else {
                continue
            }
            return text
        }

        return nil
    }

    static func containsAny(_ keys: [String], in object: [String: Any]) -> Bool {
        keys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
    }

    static func transcriptText(in array: [Any]) -> String? {
        let parts = array.compactMap(transcriptText)
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    static func firstAlternativeText(in value: Any) -> String? {
        if let array = value as? [Any] {
            return array.lazy.compactMap(transcriptText).first
        }
        return transcriptText(in: value)
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
