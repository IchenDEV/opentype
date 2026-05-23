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
    private var eventsBySession: [UUID: [InputSessionEvent]]
    private var nextSequenceBySession: [UUID: Int]
    private let settings: IntegrationServiceSettings
    private let registry: IntegrationClientRegistry

    convenience init(registry: IntegrationClientRegistry = IntegrationClientRegistry()) {
        self.init(settings: .live, registry: registry)
    }

    init(settings: IntegrationServiceSettings, registry: IntegrationClientRegistry = IntegrationClientRegistry()) {
        self.sessions = [:]
        self.eventsBySession = [:]
        self.nextSequenceBySession = [:]
        self.settings = settings
        self.registry = registry
    }

    func createSession(_ request: InputSessionRequest, clientID: String) async throws -> InputSession {
        guard settings.developerInterfaceEnabled else {
            throw IntegrationError.developerInterfaceDisabled
        }
        guard registry.isAuthorized(clientID: clientID, capability: .record) else {
            throw IntegrationError.unauthorizedClient
        }
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
        nextSequenceBySession[session.id] = 1
        appendEvent(.sessionCreated, sessionID: session.id, at: now)
        registry.markUsed(clientID: clientID, at: now)

        return session
    }

    func startRecording(sessionID: UUID) async throws {
        guard var session = sessions[sessionID] else {
            throw IntegrationError.sessionNotFound
        }
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

    func cancel(sessionID: UUID) async {
        guard var session = sessions[sessionID], !session.state.isTerminal else {
            return
        }

        let now = Date()
        session.state = .cancelled
        session.updatedAt = now
        sessions[sessionID] = session
        appendEvent(.sessionCancelled, sessionID: sessionID, at: now)
    }

    func session(_ id: UUID) -> InputSession? {
        sessions[id]
    }

    func snapshotEvents(sessionID: UUID) -> [InputSessionEvent] {
        eventsBySession[sessionID] ?? []
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
