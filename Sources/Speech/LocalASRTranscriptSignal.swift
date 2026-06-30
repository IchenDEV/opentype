import Foundation

enum LocalASRTranscriptSignal {
    static func hasDirectSignal(in object: [String: Any]) -> Bool {
        directTextKeys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
            || arrayKeys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
            || alternativeKeys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
            || nestedKeys.contains {
                guard let value = object.value(forCaseInsensitiveKey: $0) else { return false }
                return nestedValueHasSignal(value)
            }
    }
}

private extension LocalASRTranscriptSignal {
    static let directTextKeys = [
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
    static let alternativeKeys = [
        "alternatives", "hypotheses", "nbest", "n_best",
    ]

    static func nestedValueHasSignal(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            return hasDirectSignal(in: object)
        }
        if let array = value as? [Any] {
            return array.contains(where: nestedValueHasSignal)
        }
        guard let text = value as? String else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return nestedValueHasSignal(value)
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
