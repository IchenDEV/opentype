import Foundation

enum FormattedOutputCleaner {
    static func clean(_ text: String) -> String {
        let cleaned = removeScaffolding(from: text)
        let lines = cleaned
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
        if let structuredText = LLMFinalTextOutput.text(from: result) {
            return structuredText
        }

        if let markedSection = finalTextSection(in: result) {
            let section = stripWrappingCodeFence(from: markedSection)
            return LLMFinalTextOutput.text(from: section) ?? section
        }

        let section = removeLeadingLabel(from: explanationStrippedSection(result))
        let unwrapped = stripWrappingCodeFence(from: section)
        return LLMFinalTextOutput.text(from: unwrapped) ?? unwrapped
    }

    static func finalTextSection(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            guard let remainder = finalTextHeadingRemainder(in: line) else { continue }
            guard !hasMeaningfulContent(Array(lines.prefix(index))) else { continue }

            let following = Array(lines.dropFirst(index + 1))
            let section = remainder.isEmpty ? following : [remainder] + following
            guard remainder.isEmpty || hasTrailingExplanationScaffolding(section) else { continue }
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
            if hasMeaningfulContent(result), isExplanationHeading(line) {
                break
            }
            if hasMeaningfulContent(result),
               isRule(line),
               nextMeaningfulLine(after: index, in: lines).map(isExplanationHeading) == true {
                break
            }
            result.append(line)
        }
        return result
    }

    static func hasMeaningfulContent(_ lines: [String]) -> Bool {
        lines.contains { !isRule($0) && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func nextMeaningfulLine(after index: Int, in lines: [String]) -> String? {
        for next in lines.dropFirst(index + 1) {
            if !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return next
            }
        }
        return nil
    }

    static func hasTrailingExplanationScaffolding(_ lines: [String]) -> Bool {
        for (index, line) in lines.enumerated() {
            guard hasMeaningfulContent(Array(lines.prefix(index))) else { continue }
            if isExplanationHeading(line) {
                return true
            }
            if isRule(line),
               nextMeaningfulLine(after: index, in: lines).map(isExplanationHeading) == true {
                return true
            }
        }
        return false
    }

    static func removeLeadingLabel(from text: String) -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = result.components(separatedBy: .newlines)
        guard let firstIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return result
        }
        guard isStandaloneLeadingLabel(lines[firstIndex]) else { return result }
        return trimSection(Array(lines.dropFirst(firstIndex + 1)))
    }

    static func isStandaloneLeadingLabel(_ line: String) -> Bool {
        let heading = normalizedHeading(line)
        if finalTextHeadingRemainder(in: heading) == "" {
            return true
        }

        let scaffoldingPatterns = [
            "^(整理后文本|整理后|最终文本|润色后|输出结果)[：:]$",
            "^(以下是|下面是)(?:整理后|润色后|最终|改写后|处理后)?(?:的)?(?:文本|结果|内容)[：:]$",
            "^(Final text|Rewritten text|Output)[:：]$",
            "^(Here(?: is|'s) (?:the )?(?:final |rewritten |polished |edited )?(?:text|version|output|result))[:：]$",
            "^(以下|こちら)(?:が|は)?(?:整えた|修正した|最終|書き換え後)?(?:テキスト|文章|結果)[：:]$",
            "^(다음은|아래는)\\s*(?:정리된|수정된|최종)?\\s*(?:텍스트|문장|결과|출력)(?:입니다)?[:：]$",
        ]

        return scaffoldingPatterns.contains { pattern in
            heading.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static func finalTextHeadingRemainder(in line: String) -> String? {
        headingRemainder(
            in: line,
            markers: finalTextMarkers
        )
    }

    static func isExplanationHeading(_ line: String) -> Bool {
        headingRemainder(
            in: line,
            markers: explanationMarkers
        ) != nil
    }

    static var finalTextMarkers: [String] {
        [
            "整理后文本", "整理后", "最终文本", "润色后", "输出结果",
            "Final text", "Rewritten text", "Output",
            "最終テキスト", "出力", "書き換え後", "修正後",
            "최종 텍스트", "출력", "수정된 텍스트", "정리된 텍스트",
        ]
    }

    static var explanationMarkers: [String] {
        [
            "说明", "解释", "处理说明", "纠错说明", "纠错与同音词修正",
            "Reasoning", "Explanation", "Notes",
            "説明", "理由", "注釈", "補足", "解説",
            "설명", "이유", "비고", "메모", "처리 설명", "수정 설명",
        ]
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

    static func stripWrappingCodeFence(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2,
              isOpeningCodeFence(lines[0]),
              isClosingCodeFence(lines[lines.count - 1]) else {
            return trimmed
        }

        return trimSection(Array(lines.dropFirst().dropLast()))
    }

    static func isOpeningCodeFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "```" || trimmed.range(of: #"^```[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    static func isClosingCodeFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "```"
    }

    static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }
}
