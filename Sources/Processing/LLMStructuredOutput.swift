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
        var starts: [String.Index] = []
        var index = text.startIndex
        var isInsideString = false
        var isEscaped = false

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
                starts.append(index)
            } else if character == "}" {
                guard let start = starts.popLast() else {
                    index = text.index(after: index)
                    continue
                }
                ranges.append(start...index)
            }
            index = text.index(after: index)
        }
        return ranges.sorted { lhs, rhs in
            if lhs.lowerBound == rhs.lowerBound {
                return lhs.upperBound > rhs.upperBound
            }
            return lhs.lowerBound < rhs.lowerBound
        }
    }
}
