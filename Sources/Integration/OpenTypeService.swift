import Foundation

struct IntegrationServiceSettings {
    var developerInterfaceEnabled: Bool
    var httpToken: String

    @MainActor
    static var live: IntegrationServiceSettings {
        IntegrationServiceSettings(
            developerInterfaceEnabled: AppSettings.shared.developerInterfaceEnabled,
            httpToken: AppSettings.shared.developerHTTPToken
        )
    }
}

@MainActor
final class OpenTypeService {
    private var sessions: [UUID: InputSession]
    private var sessionOwners: [UUID: String]
    private var eventsBySession: [UUID: [InputSessionEvent]]
    private var nextSequenceBySession: [UUID: Int]
    private let settingsProvider: @MainActor () -> IntegrationServiceSettings
    private let registry: IntegrationClientRegistry

    convenience init(registry: IntegrationClientRegistry = IntegrationClientRegistry()) {
        self.init(settingsProvider: { .live }, registry: registry)
    }

    convenience init(settings: IntegrationServiceSettings, registry: IntegrationClientRegistry = IntegrationClientRegistry()) {
        self.init(settingsProvider: { settings }, registry: registry)
    }

    init(
        settingsProvider: @escaping @MainActor () -> IntegrationServiceSettings,
        registry: IntegrationClientRegistry = IntegrationClientRegistry()
    ) {
        self.sessions = [:]
        self.sessionOwners = [:]
        self.eventsBySession = [:]
        self.nextSequenceBySession = [:]
        self.settingsProvider = settingsProvider
        self.registry = registry
    }

    func createSession(_ request: InputSessionRequest, clientID: String) async throws -> InputSession {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard sessions.values.allSatisfy({ $0.state.isTerminal }) else {
            throw IntegrationError.busy
        }

        let now = Date()
        let session = InputSession(
            id: UUID(),
            request: request,
            state: .created,
            createdAt: now,
            updatedAt: now
        )
        sessions[session.id] = session
        sessionOwners[session.id] = clientID
        nextSequenceBySession[session.id] = 1
        appendEvent(.sessionCreated, sessionID: session.id, at: now)
        registry.markUsed(clientID: clientID, at: now)

        return session
    }

    func startRecording(sessionID: UUID, clientID: String) async throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            throw IntegrationError.sessionNotFound
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard session.state == .created else {
            throw IntegrationError.invalidSessionState
        }
        guard !sessions.values.contains(where: { $0.id != sessionID && $0.state == .recording }) else {
            throw IntegrationError.busy
        }

        let now = Date()
        session.state = .recording
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.recordingStarted, sessionID: sessionID, at: now)
    }

    func cancel(sessionID: UUID, clientID: String) async throws {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard var session = sessions[sessionID] else {
            return
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        guard !session.state.isTerminal else {
            return
        }

        let now = Date()
        session.state = .cancelled
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.sessionCancelled, sessionID: sessionID, at: now)
    }

    func session(_ id: UUID, clientID: String) throws -> InputSession? {
        try requireAuthorized(clientID: clientID, capability: .record)
        guard let session = sessions[id] else {
            return nil
        }
        try requireOwner(sessionID: id, clientID: clientID)
        return session
    }

    func snapshotEvents(sessionID: UUID, clientID: String) throws -> [InputSessionEvent] {
        try requireAuthorized(clientID: clientID, capability: .streamEvents)
        guard sessionOwners[sessionID] != nil else {
            return []
        }
        try requireOwner(sessionID: sessionID, clientID: clientID)
        return eventsBySession[sessionID] ?? []
    }

    private func requireAuthorized(clientID: String, capability: IntegrationClient.Capability) throws {
        guard settingsProvider().developerInterfaceEnabled else {
            throw IntegrationError.developerInterfaceDisabled
        }
        guard registry.isAuthorized(clientID: clientID, capability: capability) else {
            throw IntegrationError.unauthorizedClient
        }
    }

    private func requireOwner(sessionID: UUID, clientID: String) throws {
        guard sessionOwners[sessionID] == clientID else {
            throw IntegrationError.unauthorizedClient
        }
    }

    private func appendEvent(_ type: InputSessionEvent.EventType, sessionID: UUID, at timestamp: Date) {
        let sequence = nextSequenceBySession[sessionID] ?? 1
        let event = InputSessionEvent(
            type: type,
            sessionID: sessionID,
            sequence: sequence,
            timestamp: timestamp,
            text: nil,
            error: nil
        )
        eventsBySession[sessionID, default: []].append(event)
        nextSequenceBySession[sessionID] = sequence + 1
    }
}
