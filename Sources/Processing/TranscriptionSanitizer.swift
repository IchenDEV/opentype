import Foundation

enum TranscriptionSanitizer {
    static func prepare(_ text: String, audioActivity: AudioCaptureActivity? = nil) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isNonSpeechArtifact(trimmed) else { return nil }

        let collapsed = collapseRepeatedTranscript(trimmed)
        guard !isNonSpeechArtifact(collapsed) else { return nil }

        if audioActivity?.hasWeakSpeechEvidence == true, isLowContentUtterance(collapsed) {
            return nil
        }

        return collapsed
    }

    static func previewText(_ text: String) -> String {
        let collapsed = collapseRepeatedTranscript(text)
        return isNonSpeechArtifact(collapsed) ? "" : collapsed
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
        return artifactFragments.contains { cleaned.contains($0) }
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

    private static let lowContentTokens: Set<String> = [
        "嗯", "啊", "呃", "额", "哦", "唉", "哈", "哎", "诶",
        "um", "uh", "uhh", "uhm", "hmm", "ah", "eh", "oh", "mm", "mhm",
        "ok", "okay", "yes", "no",
    ]

    private static let artifactFragments: [String] = [
        "字幕志愿者", "字幕由", "字幕组",
        "请不吝点赞", "点赞订阅", "订阅转发", "订阅本频道", "点赞分享",
        "请订阅", "请关注", "请按赞", "敬请订阅", "感谢观看",
        "下集再见", "下期再见", "我们下期再见", "我们下集再见",
        "明镜与点点栏目", "明镜新闻",
        "中文字幕由", "中文字幕志愿者",
        "subscribe to", "thanks for watching", "thank you for watching",
        "please subscribe", "like and subscribe", "see you next",
        "mbc news", "bbc news",
        "as an ai", "i cannot assist", "i cant assist", "i cannot help",
        "i cant help", "i am unable to", "im unable to",
        "抱歉我无法", "抱歉不能", "我无法帮助", "我不能帮助", "无法提供帮助",
    ]

    private static func isLowContentUtterance(_ text: String) -> Bool {
        let normalized = normalizedPhrase(text)
        if lowContentTokens.contains(normalized) { return true }

        let canonical = canonicalText(text)
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        return wordCount <= 1 && canonical.count <= 3
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
