import Foundation

enum LocalASRTranscriptJoiner {
    static func join(_ parts: [String]) -> String {
        let usesExplicitSpaceMarkers = parts.contains(where: hasExplicitSpaceMarker)
        return parts.reduce(into: "") { result, part in
            let piece = normalizedPiece(part, usesExplicitSpaceMarkers: usesExplicitSpaceMarkers)
            guard !piece.text.isEmpty else { return }
            if result.isEmpty || piece.attachesToPrevious || shouldAttachWithoutSpace(previous: result, next: piece.text) {
                result += piece.text
            } else {
                result += " \(piece.text)"
            }
        }
    }
}

private struct LocalASRTranscriptPiece {
    let text: String
    let attachesToPrevious: Bool
}

private extension LocalASRTranscriptJoiner {
    static func normalizedPiece(_ rawPart: String, usesExplicitSpaceMarkers: Bool) -> LocalASRTranscriptPiece {
        var text = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
        let startsWithSpaceMarker = hasExplicitSpaceMarker(text)
        var attachesToPrevious = usesExplicitSpaceMarkers && !startsWithSpaceMarker

        if text.hasPrefix("##") {
            attachesToPrevious = true
            repeat {
                text.removeFirst(2)
            } while text.hasPrefix("##")
        }

        text = text
            .replacingOccurrences(of: "▁", with: " ")
            .replacingOccurrences(of: "Ġ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return LocalASRTranscriptPiece(text: text, attachesToPrevious: attachesToPrevious)
    }

    static func hasExplicitSpaceMarker(_ rawPart: String) -> Bool {
        let text = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("▁") || text.hasPrefix("Ġ")
    }
}

private extension LocalASRTranscriptJoiner {
    static func shouldAttachWithoutSpace(previous: String, next: String) -> Bool {
        guard let last = previous.unicodeScalars.last,
              let first = next.unicodeScalars.first else {
            return false
        }
        if isApostropheJoin(previous: previous, next: next) {
            return true
        }
        if isNumericJoin(previous: previous, next: next) {
            return true
        }
        if isConnectorJoin(previous: previous, next: next) {
            return true
        }
        if isClosingPunctuation(first, after: previous) || isOpeningPunctuation(last, in: previous) {
            return true
        }
        if isCurrencySymbol(last), CharacterSet.decimalDigits.contains(first) {
            return true
        }
        if isCJK(last), isOpeningPunctuation(first, in: previous) {
            return true
        }
        return isCJK(last) && isCJK(first)
    }

    static func isApostropheJoin(previous: String, next: String) -> Bool {
        guard let last = previous.unicodeScalars.last,
              let first = next.unicodeScalars.first else {
            return false
        }
        return (isApostrophe(first) && CharacterSet.alphanumerics.contains(last))
            || (isApostrophe(last) && CharacterSet.alphanumerics.contains(first))
    }

    static func isNumericJoin(previous: String, next: String) -> Bool {
        guard let last = previous.unicodeScalars.last,
              let first = next.unicodeScalars.first else {
            return false
        }
        if isNumericSuffix(first), CharacterSet.decimalDigits.contains(last) {
            return true
        }
        if isNumericSeparator(first), CharacterSet.decimalDigits.contains(last) {
            return true
        }
        if isNumericSeparator(last),
           CharacterSet.decimalDigits.contains(first),
           previous.dropLast().unicodeScalars.last.map(CharacterSet.decimalDigits.contains) == true {
            return true
        }
        if isDegreeSymbol(last), CharacterSet.letters.contains(first) {
            return true
        }
        return false
    }

    static func isConnectorJoin(previous: String, next: String) -> Bool {
        guard let last = previous.unicodeScalars.last,
              let first = next.unicodeScalars.first else {
            return false
        }
        if isConnectorSymbol(first), canAttachConnector(first, after: last, previous: previous) {
            return true
        }
        if isConnectorSymbol(last), canAttachAfterConnector(first) {
            return true
        }
        if isDomainSeparator(first),
           CharacterSet.alphanumerics.contains(last),
           hasConnectorContext(previous) {
            return true
        }
        if isDomainSeparator(last),
           CharacterSet.alphanumerics.contains(first),
           hasConnectorContext(String(previous.dropLast())) {
            return true
        }
        return false
    }

    static func isClosingPunctuation(_ scalar: Unicode.Scalar, after previous: String) -> Bool {
        if isConnectorSymbol(scalar) {
            return false
        }
        if isQuote(scalar) {
            return hasUnclosedQuote(scalar, in: previous)
        }
        return CharacterSet.punctuationCharacters.contains(scalar) && !isOpeningPunctuation(scalar, in: previous)
    }

    static func isOpeningPunctuation(_ scalar: Unicode.Scalar, in previous: String) -> Bool {
        if isQuote(scalar) {
            return !hasUnclosedQuote(scalar, in: String(previous.dropLast()))
        }
        let opening = CharacterSet(charactersIn: "([{（［｛【《〈〔〖〘〚「『«‹“‘")
        return opening.contains(scalar)
    }

    static func isApostrophe(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet(charactersIn: "'’").contains(scalar)
    }

    static func isQuote(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet(charactersIn: "\"“”‘「」『』«»‹›").contains(scalar)
    }

    static func hasUnclosedQuote(_ scalar: Unicode.Scalar, in text: String) -> Bool {
        let quotedScalars = text.unicodeScalars.filter { matchingQuoteFamily($0) == matchingQuoteFamily(scalar) }
        return !quotedScalars.isEmpty && quotedScalars.count.isMultiple(of: 2) == false
    }

    static func matchingQuoteFamily(_ scalar: Unicode.Scalar) -> String {
        switch scalar {
        case "\"", "“", "”": return "\""
        case "‘": return "‘"
        case "「", "」": return "「"
        case "『", "』": return "『"
        case "«", "»": return "«"
        case "‹", "›": return "‹"
        default: return String(scalar)
        }
    }

    static func isNumericSeparator(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet(charactersIn: ".,:/-–—").contains(scalar)
    }

    static func isNumericSuffix(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet(charactersIn: "%‰‱°").contains(scalar)
    }

    static func isDegreeSymbol(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "°"
    }

    static func isConnectorSymbol(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet(charactersIn: "@#/\\_+=").contains(scalar)
    }

    static func canAttachConnector(
        _ connector: Unicode.Scalar,
        after scalar: Unicode.Scalar,
        previous: String
    ) -> Bool {
        if connector == "#", currentTokenLength(in: previous) > 1 {
            return false
        }
        return CharacterSet.alphanumerics.contains(scalar)
            || isConnectorSymbol(scalar)
            || scalar == "."
            || scalar == ":"
    }

    static func canAttachAfterConnector(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
            || isConnectorSymbol(scalar)
            || scalar == "."
            || scalar == ":"
    }

    static func isDomainSeparator(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "."
    }

    static func hasConnectorContext(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isConnectorSymbol)
    }

    static func currentTokenLength(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).last?.unicodeScalars.count ?? 0
    }

    static func isCurrencySymbol(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet(charactersIn: "$€£¥₹₩₽₺₪₫₴₦₱฿₡₲₵₸₼₿").contains(scalar)
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF:
            return true
        default:
            return false
        }
    }
}
