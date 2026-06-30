import Foundation

enum LLMStructuredOutput {
    static func firstJSONObjectData(from text: String) -> Data? {
        guard let range = firstBalancedJSONObjectRange(in: text) else { return nil }
        return String(text[range]).data(using: .utf8)
    }

    static func jsonObjectDataCandidates(from text: String) -> [Data] {
        balancedJSONObjectRanges(in: text).compactMap { range in
            String(text[range]).data(using: .utf8)
        }
    }

    static func firstBalancedJSONObjectRange(in text: String) -> ClosedRange<String.Index>? {
        balancedJSONObjectRanges(in: text).first
    }

    static func balancedJSONObjectRanges(in text: String) -> [ClosedRange<String.Index>] {
        var ranges: [ClosedRange<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "{",
               let end = balancedJSONObjectEnd(startingAt: index, in: text) {
                ranges.append(index...end)
                index = text.index(after: end)
                continue
            }
            index = text.index(after: index)
        }
        return ranges
    }
}

private extension LLMStructuredOutput {
    static func balancedJSONObjectEnd(startingAt start: String.Index, in text: String) -> String.Index? {
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
                if depth < 0 { return nil }
            }

            index = text.index(after: index)
        }
        return nil
    }
}
