import Foundation

enum LocalASRTranscriptSignal {
    static func hasDirectSignal(in object: [String: Any]) -> Bool {
        transcriptKeys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
    }
}

private extension LocalASRTranscriptSignal {
    static let transcriptKeys = [
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
        "result", "data", "output", "response", "payload", "body",
        "best", "best_hypothesis", "bestHypothesis",
        "asr_result", "asrResult",
        "transcription_result", "transcriptionResult",
        "recognition_result", "recognitionResult",
        "channel", "events", "messages", "outputs",
        "segments", "chunks", "results", "utterances", "channels",
        "sentences", "transcripts", "predictions",
        "phrases", "recognizedPhrases", "recognized_phrases",
        "combinedRecognizedPhrases", "combined_recognized_phrases",
        "words", "tokens", "items",
        "alternatives", "hypotheses", "nbest", "n_best",
    ]
}

private extension Dictionary where Key == String {
    func value(forCaseInsensitiveKey key: String) -> Value? {
        if let value = self[key] {
            return value
        }
        return first { $0.key.localizedCaseInsensitiveCompare(key) == .orderedSame }?.value
    }
}
