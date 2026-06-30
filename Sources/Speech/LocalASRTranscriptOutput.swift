import Foundation

enum LocalASRTranscriptOutput {
    static func text(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let jsonLinesText = LocalASRJSONLinesOutput.text(from: trimmed) {
            return jsonLinesText
        }

        return structuredText(from: trimmed)
    }

    static func structuredText(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var bestText: String?
        var bestPriority = 0
        for data in LLMStructuredOutput.jsonValueDataCandidates(from: trimmed) {
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  isLikelyRunnerLog(object) == false,
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
        "word", "punctuated_word", "punctuatedWord", "content",
        "token", "display_token", "displayToken",
        "punctuated_token", "punctuatedToken",
        "token_str", "tokenStr", "piece", "surface",
        "lexical", "utterance", "hypothesis",
        "normalized", "normalized_text", "normalizedText",
        "generated_text", "generatedText",
        "best_text", "bestText",
        "recognized_text", "recognizedText", "recognised_text", "recognisedText",
    ]
    static let nestedKeys = [
        "result", "data", "output", "response", "payload", "message", "body",
        "best", "best_hypothesis", "bestHypothesis",
        "asr_result", "asrResult",
        "transcription_result", "transcriptionResult",
        "recognition_result", "recognitionResult",
        "channel",
    ]
    static let arrayKeys = [
        "events", "messages", "outputs",
        "segments", "chunks", "results", "utterances", "channels",
        "sentences", "transcripts", "predictions",
        "phrases", "recognizedPhrases", "recognized_phrases",
        "combinedRecognizedPhrases", "combined_recognized_phrases",
        "words", "tokens", "items",
    ]
    static let finalSegmentArrayKeys = [
        "segments", "chunks", "results", "utterances", "sentences",
        "transcripts", "predictions", "phrases",
        "words", "tokens", "items",
    ]
    static let alternativeKeys = [
        "alternatives", "hypotheses", "nbest", "n_best",
        "candidates", "candidate", "beams", "beam",
        "best_candidates", "bestCandidates",
        "recognition_candidates", "recognitionCandidates",
    ]
    static func transcriptCandidate(in value: Any) -> (text: String, priority: Int)? {
        guard let text = transcriptText(in: value) else { return nil }
        guard let object = value as? [String: Any] else {
            return (text, LocalASRTranscriptFinality.priority(structuralPriority: 1))
        }
        let structuralPriority = (containsAny(arrayKeys, in: object) || containsAny(nestedKeys, in: object)) ? 2 : 1
        return (text, LocalASRTranscriptFinality.priority(in: object, structuralPriority: structuralPriority))
    }

    static func transcriptText(in value: Any) -> String? {
        if let text = value as? String {
            return LocalASRTokenControl.textIfNotControl(text)
        }
        if let object = value as? [String: Any] {
            guard !LocalASRTokenControl.shouldIgnore(object) else { return nil }
            return transcriptText(in: object)
        }
        if let array = value as? [Any] {
            return transcriptText(in: array)
        }
        return nil
    }

    static func transcriptText(in object: [String: Any]) -> String? {
        structuredTranscriptText(in: object) ?? directTranscriptText(in: object)
    }

    static func directTranscriptText(in object: [String: Any]) -> String? {
        for key in textKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = transcriptText(in: value) else {
                continue
            }
            return text
        }
        return nil
    }

    static func structuredTranscriptText(in object: [String: Any]) -> String? {
        for key in nestedKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = nestedTranscriptText(in: value) else {
                continue
            }
            return text
        }

        for key in arrayKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let text = transcriptText(
                    in: value,
                    joinsFinalSegments: finalSegmentArrayKeys.contains(where: { matchesKey(key, $0) })
                  ) else {
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

    static func nestedTranscriptText(in value: Any) -> String? {
        guard let text = value as? String else {
            return transcriptText(in: value)
        }
        return serializedPayloadTranscriptText(in: text)
            ?? LocalASRTokenControl.textIfNotControl(text)
    }

    static func serializedPayloadTranscriptText(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return transcriptText(in: value)
    }

    static func containsAny(_ keys: [String], in object: [String: Any]) -> Bool {
        keys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
    }

    static func isLikelyRunnerLog(_ value: Any) -> Bool {
        guard let object = value as? [String: Any],
              ["level", "logger", "severity"].contains(where: { object.value(forCaseInsensitiveKey: $0) != nil }) else {
            return false
        }
        return LocalASRTranscriptSignal.hasDirectSignal(in: object) == false
    }

    static func transcriptText(in value: Any, joinsFinalSegments: Bool) -> String? {
        if let array = value as? [Any] {
            return transcriptText(in: array, joinsFinalSegments: joinsFinalSegments)
        }
        return transcriptText(in: value)
    }

    static func transcriptText(in array: [Any], joinsFinalSegments: Bool = false) -> String? {
        if joinsFinalSegments,
           let text = joinedFinalSegmentsText(in: array) {
            return text
        }
        if let text = finalityPreferredText(in: array) {
            return text
        }
        let parts = array.compactMap(transcriptText)
        guard !parts.isEmpty else { return nil }
        return LocalASRTranscriptJoiner.join(parts)
    }

    static func joinedFinalSegmentsText(in array: [Any]) -> String? {
        let finalTexts = array.compactMap { value -> String? in
            guard let object = value as? [String: Any],
                  LocalASRTranscriptFinality.isFinal(in: object),
                  let candidate = transcriptCandidate(in: object) else {
                return nil
            }
            return candidate.text
        }
        guard finalTexts.count > 1 else { return nil }
        return LocalASRFinalSegmentJoiner.join(finalTexts)
    }

    static func finalityPreferredText(in array: [Any]) -> String? {
        var hasFinalityMetadata = false
        var bestText: String?
        var bestPriority = 0

        for case let object as [String: Any] in array {
            guard LocalASRTranscriptFinality.hasMetadata(in: object) else { continue }
            hasFinalityMetadata = true
            guard let candidate = transcriptCandidate(in: object),
                  candidate.priority >= bestPriority else {
                continue
            }
            bestText = candidate.text
            bestPriority = candidate.priority
        }

        return hasFinalityMetadata ? bestText : nil
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
        let confidence = (value as? [String: Any]).flatMap(LocalASRConfidence.value(in:))
        return (text, confidence)
    }

    static func matchesKey(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame
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
