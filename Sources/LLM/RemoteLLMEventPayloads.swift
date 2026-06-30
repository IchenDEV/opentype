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
        var eventName: String?

        func flush() {
            guard !dataLines.isEmpty else { return }
            let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            payloads.append(payloadWithEventType(payload, eventName: eventName))
            dataLines.removeAll()
            eventName = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                flush()
                continue
            }
            let rawLine = String(line)
            if rawLine.localizedCaseInsensitiveComparePrefix("event:") {
                eventName = String(rawLine.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            guard rawLine.localizedCaseInsensitiveComparePrefix("data:") else { continue }
            dataLines.append(String(rawLine.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        flush()
        return payloads.filter { !$0.isEmpty }
    }

    static func payloadWithEventType(_ payload: String, eventName: String?) -> String {
        guard let eventName,
              !eventName.isEmpty,
              let data = payload.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.value(forCaseInsensitiveKey: "type") == nil else {
            return payload
        }
        object["type"] = eventName
        guard JSONSerialization.isValidJSONObject(object),
              let typedData = try? JSONSerialization.data(withJSONObject: object),
              let typedPayload = String(data: typedData, encoding: .utf8) else {
            return payload
        }
        return typedPayload
    }
}

private extension String {
    func localizedCaseInsensitiveComparePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }
}

private extension Dictionary where Key == String {
    func value(forCaseInsensitiveKey key: String) -> Value? {
        if let value = self[key] {
            return value
        }
        return first { $0.key.localizedCaseInsensitiveCompare(key) == .orderedSame }?.value
    }
}
