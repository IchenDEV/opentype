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
        "text", "transcript", "transcription", "sentence", "prediction",
        "display", "display_text", "displayText",
        "recognized_text", "recognizedText", "recognised_text", "recognisedText",
    ]
    static let nestedKeys = [
        "result", "data", "output", "response",
    ]
    static let arrayKeys = [
        "segments", "chunks", "results", "utterances", "channels",
        "sentences", "transcripts", "predictions",
    ]
    static let alternativeKeys = [
        "alternatives", "hypotheses", "nbest", "n_best",
    ]
    static let confidenceKeys = [
        "confidence", "score", "probability", "certainty",
        "confidence_score", "confidenceScore",
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
                  let text = bestAlternativeText(in: value) else {
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

    static func bestAlternativeText(in value: Any) -> String? {
        if let array = value as? [Any] {
            var firstText: String?
            var bestText: String?
            var bestConfidence = -1.0
            for value in array {
                guard let candidate = alternativeCandidate(in: value) else { continue }
                if firstText == nil {
                    firstText = candidate.text
                }
                guard let confidence = candidate.confidence,
                      confidence > bestConfidence else {
                    continue
                }
                bestText = candidate.text
                bestConfidence = confidence
            }
            return bestText ?? firstText
        }
        return transcriptText(in: value)
    }

    static func alternativeCandidate(in value: Any) -> (text: String, confidence: Double?)? {
        guard let text = transcriptText(in: value) else { return nil }
        let confidence = (value as? [String: Any]).flatMap(confidence(in:))
        return (text, confidence)
    }

    static func confidence(in object: [String: Any]) -> Double? {
        for key in confidenceKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let confidence = confidence(from: value) else {
                continue
            }
            return confidence
        }
        return nil
    }

    static func confidence(from value: Any) -> Double? {
        if value is Bool {
            return nil
        }
        if let number = value as? NSNumber {
            return normalizedConfidence(number.doubleValue)
        }
        if let text = value as? String {
            return confidence(from: text)
        }
        if let object = value as? [String: Any] {
            return confidence(in: object)
        }
        return nil
    }

    static func confidence(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%"),
           let percent = Double(trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)),
           (0...100).contains(percent) {
            return percent / 100
        }
        guard let number = Double(trimmed) else { return nil }
        return normalizedConfidence(number)
    }

    static func normalizedConfidence(_ number: Double) -> Double? {
        if (0...1).contains(number) {
            return number
        }
        if number > 1, number <= 100 {
            return number / 100
        }
        return nil
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
