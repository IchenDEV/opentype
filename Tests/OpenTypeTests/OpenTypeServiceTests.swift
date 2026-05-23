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

        XCTAssertEqual(service.session(session.id), session)
        let events = service.snapshotEvents(sessionID: session.id)
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
        try await service.startRecording(sessionID: first.id)

        await assertThrowsIntegrationError(.busy) {
            try await service.createSession(request(), clientID: clientID)
        }
        XCTAssertEqual(service.session(first.id)?.state, .recording)
    }

    func testCancelSessionTransitionsToTerminalState() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await service.cancel(sessionID: session.id)

        XCTAssertEqual(service.session(session.id)?.state, .cancelled)
        let events = service.snapshotEvents(sessionID: session.id)
        XCTAssertEqual(events.map(\.type), [.sessionCreated, .sessionCancelled])
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testStartRecordingIncrementsEventSequence() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        try await service.startRecording(sessionID: session.id)

        XCTAssertEqual(service.session(session.id)?.state, .recording)
        let events = service.snapshotEvents(sessionID: session.id)
        XCTAssertEqual(events.map(\.type), [.sessionCreated, .recordingStarted])
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testCancelNoOpsForMissingAndTerminalSessions() async throws {
        let store = registry()
        defer { store.cleanup() }
        approveLocalHTTP(in: store.registry)
        let service = makeService(registry: store.registry)
        let session = try await service.createSession(request(), clientID: clientID)

        await service.cancel(sessionID: UUID())
        await service.cancel(sessionID: session.id)
        await service.cancel(sessionID: session.id)

        XCTAssertEqual(service.session(session.id)?.state, .cancelled)
        XCTAssertEqual(service.snapshotEvents(sessionID: session.id).map(\.type), [.sessionCreated, .sessionCancelled])
    }

    private var clientID: String {
        IntegrationClient.localHTTP(tokenID: "token").id
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
