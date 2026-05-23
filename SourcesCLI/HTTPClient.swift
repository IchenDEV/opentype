import Foundation

struct HTTPClient {
    let config: DeveloperInterfaceConfig

    func createSession(options: SessionOptions) async throws -> InputSession {
        try await send(
            method: "POST",
            path: "/v1/sessions",
            body: options.requestBody(),
            headers: ["Content-Type": "application/json"],
            responseType: InputSession.self
        )
    }

    func startRecording(sessionID: UUID) async throws -> InputSession {
        try await send(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/recording/start", responseType: InputSession.self)
    }

    func stopRecording(sessionID: UUID) async throws -> InputSessionResult {
        try await send(method: "POST", path: "/v1/sessions/\(sessionID.uuidString)/recording/stop", responseType: InputSessionResult.self)
    }

    func submitAudio(sessionID: UUID, audioURL: URL) async throws -> InputSessionResult {
        let data = try Data(contentsOf: audioURL)
        return try await send(
            method: "POST",
            path: "/v1/sessions/\(sessionID.uuidString)/audio",
            body: data,
            headers: ["X-OpenType-Audio-Extension": audioURL.pathExtension.nonEmpty ?? "wav"],
            responseType: InputSessionResult.self
        )
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

    private func send<T: Decodable>(
        method: String,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:],
        responseType: T.Type
    ) async throws -> T {
        let request = request(method: method, path: path, body: body, headers: headers)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, body: data)
        return try JSONDecoder.integration.decode(T.self, from: data)
    }

    private func request(
        method: String,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = config.port
        components.path = path

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        request.setValue(CLIIdentity.clientID, forHTTPHeaderField: "X-OpenType-Client-ID")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.httpBody = body
            request.setValue(headers["Content-Type"] ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
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
