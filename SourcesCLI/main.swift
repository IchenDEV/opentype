import AppKit
import Foundation

@main
enum OpenTypeCLI {
    static func main() async {
        do {
            try await CLI().run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as CLIError {
            fputs("opentype: \(error.message)\n", stderr)
            Foundation.exit(Int32(error.exitCode))
        } catch {
            fputs("opentype: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private struct CLI {
    func run(arguments: [String]) async throws {
        var parser = ArgumentParser(arguments: arguments)
        let command = parser.next() ?? "help"

        switch command {
        case "help", "-h", "--help":
            print(Self.help)
        case "status":
            let config = try DeveloperInterfaceConfig.load()
            print(config.enabled ? "enabled 127.0.0.1:\(config.port)" : "disabled")
        case "record":
            let options = try SessionOptions(parser: &parser)
            try await OpenTypeLauncher.launchIfNeeded()
            let client = try HTTPClient(config: .load())
            let session = try await client.createSession(options: options)
            _ = try await client.startRecording(sessionID: session.id)
            fputs("Recording. Press Return to stop.\n", stderr)
            _ = readLine()
            let result = try await client.stopRecording(sessionID: session.id)
            print(options.json ? result.encodedJSON() : result.text)
        case "create":
            let options = try SessionOptions(parser: &parser)
            try await OpenTypeLauncher.launchIfNeeded()
            let session = try await HTTPClient(config: .load()).createSession(options: options)
            print(session.encodedJSON())
        case "start":
            let sessionID = try parser.requiredUUID(name: "session id")
            try await OpenTypeLauncher.launchIfNeeded()
            let session = try await HTTPClient(config: .load()).startRecording(sessionID: sessionID)
            print(session.encodedJSON())
        case "stop":
            let sessionID = try parser.requiredUUID(name: "session id")
            let result = try await HTTPClient(config: .load()).stopRecording(sessionID: sessionID)
            print(result.encodedJSON())
        case "cancel":
            let sessionID = try parser.requiredUUID(name: "session id")
            let session = try await HTTPClient(config: .load()).cancel(sessionID: sessionID)
            print(session?.encodedJSON() ?? "{}")
        case "events":
            let sessionID = try parser.requiredUUID(name: "session id")
            try await HTTPClient(config: .load()).streamEvents(sessionID: sessionID)
        default:
            throw CLIError("unknown command: \(command)")
        }
    }

    private static let help = """
    Usage:
      opentype status
      opentype record [--mode direct|processed|command] [--language auto|zh|en|ja|ko|yue] [--screen-context on|off] [--json]
      opentype create [--mode direct|processed|command] [--language auto|zh|en|ja|ko|yue] [--screen-context on|off]
      opentype start <session-id>
      opentype stop <session-id>
      opentype cancel <session-id>
      opentype events <session-id>
    """
}

private struct DeveloperInterfaceConfig {
    let enabled: Bool
    let port: Int
    let token: String

    static func load() throws -> DeveloperInterfaceConfig {
        guard let defaults = UserDefaults(suiteName: OpenTypeLauncher.bundleIdentifier) else {
            throw CLIError("cannot read OpenType preferences")
        }
        let enabled = defaults.object(forKey: "developerInterfaceEnabled") as? Bool ?? false
        guard enabled else {
            throw CLIError("developer interface is disabled")
        }
        let port = defaults.integer(forKey: "developerHTTPPort")
        let token = defaults.string(forKey: "developerHTTPToken") ?? ""
        guard (1...65_535).contains(port), !token.isEmpty else {
            throw CLIError("developer interface is not configured")
        }
        return DeveloperInterfaceConfig(enabled: enabled, port: port, token: token)
    }
}

private enum OpenTypeLauncher {
    static let bundleIdentifier = "com.opentype.voiceinput"

    static func launchIfNeeded() async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            return
        }
        guard let appURL = findAppURL() else {
            throw CLIError("OpenType.app was not found")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        try await Task.sleep(nanoseconds: 700_000_000)
    }

    private static func findAppURL() -> URL? {
        if let path = ProcessInfo.processInfo.environment["OPENTYPE_APP_PATH"] {
            return URL(fileURLWithPath: path)
        }
        if let bundled = bundledAppURL() {
            return bundled
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications/OpenType.app",
            "\(home)/Applications/OpenType.app"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func bundledAppURL() -> URL? {
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}

private struct HTTPClient {
    let config: DeveloperInterfaceConfig

    func createSession(options: SessionOptions) async throws -> InputSession {
        try await send(
            method: "POST",
            path: "/v1/sessions",
            body: options.requestBody(),
            responseType: InputSession.self
        )
    }

    func startRecording(sessionID: UUID) async throws -> InputSession {
        try await send(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/recording/start", responseType: InputSession.self)
    }

    func stopRecording(sessionID: UUID) async throws -> InputSessionResult {
        try await send(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/recording/stop", responseType: InputSessionResult.self)
    }

    func cancel(sessionID: UUID) async throws -> InputSession? {
        try await send(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/cancel", responseType: InputSession?.self)
    }

    func streamEvents(sessionID: UUID) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request(method: "GET", path: "/v1/sessions/\(sessionID.uuidString)/events"))
        try validate(response: response, body: nil)
        for try await line in bytes.lines {
            print(line)
        }
    }

    private func send<T: Decodable>(method: String, path: String, body: Data? = nil, responseType: T.Type) async throws -> T {
        let request = request(method: method, path: path, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, body: data)
        return try JSONDecoder.integration.decode(T.self, from: data)
    }

    private func request(method: String, path: String, body: Data? = nil) -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = config.port
        components.path = path

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue(CLIIdentity.clientID, forHTTPHeaderField: "X-OpenType-Client-ID")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validate(response: URLResponse, body: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            if let body,
               let payload = try? JSONDecoder.integration.decode(ErrorPayload.self, from: body) {
                throw CLIError("\(payload.error): \(payload.message)", exitCode: http.statusCode == 401 ? 2 : 1)
            }
            throw CLIError("HTTP \(http.statusCode)")
        }
    }
}

private enum CLIIdentity {
    static var clientID: String {
        let encoded = Data(executablePath.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "cli:\(encoded)"
    }

    private static var executablePath: String {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}

private struct SessionOptions {
    var mode: String?
    var language: String?
    var useScreenContext: Bool?
    var json = false

    init(parser: inout ArgumentParser) throws {
        while let option = parser.next() {
            switch option {
            case "--mode":
                mode = try parser.requiredValue(after: option)
            case "--language":
                language = try parser.requiredValue(after: option).mappedLanguage
            case "--screen-context":
                useScreenContext = try parser.requiredValue(after: option).boolValue
            case "--json":
                json = true
            default:
                throw CLIError("unknown option: \(option)")
            }
        }
    }

    func requestBody() throws -> Data {
        var body: [String: Any] = [:]
        if let mode { body["mode"] = mode }
        if let language { body["language"] = language }
        if let useScreenContext { body["use_screen_context"] = useScreenContext }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

private struct InputSession: Codable {
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

private struct SessionRequest: Codable {
    let mode: String?
    let language: String?
    let useScreenContext: Bool?

    enum CodingKeys: String, CodingKey {
        case mode
        case language
        case useScreenContext = "use_screen_context"
    }
}

private struct InputSessionResult: Codable {
    let session: InputSession
    let transcript: String
    let text: String
}

private struct ErrorPayload: Decodable {
    let error: String
    let message: String
}

private struct CLIError: Error {
    let message: String
    let exitCode: Int

    init(_ message: String, exitCode: Int = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}

private struct ArgumentParser {
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

private extension String {
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
}

private extension Encodable {
    func encodedJSON() -> String {
        let data = (try? JSONEncoder.integration.encode(self)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private extension JSONEncoder {
    static var integration: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var integration: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
