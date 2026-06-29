import Foundation

enum TranscriptionSanitizer {
    static func prepare(_ text: String, audioActivity: AudioCaptureActivity? = nil) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isNonSpeechArtifact(trimmed) else { return nil }

        let collapsed = collapseRepeatedTranscript(trimmed)
        guard !isNonSpeechArtifact(collapsed) else { return nil }

        return collapsed
    }

    static func previewText(_ text: String, inputLanguage: InputLanguage = .auto) -> String {
        let collapsed = collapseRepeatedTranscript(text)
        guard !isNonSpeechArtifact(collapsed) else { return "" }

        let normalized = FormattingHeuristics.normalizeInput(collapsed)
        return isNonSpeechArtifact(normalized) ? "" : normalized
    }

    static func isNonSpeechArtifact(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let meaningfulScalars = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }
        if meaningfulScalars.isEmpty { return true }

        let cleaned = normalizedPhrase(trimmed)
        return cleaned.isEmpty
    }

    static func collapseRepeatedTranscript(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(normalized)
        guard characters.count >= 12 else { return normalized }

        var bestMatch: String?
        for splitIndex in 1..<characters.count {
            let first = String(characters[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let second = String(characters[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRepeatCandidate(first) else { continue }
            if canonicalText(first) == canonicalText(second) {
                bestMatch = first
            }
        }

        return bestMatch ?? normalized
    }

    private static func isRepeatCandidate(_ text: String) -> Bool {
        let canonical = canonicalText(text)
        guard canonical.count >= 6 else { return false }

        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount >= 2 || containsCJK(text)
    }

    private static func normalizedPhrase(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
        }))
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    }

    private static func canonicalText(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || isCJKScalar(scalar)
        }))
        .lowercased()
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCJKScalar)
    }

    private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
    }
}
