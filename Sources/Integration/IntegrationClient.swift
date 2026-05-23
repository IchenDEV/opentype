import Foundation

struct IntegrationClient: Codable, Equatable, Identifiable {
    enum Transport: String, Codable, Equatable {
        case http
        case xpc
        case cli
    }

    enum Capability: String, Codable, Equatable, Hashable {
        case record
        case streamEvents
        case provideAudio
        case manageClients
    }

    let id: String
    var displayName: String
    var bundleIdentifier: String?
    var teamIdentifier: String?
    var codeRequirement: String?
    var transport: Transport
    var capabilities: Set<Capability>
    var firstApprovedAt: Date
    var lastUsedAt: Date?

    static func localHTTP(tokenID: String) -> IntegrationClient {
        IntegrationClient(
            id: "http:\(tokenID)",
            displayName: "Local HTTP",
            bundleIdentifier: nil,
            teamIdentifier: nil,
            codeRequirement: nil,
            transport: .http,
            capabilities: [.record, .streamEvents],
            firstApprovedAt: Date(),
            lastUsedAt: nil
        )
    }
}
