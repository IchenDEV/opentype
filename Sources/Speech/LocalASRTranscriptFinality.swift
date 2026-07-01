import Foundation

enum LocalASRTranscriptFinality {
    static func priority(in object: [String: Any]? = nil, structuralPriority: Int) -> Int {
        finality(in: object).priority + structuralPriority
    }

    static func hasMetadata(in object: [String: Any]) -> Bool {
        finality(in: object) != .unknown
    }

    static func isFinal(in object: [String: Any]) -> Bool {
        finality(in: object) == .final
    }
}

private enum TranscriptFinality {
    case final
    case unknown
    case partial

    var priority: Int {
        switch self {
        case .final: return 200
        case .unknown: return 100
        case .partial: return 0
        }
    }
}

private extension LocalASRTranscriptFinality {
    static let finalityBooleanKeys = [
        "is_final", "isFinal", "final",
        "final_result", "finalResult", "is_final_result", "isFinalResult",
        "speech_final", "speechFinal",
        "sentence_end", "sentenceEnd", "utterance_end", "utteranceEnd",
        "end_of_speech", "endOfSpeech", "is_eos", "isEos",
    ]
    static let partialBooleanKeys = [
        "is_partial", "isPartial", "partial",
        "is_interim", "isInterim", "interim",
    ]
    static let finalityStringKeys = [
        "type", "status", "state", "event",
        "result_type", "resultType", "message_type", "messageType",
        "recognition_status", "recognitionStatus",
    ]

    static func finality(in object: [String: Any]?) -> TranscriptFinality {
        guard let object else { return .unknown }
        if boolValue(forAnyKey: finalityBooleanKeys, in: object) == true {
            return .final
        }
        if boolValue(forAnyKey: partialBooleanKeys, in: object) == true {
            return .partial
        }
        if boolValue(forAnyKey: finalityBooleanKeys, in: object) == false {
            return .partial
        }
        if boolValue(forAnyKey: partialBooleanKeys, in: object) == false {
            return .final
        }
        for key in finalityStringKeys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let finality = finality(from: value) else {
                continue
            }
            return finality
        }
        return .unknown
    }

    static func boolValue(forAnyKey keys: [String], in object: [String: Any]) -> Bool? {
        for key in keys {
            guard let value = object.value(forCaseInsensitiveKey: key),
                  let bool = boolValue(from: value) else {
                continue
            }
            return bool
        }
        return nil
    }

    static func boolValue(from value: Any) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    static func finality(from value: Any) -> TranscriptFinality? {
        guard let text = value as? String else { return nil }
        switch normalizedStatus(text) {
        case "final", "finaltranscript", "finalresult",
             "sentenceend", "utteranceend", "speechend", "endofspeech", "endoftranscript",
             "complete", "completed", "done", "success", "succeeded", "finished", "finalized", "recognized":
            return .final
        case "partial", "partialtranscript", "partialresult",
             "interim", "intermediate", "temporary", "streaming", "inprogress", "recognizing", "processing", "running":
            return .partial
        default:
            return nil
        }
    }

    static func normalizedStatus(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
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
