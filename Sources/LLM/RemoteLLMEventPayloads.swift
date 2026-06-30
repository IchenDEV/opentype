import Foundation

enum RemoteLLMEventPayloads {
    static func values(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let ssePayloads = sseValues(in: normalized)
        if !ssePayloads.isEmpty { return ssePayloads }

        return normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("{") || $0.hasPrefix("[") }
    }
}

private extension RemoteLLMEventPayloads {
    static func sseValues(in text: String) -> [String] {
        var payloads: [String] = []
        var dataLines: [String] = []

        func flush() {
            guard !dataLines.isEmpty else { return }
            payloads.append(dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
            dataLines.removeAll()
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                flush()
                continue
            }
            let rawLine = String(line)
            guard rawLine.localizedCaseInsensitiveComparePrefix("data:") else { continue }
            dataLines.append(String(rawLine.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        flush()
        return payloads.filter { !$0.isEmpty }
    }
}

private extension String {
    func localizedCaseInsensitiveComparePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }
}
