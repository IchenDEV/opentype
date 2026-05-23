import Foundation

struct SessionOptions {
    var mode: String?
    var language: String?
    var useScreenContext: Bool?
    var audioPath: String?
    var json = false

    init(parser: inout ArgumentParser, requiresAudio: Bool = false) throws {
        while let option = parser.next() {
            switch option {
            case "--mode":
                mode = try parser.requiredValue(after: option)
            case "--language":
                language = try parser.requiredValue(after: option).mappedLanguage
            case "--screen-context":
                useScreenContext = try parser.requiredValue(after: option).boolValue
            case "--audio":
                audioPath = try parser.requiredValue(after: option)
            case "--json":
                json = true
            default:
                throw CLIError("unknown option: \(option)")
            }
        }
        if requiresAudio, audioPath == nil {
            throw CLIError("missing --audio path")
        }
    }

    func requestBody() throws -> Data {
        var body: [String: Any] = [:]
        if let mode { body["mode"] = mode }
        if let language { body["language"] = language }
        if let useScreenContext { body["use_screen_context"] = useScreenContext }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    func requiredAudioURL() throws -> URL {
        guard let audioPath else {
            throw CLIError("missing --audio path")
        }
        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError("audio file does not exist: \(audioPath)")
        }
        return url
    }
}

struct InputSession: Codable {
    let id: UUID
    let request: SessionRequest
    let state: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case request
        case state
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SessionRequest: Codable {
    let mode: String?
    let language: String?
    let useScreenContext: Bool?

    enum CodingKeys: String, CodingKey {
        case mode
        case language
        case useScreenContext = "use_screen_context"
    }
}

struct InputSessionResult: Codable {
    let session: InputSession
    let transcript: String
    let text: String
}

struct ErrorPayload: Decodable {
    let error: String
    let message: String
}

struct CLIError: Error {
    let message: String
    let exitCode: Int

    init(_ message: String, exitCode: Int = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}
