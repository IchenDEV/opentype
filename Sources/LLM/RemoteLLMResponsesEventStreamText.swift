import Foundation

enum RemoteLLMResponsesEventStreamText {
    static func text(from eventStream: String) -> String? {
        var textParts: [String] = []
        var functionArguments: [String: String] = [:]
        var sawResponsesEvent = false

        for payload in eventPayloads(in: eventStream) {
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let type = (json.value(forCaseInsensitiveKey: "type") as? String) ?? ""
            let eventType = normalizedEventType(type)
            guard eventType.hasPrefix("response") else { continue }
            sawResponsesEvent = true

            switch eventType {
            case "responseoutputtextdelta":
                if let delta = json.value(forCaseInsensitiveKey: "delta") as? String {
                    textParts.append(delta)
                }
            case "responseoutputtextdone":
                if textParts.isEmpty,
                   let text = json.value(forCaseInsensitiveKey: "text") as? String {
                    textParts.append(text)
                }
            case "responsefunctioncallargumentsdelta":
                if let delta = json.value(forCaseInsensitiveKey: "delta") as? String {
                    functionArguments[eventKey(in: json), default: ""] += delta
                }
            case "responsefunctioncallargumentsdone":
                if let arguments = json.value(forCaseInsensitiveKey: "arguments") as? String {
                    functionArguments[eventKey(in: json)] = arguments
                }
            case "responseoutputitemdone":
                if let item = json.value(forCaseInsensitiveKey: "item") as? [String: Any],
                   let text = RemoteLLMResponseText.openAIText(in: ["output": [item]]) {
                    return text
                }
            default:
                if let text = RemoteLLMResponseText.openAIText(in: json) {
                    return text
                }
            }
        }

        guard sawResponsesEvent else { return nil }
        if let text = functionArgumentsText(functionArguments) {
            return text
        }
        return nonEmpty(textParts.joined())
    }
}

private extension RemoteLLMResponsesEventStreamText {
    static func eventPayloads(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var payloads: [String] = []
        var dataLines: [String] = []

        func flush() {
            guard !dataLines.isEmpty else { return }
            payloads.append(dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
            dataLines.removeAll()
        }

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
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

    static func functionArgumentsText(_ functionArguments: [String: String]) -> String? {
        for key in functionArguments.keys.sorted() {
            let arguments = functionArguments[key] ?? ""
            let payload: [String: Any] = ["output": [["type": "function_call", "arguments": arguments]]]
            guard let text = RemoteLLMResponseText.openAIText(in: payload) else { continue }
            return text
        }
        return nil
    }

    static func eventKey(in json: [String: Any]) -> String {
        if let itemID = json.value(forCaseInsensitiveKey: "item_id") as? String, !itemID.isEmpty {
            return itemID
        }
        if let outputIndex = intValue(json.value(forCaseInsensitiveKey: "output_index")) {
            return String(outputIndex)
        }
        return "0"
    }

    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    static func normalizedEventType(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
