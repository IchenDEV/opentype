import Foundation

enum LLMScaffoldedOutput {
    static func finalText(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let tagged = finalTaggedText(in: trimmed) {
            return tagged
        }
        return finalHeadingText(in: trimmed)
    }
}

private extension LLMScaffoldedOutput {
    static let thinkingMarkers = [
        "analysis", "reasoning", "reason", "thought", "thoughts",
        "thinking", "scratchpad", "inner monologue", "inner_monologue",
    ]
    static let finalMarkers = [
        "final", "final answer", "final output", "answer",
    ]
    static let finalTagPattern = #"<(?:final|final_answer|answer)>([\s\S]*?)</(?:final|final_answer|answer)>"#
    static let thinkingTagPattern = #"<(?:analysis|think|thinking|thought|reason|reasoning|reflect|reflection|inner_monologue|scratchpad)>"#

    static func finalTaggedText(in text: String) -> String? {
        guard hasThinkingTag(text) || isWrappedInFinalTag(text) else { return nil }
        guard let match = text.range(of: finalTagPattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let matched = String(text[match])
        let content = matched.replacingOccurrences(
            of: finalTagPattern,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        return nonEmpty(content)
    }

    static func finalHeadingText(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var sawThinkingScaffold = hasThinkingTag(text)
        var sawContentBeforeScaffold = false

        for (index, line) in lines.enumerated() {
            if isIgnorableLine(line) { continue }

            if !sawThinkingScaffold {
                if isThinkingHeading(line) {
                    sawThinkingScaffold = true
                    continue
                }
                sawContentBeforeScaffold = true
                continue
            }

            guard let remainder = finalHeadingRemainder(in: line),
                  !sawContentBeforeScaffold else {
                continue
            }

            let following = Array(lines.dropFirst(index + 1))
            let section = remainder.isEmpty ? following : [remainder] + following
            return nonEmpty(trimSection(section))
        }

        return nil
    }

    static func isThinkingHeading(_ line: String) -> Bool {
        headingRemainder(in: line, markers: thinkingMarkers) != nil
    }

    static func finalHeadingRemainder(in line: String) -> String? {
        headingRemainder(in: line, markers: finalMarkers)
    }

    static func headingRemainder(in line: String, markers: [String]) -> String? {
        let heading = normalizedHeading(line)
        for marker in markers {
            if heading.localizedCaseInsensitiveCompare(marker) == .orderedSame {
                return ""
            }
            for separator in ["：", ":"] {
                let prefix = marker + separator
                if heading.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil {
                    return String(heading.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    static func normalizedHeading(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = value.first, "#*-_` ".contains(first) {
            value.removeFirst()
        }
        while let last = value.last, "*-_` ".contains(last) {
            value.removeLast()
        }
        return value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func trimSection(_ lines: [String]) -> String {
        var trimmed = lines
        while let first = trimmed.first, isIgnorableLine(first) {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, isIgnorableLine(last) {
            trimmed.removeLast()
        }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isIgnorableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    static func hasThinkingTag(_ text: String) -> Bool {
        text.range(of: thinkingTagPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isWrappedInFinalTag(_ text: String) -> Bool {
        guard let match = text.range(of: finalTagPattern, options: [.regularExpression, .caseInsensitive]) else {
            return false
        }
        return match.lowerBound == text.startIndex && match.upperBound == text.endIndex
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
