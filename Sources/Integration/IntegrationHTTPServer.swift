import Foundation
import Network

@MainActor
final class IntegrationHTTPServer {
    private let port: Int
    private let service: OpenTypeService
    private let registry: IntegrationClientRegistry
    private let settingsProvider: @MainActor () -> IntegrationServiceSettings
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection]

    init(
        port: Int,
        service: OpenTypeService,
        registry: IntegrationClientRegistry,
        settingsProvider: @escaping @MainActor () -> IntegrationServiceSettings = { .live }
    ) {
        self.port = port
        self.service = service
        self.registry = registry
        self.settingsProvider = settingsProvider
        self.activeConnections = [:]
    }

    func start() throws {
        guard listener == nil else {
            return
        }
        guard (1...65_535).contains(port), let listenerPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw IntegrationHTTPServerError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: listenerPort)

        let newListener = try NWListener(using: parameters)
        newListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        newListener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                Log.error("Integration HTTP server failed: \(error.localizedDescription)")
            }
        }

        listener = newListener
        newListener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
    }

    func dispatch(_ request: IntegrationHTTPRequest) async -> IntegrationHTTPResponse {
        let settings = settingsProvider()
        guard settings.developerInterfaceEnabled else {
            return IntegrationHTTPResponse.error(.developerInterfaceDisabled, statusCode: 401)
        }
        guard let token = request.bearerToken, token == settings.httpToken else {
            return IntegrationHTTPResponse.error(.unauthorizedClient, statusCode: 401)
        }

        let client = IntegrationClient.localHTTP(tokenID: token)
        registry.approve(client)

        do {
            switch IntegrationHTTPRoute.match(method: request.method, path: request.path) {
            case .createSession:
                let sessionRequest = try decodeSessionRequest(from: request.body)
                let session = try await service.createSession(sessionRequest, clientID: client.id)
                return IntegrationHTTPResponse.json(session, statusCode: 201)
            case let .events(sessionID):
                let events = try service.snapshotEvents(sessionID: sessionID, clientID: client.id)
                let body = try IntegrationSSE.encode(events)
                return IntegrationHTTPResponse(
                    statusCode: 200,
                    reason: "OK",
                    headers: [
                        "Cache-Control": "no-cache",
                        "Content-Type": "text/event-stream"
                    ],
                    body: body
                )
            case let .startRecording(sessionID):
                try await service.startRecording(sessionID: sessionID, clientID: client.id)
                guard let session = try service.session(sessionID, clientID: client.id) else {
                    return IntegrationHTTPResponse.notFound()
                }
                return IntegrationHTTPResponse.json(session, statusCode: 202)
            case let .stopRecording(sessionID):
                try await service.beginProcessing(sessionID: sessionID, clientID: client.id)
                try await service.completeSession(sessionID: sessionID, clientID: client.id, finalText: nil)
                guard let session = try service.session(sessionID, clientID: client.id) else {
                    return IntegrationHTTPResponse.notFound()
                }
                return IntegrationHTTPResponse.json(session, statusCode: 202)
            case let .cancel(sessionID):
                guard try service.session(sessionID, clientID: client.id) != nil else {
                    return IntegrationHTTPResponse(statusCode: 204, reason: "No Content", headers: [:], body: Data())
                }
                try await service.cancel(sessionID: sessionID, clientID: client.id)
                guard let session = try service.session(sessionID, clientID: client.id) else {
                    return IntegrationHTTPResponse.notFound()
                }
                return IntegrationHTTPResponse.json(session, statusCode: 202)
            case .notFound:
                return IntegrationHTTPResponse.notFound()
            }
        } catch let error as IntegrationError {
            return IntegrationHTTPResponse.error(error, statusCode: Self.statusCode(for: error))
        } catch is DecodingError {
            return Self.badRequest(message: "Request body is not valid JSON.")
        } catch {
            return Self.internalServerError()
        }
    }

    nonisolated static func statusCode(for error: Error) -> Int {
        guard let error = error as? IntegrationError else {
            return 500
        }
        switch error {
        case .developerInterfaceDisabled, .unauthorizedClient:
            return 401
        case .busy, .invalidSessionState, .sessionCancelled:
            return 409
        case .sessionNotFound:
            return 404
        case .permissionDenied, .modelNotReady:
            return 400
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        activeConnections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                Task { @MainActor in
                    self?.activeConnections[id] = nil
                }
            default:
                break
            }
        }

        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else {
                    connection.cancel()
                    return
                }
                guard error == nil else {
                    self.send(Self.badRequest(message: "Malformed HTTP request."), on: connection)
                    return
                }

                var nextBuffer = buffer
                if let data {
                    nextBuffer.append(data)
                }

                if Self.hasCompleteRequest(nextBuffer) || isComplete {
                    await self.respond(to: nextBuffer, on: connection)
                } else {
                    self.receive(on: connection, buffer: nextBuffer)
                }
            }
        }
    }

    private func respond(to data: Data, on connection: NWConnection) async {
        guard let request = IntegrationHTTPRequest.parse(from: data) else {
            send(Self.badRequest(message: "Malformed HTTP request."), on: connection)
            return
        }

        let response = await dispatch(request)
        send(response, on: connection)
    }

    private func send(_ response: IntegrationHTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialize(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func decodeSessionRequest(from body: Data) throws -> InputSessionRequest {
        guard !body.isEmpty else {
            return InputSessionRequest(mode: nil, language: nil, useScreenContext: nil)
        }
        return try JSONDecoder.integration.decode(InputSessionRequest.self, from: body)
    }

    private nonisolated static func hasCompleteRequest(_ data: Data) -> Bool {
        let delimiter = Data([13, 10, 13, 10])
        guard let delimiterRange = data.range(of: delimiter) else {
            return false
        }
        guard let head = String(data: data[..<delimiterRange.lowerBound], encoding: .utf8) else {
            return true
        }

        let contentLength = head
            .components(separatedBy: "\r\n")
            .dropFirst()
            .compactMap { line -> Int? in
                guard let colonIndex = line.firstIndex(of: ":") else {
                    return nil
                }
                let name = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.caseInsensitiveCompare("Content-Length") == .orderedSame else {
                    return nil
                }
                let valueStart = line.index(after: colonIndex)
                return Int(line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0

        let bodyLength = data.count - delimiterRange.upperBound
        return bodyLength >= contentLength
    }

    private nonisolated static func badRequest(message: String) -> IntegrationHTTPResponse {
        IntegrationHTTPResponse.json(
            IntegrationError.Payload(error: "bad_request", message: message),
            statusCode: 400
        )
    }

    private nonisolated static func internalServerError() -> IntegrationHTTPResponse {
        IntegrationHTTPResponse.json(
            IntegrationError.Payload(error: "internal_server_error", message: "Internal server error."),
            statusCode: 500
        )
    }
}

private enum IntegrationHTTPServerError: Error {
    case invalidPort
}
