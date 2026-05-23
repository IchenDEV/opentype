import Foundation
import XCTest
@testable import OpenType

@MainActor
final class OpenTypeServiceTests: XCTestCase {
    func testCreateSessionFailsWhenDeveloperInterfaceDisabled() async {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: false, httpToken: "token"),
            registry: store.registry
        )

        await assertThrowsIntegrationError(.developerInterfaceDisabled) {
            try await service.createSession(request(), clientID: clientID)
        }
    }

    func testCreateSessionFailsForUnauthorizedClient() async {
        let store = registry()
        defer { store.cleanup() }
        let service = OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token"),
            registry: store.registry
        )

        await assertThrowsIntegrationError(.unauthorizedClient) {
            try await service.createSession(request(), clientID: clientID)
        }
    }

    func testCreateSessionEmitsCreatedEvent() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)

        let session = try await service.createSession(request(), clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID), session)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .sessionCreated)
        XCTAssertEqual(events.first?.sessionID, session.id)
        XCTAssertEqual(events.first?.sequence, 1)
        XCTAssertNotNil(store.registry.client(id: clientID)?.lastUsedAt)
    }

    func testOnlyOneActiveSessionCanRecord() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let first = try await service.createSession(request(), clientID: clientID)
        try await service.startRecording(sessionID: first.id, clientID: clientID)

        await assertThrowsIntegrationError(.busy) {
            try await service.createSession(request(), clientID: clientID)
        }
        XCTAssertEqual(try service.session(first.id, clientID: clientID)?.state, .recording)
    }

    func testCancelSessionTransitionsToTerminalState() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        try await service.cancel(sessionID: session.id, clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .cancelled)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(events.map(\.type), [.sessionCreated, .sessionCancelled])
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testStartRecordingIncrementsEventSequence() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        try await service.startRecording(sessionID: session.id, clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .recording)
        let events = try service.snapshotEvents(sessionID: session.id, clientID: clientID)
        XCTAssertEqual(events.map(\.type), [.sessionCreated, .recordingStarted])
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testCancelNoOpsForMissingAndTerminalSessions() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        try await service.cancel(sessionID: UUID(), clientID: clientID)
        try await service.cancel(sessionID: session.id, clientID: clientID)
        try await service.cancel(sessionID: session.id, clientID: clientID)

        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .cancelled)
        XCTAssertEqual(
            try service.snapshotEvents(sessionID: session.id, clientID: clientID).map(\.type),
            [.sessionCreated, .sessionCancelled]
        )
    }

    func testOtherApprovedClientCannotStartOwnedSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        approveOtherLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            try await service.startRecording(sessionID: session.id, clientID: otherClientID)
        }
    }

    func testOtherApprovedClientCannotCancelOwnedSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        approveOtherLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            try await service.cancel(sessionID: session.id, clientID: otherClientID)
        }
        XCTAssertEqual(try service.session(session.id, clientID: clientID)?.state, .created)
    }

    func testOtherApprovedClientCannotReadOwnedSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        approveOtherLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            _ = try service.session(session.id, clientID: otherClientID)
        }
        await assertThrowsIntegrationError(.unauthorizedClient) {
            _ = try service.snapshotEvents(sessionID: session.id, clientID: otherClientID)
        }
    }

    func testClientWithoutStreamEventsCannotReadSnapshotEvents() async throws {
        let store = registry()
        defer { store.cleanup() }
        store.registry.approve(recordOnlyClient)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: recordOnlyClient.id)

        await assertThrowsIntegrationError(.unauthorizedClient) {
            _ = try service.snapshotEvents(sessionID: session.id, clientID: recordOnlyClient.id)
        }
    }

    func testSettingsProviderIsReadForEachCreateSession() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        var settings = IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token")
        let service = OpenTypeService(settingsProvider: { settings }, registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)
        try await service.cancel(sessionID: session.id, clientID: clientID)

        settings.developerInterfaceEnabled = false

        await assertThrowsIntegrationError(.developerInterfaceDisabled) {
            try await service.createSession(request(), clientID: clientID)
        }
    }

    private var clientID: String {
        IntegrationClient.localHTTP(tokenID: "token").id
    }

    private var otherClientID: String {
        IntegrationClient.localHTTP(tokenID: "other").id
    }

    private var recordOnlyClient: IntegrationClient {
        IntegrationClient(
            id: "http:record-only",
            displayName: "Record Only",
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: nil,
            transport: .http,
            capabilities: [.record],
            firstApprovedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: nil
        )
    }

    private func makeService(registry: IntegrationClientRegistry) -> OpenTypeService {
        OpenTypeService(
            settings: IntegrationServiceSettings(developerInterfaceEnabled: true, httpToken: "token"),
            registry: registry
        )
    }

    private func request() -> InputSessionRequest {
        InputSessionRequest(mode: .processed, language: .english, useScreenContext: false)
    }

    private func approveLocalHTTP(in registry: IntegrationClientRegistry) {
        registry.approve(IntegrationClient.localHTTP(tokenID: "token"))
    }

    private func approveOtherLocalHTTP(in registry: IntegrationClientRegistry) {
        registry.approve(IntegrationClient.localHTTP(tokenID: "other"))
    }

    private func registry() -> RegistryStore {
        let suiteName = "OpenTypeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RegistryStore(
            registry: IntegrationClientRegistry(defaults: defaults),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func assertThrowsIntegrationError(
        _ expected: IntegrationError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as IntegrationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }
}

private struct RegistryStore {
    let registry: IntegrationClientRegistry
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
