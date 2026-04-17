import Foundation

enum FormattingHeuristics {
    static func preClean(text: String, inputLanguage: InputLanguage) -> String {
        var result = normalizeInput(text)

        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            result = preCleanChinese(result)
        case .english, .japanese, .korean:
            result = preCleanWestern(result)
        }

        result = structureOrdinalLists(in: result, inputLanguage: inputLanguage)
        result = collapseBlankLines(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "[ ]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preCleanChinese(_ text: String) -> String {
        let fillerTokens = ["嗯", "呃", "额", "啊", "那个", "这个", "就是", "然后呢", "你知道吧"]
        let correctionMarkers = ["不对", "不是", "更正一下", "更正", "改口", "改成", "应该是"]

        var result = text
            .replacingOccurrences(of: "，+", with: "，", options: .regularExpression)
            .replacingOccurrences(of: "。+", with: "。", options: .regularExpression)
            .replacingOccurrences(of: "([，。！？；：])\\1+", with: "$1", options: .regularExpression)

        result = stripStandaloneTokens(result, tokens: fillerTokens, punctuationClass: "，。！？；：、,;:!?")
        result = collapseCorrectionClauses(result, markers: correctionMarkers, punctuationBefore: ["，", ",", "；", ";", "：", ":"])
        result = collapseDuplicateWords(result)
        return result
    }

    private static func preCleanWestern(_ text: String) -> String {
        let fillerTokens = ["um", "uh", "er", "ah", "you know", "like"]
        let correctionMarkers = ["sorry", "I mean", "rather", "actually"]

        var result = text
            .replacingOccurrences(of: ",+", with: ",", options: .regularExpression)
            .replacingOccurrences(of: "\\.+", with: ".", options: .regularExpression)
            .replacingOccurrences(of: "([,.;:!?])\\1+", with: "$1", options: .regularExpression)

        result = stripStandaloneTokens(result, tokens: fillerTokens, punctuationClass: ",.;:!?")
        result = collapseCorrectionClauses(result, markers: correctionMarkers, punctuationBefore: [",", ";", ":"])
        result = collapseDuplicateWords(result)
        return result
    }

    private static func stripStandaloneTokens(_ text: String, tokens: [String], punctuationClass: String) -> String {
        var result = text

        for token in tokens {
            let escapedToken = NSRegularExpression.escapedPattern(for: token)
            let leadingPattern = "^(?:\(escapedToken))(?:[\\s\(punctuationClass)]*)"
            let inlinePattern = "([\\s\(punctuationClass)])(?:\(escapedToken))(?=([\\s\(punctuationClass)]|$))"

            result = result.replacingOccurrences(of: leadingPattern, with: "", options: .regularExpression)
            result = result.replacingOccurrences(of: inlinePattern, with: "$1", options: .regularExpression)
        }

        result = result.replacingOccurrences(of: "[ ]{2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "([\(punctuationClass)]) ", with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseCorrectionClauses(_ text: String, markers: [String], punctuationBefore: [Character]) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var candidate = line

            for marker in markers {
                guard let markerRange = candidate.range(of: marker, options: .caseInsensitive) else { continue }

                let prefix = candidate[..<markerRange.lowerBound].trimmingCharacters(in: .whitespaces)
                guard let last = prefix.last, punctuationBefore.contains(last) else { continue }

                let suffix = candidate[markerRange.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ，,；;：:"))
                guard !suffix.isEmpty else { continue }

                candidate = String(suffix)
                break
            }

            return candidate
        }

        return lines.joined(separator: "\n")
    }

    private static func collapseDuplicateWords(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "\\b([A-Za-z]+)(?:\\s+\\1\\b)+",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "([\\p{Han}]{1,4})(?:[，, ]+\\1){1,}",
            with: "$1",
            options: .regularExpression
        )
        return result
    }

    private static func structureOrdinalLists(in text: String, inputLanguage: InputLanguage) -> String {
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return replaceOrdinalMarkers(
                in: text,
                markers: [
                    ("第一", "1."),
                    ("第二", "2."),
                    ("第三", "3."),
                    ("第四", "4."),
                    ("第五", "5.")
                ]
            )
        case .english, .japanese, .korean:
            return replaceOrdinalMarkers(
                in: text,
                markers: [
                    ("First", "1."),
                    ("Second", "2."),
                    ("Third", "3."),
                    ("Fourth", "4."),
                    ("Fifth", "5.")
                ],
                caseInsensitive: true
            )
        }
    }

    private static func replaceOrdinalMarkers(
        in text: String,
        markers: [(String, String)],
        caseInsensitive: Bool = false
    ) -> String {
        let markerCount = markers.reduce(0) { partialResult, pair in
            partialResult + occurrences(of: pair.0, in: text, caseInsensitive: caseInsensitive)
        }
        guard markerCount >= 2 else { return text }

        var result = text

        for (marker, replacement) in markers {
            let escaped = NSRegularExpression.escapedPattern(for: marker)
            let startPattern = "^\\s*\(escaped)[：:、,， ]*"
            let inlinePattern = "(?<!\\n)\\s*\(escaped)[：:、,， ]*"
            let options: NSString.CompareOptions = caseInsensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]

            result = result.replacingOccurrences(of: startPattern, with: "\(replacement) ", options: options)
            result = result.replacingOccurrences(of: inlinePattern, with: "\n\(replacement) ", options: options)
        }

        return result
    }

    private static func occurrences(of needle: String, in haystack: String, caseInsensitive: Bool) -> Int {
        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        var count = 0
        var searchRange: Range<String.Index>? = haystack.startIndex..<haystack.endIndex

        while let range = haystack.range(of: needle, options: options, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<haystack.endIndex
        }

        return count
    }

    private static func collapseBlankLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }
}
