import Foundation

enum FormattedOutputCleaner {
    static func clean(_ text: String) -> String {
        let cleaned = removeScaffolding(from: text)
        let lines = promoteStructuredBreaks(in: cleaned)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var normalized: [String] = []
        var previousWasBlank = false

        for line in lines {
            let isBlank = line.isEmpty
            if isBlank {
                if previousWasBlank { continue }
                normalized.append("")
            } else {
                normalized.append(line)
            }
            previousWasBlank = isBlank
        }

        return normalized
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension FormattedOutputCleaner {
    static func removeScaffolding(from text: String) -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let markedSection = finalTextSection(in: result) {
            return markedSection
        }

        return removeLeadingLabel(from: explanationStrippedSection(result))
    }

    static func finalTextSection(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            guard let remainder = finalTextHeadingRemainder(in: line) else { continue }

            var section: [String] = []
            if !remainder.isEmpty {
                section.append(remainder)
            }
            section.append(contentsOf: lines.dropFirst(index + 1))
            return trimSection(explanationStrippedLines(section))
        }
        return nil
    }

    static func explanationStrippedSection(_ text: String) -> String {
        trimSection(explanationStrippedLines(text.components(separatedBy: .newlines)))
    }

    static func explanationStrippedLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        for (index, line) in lines.enumerated() {
            if isExplanationHeading(line) {
                break
            }
            if isRule(line), nextMeaningfulLine(after: index, in: lines).map(isExplanationHeading) == true {
                break
            }
            result.append(line)
        }
        return result
    }

    static func nextMeaningfulLine(after index: Int, in lines: [String]) -> String? {
        for next in lines.dropFirst(index + 1) {
            if !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return next
            }
        }
        return nil
    }

    static func removeLeadingLabel(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scaffoldingPatterns = [
            "^(整理后文本|整理后|最终文本|润色后|输出结果)[：:]\\s*",
            "^(Final text|Rewritten text|Output)[:：]\\s*",
        ]

        for pattern in scaffoldingPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    static func finalTextHeadingRemainder(in line: String) -> String? {
        headingRemainder(
            in: line,
            markers: ["整理后文本", "整理后", "最终文本", "润色后", "输出结果", "Final text", "Rewritten text", "Output"]
        )
    }

    static func isExplanationHeading(_ line: String) -> Bool {
        headingRemainder(
            in: line,
            markers: ["说明", "解释", "处理说明", "纠错说明", "纠错与同音词修正", "Reasoning", "Explanation", "Notes"]
        ) != nil
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
        value = value.replacingOccurrences(
            of: #"^\d+[.)]\s+"#,
            with: "",
            options: .regularExpression
        )

        while let first = value.first, "#*-_` ".contains(first) {
            value.removeFirst()
        }
        while let last = value.last, "*-_` ".contains(last) {
            value.removeLast()
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimSection(_ lines: [String]) -> String {
        var trimmed = lines
        while let first = trimmed.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRule(first) {
            trimmed.removeFirst()
        }
        while let last = trimmed.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRule(last) {
            trimmed.removeLast()
        }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    static func promoteStructuredBreaks(in text: String) -> String {
        guard !text.contains("\n"), text.count >= 48 else { return text }

        let chineseMarkers = ["首先", "其次", "再次", "然后", "最后", "另外", "还有", "第一", "第二", "第三", "第四", "第五"]
        let englishMarkers = ["First", "Second", "Third", "Fourth", "Finally", "Next"]
        let markerCount = chineseMarkers.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
            + englishMarkers.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }

        guard markerCount >= 2 else { return text }

        var result = text
        let patterns = [
            "(?<!^)(?=(首先|其次|再次|然后|最后|另外|还有|第一|第二|第三|第四|第五))",
            "(?<!^)(?=(First\\b|Second\\b|Third\\b|Fourth\\b|Finally\\b|Next\\b))",
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "\n", options: .regularExpression)
        }

        return result
    }
}
