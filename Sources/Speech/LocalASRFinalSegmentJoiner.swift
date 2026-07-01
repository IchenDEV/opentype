import Foundation

enum LocalASRFinalSegmentJoiner {
    static func join(_ parts: [String]) -> String? {
        var merged: [String] = []
        for part in parts {
            append(part, to: &merged)
        }
        guard !merged.isEmpty else { return nil }
        return LocalASRTranscriptJoiner.join(merged)
    }
}

private extension LocalASRFinalSegmentJoiner {
    static func append(_ rawPart: String, to parts: inout [String]) {
        let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !part.isEmpty else { return }

        guard let last = parts.last else {
            parts.append(part)
            return
        }

        let lastKey = normalized(last)
        let partKey = normalized(part)
        if !lastKey.isEmpty, lastKey == partKey {
            if part.count > last.count {
                parts[parts.count - 1] = part
            }
            return
        }
        if isCumulativeUpdate(previous: last, next: part) {
            parts[parts.count - 1] = part
            return
        }
        if isCumulativeUpdate(previous: part, next: last) {
            return
        }
        parts.append(part)
    }

    static func isCumulativeUpdate(previous: String, next: String) -> Bool {
        let previous = normalized(previous)
        let next = normalized(next)
        guard previous.count >= 3 else { return false }
        return next.hasPrefix(previous)
    }

    static func normalized(_ text: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits)
        return String(text.lowercased().unicodeScalars.filter { allowed.contains($0) })
    }
}
