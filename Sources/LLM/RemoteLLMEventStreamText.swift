import Foundation

enum RemoteLLMEventStreamText {
    static func openAI(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              text.localizedCaseInsensitiveContains("data:") else {
            return nil
        }
        if let text = RemoteLLMResponsesEventStreamText.text(from: text) {
            return text
        }

        var contentParts: [String] = []
        var toolArguments: [Int: String] = [:]
        var functionArguments = ""

        for payload in eventPayloads(in: text) {
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if hasDelta(in: json) {
                collectDeltaPayloads(
                    from: json,
                    contentParts: &contentParts,
                    toolArguments: &toolArguments,
                    functionArguments: &functionArguments
                )
            } else if let text = RemoteLLMResponseText.openAIText(in: json) {
                return text
            }
        }

        if let text = toolArgumentsText(toolArguments) {
            return text
        }
        if let text = functionArgumentsText(functionArguments) {
            return text
        }
        return nonEmpty(contentParts.joined())
    }

    static func anthropic(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              text.localizedCaseInsensitiveContains("data:") else {
            return nil
        }

        var textParts: [Int: String] = [:]
        var toolInputs: [Int: String] = [:]

        for payload in eventPayloads(in: text) {
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let text = RemoteLLMResponseText.anthropicText(in: json) {
                return text
            }
            collectAnthropicPayload(from: json, textParts: &textParts, toolInputs: &toolInputs)
        }

        if let text = anthropicToolText(toolInputs) {
            return text
        }
        return anthropicText(textParts)
    }
}

private extension RemoteLLMEventStreamText {
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

    static func hasDelta(in json: [String: Any]) -> Bool {
        guard let choices = json.value(forCaseInsensitiveKey: "choices") as? [Any] else { return false }
        return choices.contains { choice in
            (choice as? [String: Any])?.value(forCaseInsensitiveKey: "delta") != nil
        }
    }

    static func collectDeltaPayloads(
        from json: [String: Any],
        contentParts: inout [String],
        toolArguments: inout [Int: String],
        functionArguments: inout String
    ) {
        guard let choices = json.value(forCaseInsensitiveKey: "choices") as? [Any] else { return }
        for case let choice as [String: Any] in choices {
            guard let delta = choice.value(forCaseInsensitiveKey: "delta") as? [String: Any] else { continue }
            if let content = delta.value(forCaseInsensitiveKey: "content") as? String {
                contentParts.append(content)
            } else if let content = delta.value(forCaseInsensitiveKey: "content"),
                      let text = RemoteLLMStreamContentDeltaText.text(from: content) {
                contentParts.append(text)
            }
            appendToolArguments(from: delta.value(forCaseInsensitiveKey: "tool_calls"), to: &toolArguments)
            appendFunctionArguments(from: delta.value(forCaseInsensitiveKey: "function_call"), to: &functionArguments)
        }
    }

    static func appendToolArguments(from value: Any?, to toolArguments: inout [Int: String]) {
        guard let calls = value as? [Any] else { return }
        for (fallbackIndex, value) in calls.enumerated() {
            guard let call = value as? [String: Any] else { continue }
            let index = intValue(call.value(forCaseInsensitiveKey: "index")) ?? fallbackIndex
            if let arguments = argumentsText(in: call) {
                toolArguments[index, default: ""] += arguments
            }
            if let function = call.value(forCaseInsensitiveKey: "function") as? [String: Any],
               let arguments = argumentsText(in: function) {
                toolArguments[index, default: ""] += arguments
            }
        }
    }

    static func appendFunctionArguments(from value: Any?, to functionArguments: inout String) {
        guard let function = value as? [String: Any],
              let arguments = argumentsText(in: function) else {
            return
        }
        functionArguments += arguments
    }

    static func collectAnthropicPayload(
        from json: [String: Any],
        textParts: inout [Int: String],
        toolInputs: inout [Int: String]
    ) {
        if let block = json.value(forCaseInsensitiveKey: "content_block") as? [String: Any],
           let index = intValue(json.value(forCaseInsensitiveKey: "index")) {
            collectAnthropicStartBlock(block, index: index, textParts: &textParts, toolInputs: &toolInputs)
        }

        guard let delta = json.value(forCaseInsensitiveKey: "delta") as? [String: Any],
              let index = intValue(json.value(forCaseInsensitiveKey: "index")) else {
            return
        }
        if let text = delta.value(forCaseInsensitiveKey: "text") as? String {
            textParts[index, default: ""] += text
        }
        if let partialJSON = delta.value(forCaseInsensitiveKey: "partial_json") as? String {
            toolInputs[index, default: ""] += partialJSON
        }
    }

    static func collectAnthropicStartBlock(
        _ block: [String: Any],
        index: Int,
        textParts: inout [Int: String],
        toolInputs: inout [Int: String]
    ) {
        if let text = block.value(forCaseInsensitiveKey: "text") as? String {
            textParts[index, default: ""] += text
        }
        if let input = block.value(forCaseInsensitiveKey: "input"),
           let text = jsonString(from: input) {
            guard text != "{}" else { return }
            toolInputs[index, default: ""] += text
        }
    }

    static func argumentsText(in object: [String: Any]) -> String? {
        for key in ["arguments", "args", "parameters", "params", "input"] {
            guard let value = object.value(forCaseInsensitiveKey: key) else { continue }
            if let text = value as? String, !text.isEmpty {
                return text
            }
            if let text = jsonString(from: value) {
                return text
            }
        }
        return nil
    }

    static func toolArgumentsText(_ toolArguments: [Int: String]) -> String? {
        for key in toolArguments.keys.sorted() {
            guard let text = payloadText(fromArguments: toolArguments[key] ?? "", toolKey: "tool_calls") else {
                continue
            }
            return text
        }
        return nil
    }

    static func functionArgumentsText(_ functionArguments: String) -> String? {
        payloadText(fromArguments: functionArguments, toolKey: "function_call")
    }

    static func anthropicToolText(_ toolInputs: [Int: String]) -> String? {
        for key in toolInputs.keys.sorted() {
            let input = normalizedAnthropicToolInput(toolInputs[key] ?? "")
            let payload: [String: Any] = ["content": [["type": "tool_use", "input": input]]]
            guard let text = RemoteLLMResponseText.anthropicText(in: payload) else { continue }
            return text
        }
        return nil
    }

    static func normalizedAnthropicToolInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("{") else { return trimmed }
        return "{\(trimmed)}"
    }

    static func anthropicText(_ textParts: [Int: String]) -> String? {
        let parts = textParts.keys.sorted().compactMap { nonEmpty(textParts[$0] ?? "") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    static func payloadText(fromArguments arguments: String, toolKey: String) -> String? {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let payload: [String: Any]
        if toolKey == "tool_calls" {
            payload = ["choices": [["message": ["tool_calls": [["function": ["arguments": trimmed]]]]]]]
        } else {
            payload = ["choices": [["message": ["function_call": ["arguments": trimmed]]]]]
        }
        return RemoteLLMResponseText.openAIText(in: payload)
    }

    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    static func jsonString(from value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
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
