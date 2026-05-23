import Foundation

struct ArgumentParser {
    private var arguments: [String]
    private var index = 0

    init(arguments: [String]) {
        self.arguments = arguments
    }

    mutating func next() -> String? {
        guard index < arguments.count else { return nil }
        defer { index += 1 }
        return arguments[index]
    }

    mutating func requiredValue(after option: String) throws -> String {
        guard let value = next(), !value.hasPrefix("--") else {
            throw CLIError("missing value after \(option)")
        }
        return value
    }

    mutating func requiredUUID(name: String) throws -> UUID {
        guard let value = next(), let id = UUID(uuidString: value) else {
            throw CLIError("missing or invalid \(name)")
        }
        return id
    }
}

extension String {
    var mappedLanguage: String {
        switch lowercased() {
        case "auto": return "Auto"
        case "zh", "chinese", "中文": return "中文"
        case "en", "english": return "English"
        case "ja", "japanese", "日本語": return "日本語"
        case "ko", "korean", "한국어": return "한국어"
        case "yue", "cantonese", "粤语": return "粤语"
        default: return self
        }
    }

    var boolValue: Bool {
        get throws {
            switch lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: throw CLIError("expected on/off boolean, got \(self)")
            }
        }
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Encodable {
    func encodedJSON() -> String {
        let data = (try? JSONEncoder.integration.encode(self)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

extension JSONEncoder {
    static var integration: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var integration: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
