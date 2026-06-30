import Foundation

enum LocalASRJSONLinesOutput {
    static func text(from output: String) -> String? {
        let events = jsonLineEvents(in: output)
        guard events.count > 1,
              events.contains(where: \.hasFinalityMetadata) == false else {
            return nil
        }

        let parts = events.compactMap(\.text)
        guard parts.count > 1 else { return nil }
        return LocalASRTranscriptJoiner.join(parts)
    }
}

private struct LocalASRJSONLineEvent {
    let text: String?
    let hasFinalityMetadata: Bool
}

private extension LocalASRJSONLinesOutput {
    static func jsonLineEvents(in output: String) -> [LocalASRJSONLineEvent] {
        output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { jsonLineEvent(from: String($0)) }
    }

    static func jsonLineEvent(from line: String) -> LocalASRJSONLineEvent? {
        let payload = jsonPayload(in: line)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              isLikelyRunnerLog(value) == false else {
            return nil
        }

        return LocalASRJSONLineEvent(
            text: LocalASRTranscriptOutput.structuredText(from: payload),
            hasFinalityMetadata: hasFinalityMetadata(in: value)
        )
    }

    static func jsonPayload(in line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if trimmed.localizedCaseInsensitiveComparePrefix("data:") {
            payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            payload = trimmed
        }
        guard payload.hasPrefix("{") || payload.hasPrefix("[") else { return "" }
        return payload
    }

    static func isLikelyRunnerLog(_ value: Any) -> Bool {
        guard let object = value as? [String: Any],
              ["level", "logger", "severity"].contains(where: { object.value(forCaseInsensitiveKey: $0) != nil }) else {
            return false
        }
        return hasDirectTranscriptSignal(in: object) == false
    }

    static func hasDirectTranscriptSignal(in object: [String: Any]) -> Bool {
        let transcriptKeys = [
            "text", "transcript", "transcription", "sentence", "prediction",
            "display", "display_text", "displayText", "word", "content",
            "token", "token_str", "tokenStr", "piece", "surface",
            "segments", "chunks", "results", "utterances", "sentences",
            "transcripts", "words", "tokens", "alternatives", "hypotheses",
        ]
        return transcriptKeys.contains { object.value(forCaseInsensitiveKey: $0) != nil }
    }

    static func hasFinalityMetadata(in value: Any) -> Bool {
        if let object = value as? [String: Any] {
            if LocalASRTranscriptFinality.hasMetadata(in: object) {
                return true
            }
            return object.values.contains(where: hasFinalityMetadata)
        }
        if let array = value as? [Any] {
            return array.contains(where: hasFinalityMetadata)
        }
        return false
    }
}

private extension String {
    func localizedCaseInsensitiveComparePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
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
