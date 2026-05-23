import Foundation
import XCTest
@testable import OpenType

final class IntegrationAuthTests: XCTestCase {
    func testRegistryStartsEmpty() {
        let registry = registry()

        XCTAssertTrue(registry.approvedClients().isEmpty)
        XCTAssertNil(registry.client(id: "missing"))
        XCTAssertFalse(registry.isAuthorized(clientID: "missing", capability: .record))
    }

    func testApprovingClientPersistsIdentity() throws {
        let registry = registry()
        let client = makeClient(
            id: "cli:test",
            displayName: "Test CLI",
            transport: .cli,
            capabilities: [.record]
        )

        registry.approve(client)

        let persisted = try XCTUnwrap(registry.client(id: "cli:test"))
        XCTAssertEqual(persisted, client)
        XCTAssertEqual(registry.approvedClients(), [client])
    }

    func testAuthorizationRequiresApprovedClientAndCapability() {
        let registry = registry()
        let client = makeClient(
            id: "http:test",
            displayName: "Local HTTP",
            transport: .http,
            capabilities: [.record]
        )

        registry.approve(client)

        XCTAssertTrue(registry.isAuthorized(clientID: client.id, capability: .record))
        XCTAssertFalse(registry.isAuthorized(clientID: client.id, capability: .streamEvents))
        XCTAssertFalse(registry.isAuthorized(clientID: "http:other", capability: .record))
    }

    func testRevokingClientRemovesAccess() {
        let registry = registry()
        let client = makeClient(
            id: "xpc:test",
            displayName: "Helper",
            transport: .xpc,
            capabilities: [.record, .manageClients]
        )
        registry.approve(client)

        registry.revoke(clientID: client.id)

        XCTAssertNil(registry.client(id: client.id))
        XCTAssertTrue(registry.approvedClients().isEmpty)
        XCTAssertFalse(registry.isAuthorized(clientID: client.id, capability: .record))
    }

    private func registry() -> IntegrationClientRegistry {
        let suiteName = "IntegrationAuthTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return IntegrationClientRegistry(defaults: defaults)
    }

    private func makeClient(
        id: String,
        displayName: String,
        transport: IntegrationClient.Transport,
        capabilities: Set<IntegrationClient.Capability>
    ) -> IntegrationClient {
        IntegrationClient(
            id: id,
            displayName: displayName,
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: nil,
            transport: transport,
            capabilities: capabilities,
            firstApprovedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: nil
        )
    }
}
