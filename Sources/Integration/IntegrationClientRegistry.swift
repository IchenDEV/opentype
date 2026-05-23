import Foundation

final class IntegrationClientRegistry {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "integrationApprovedClients") {
        self.defaults = defaults
        self.key = key
    }

    func approvedClients() -> [IntegrationClient] {
        load().sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func client(id: String) -> IntegrationClient? {
        load().first { $0.id == id }
    }

    func approve(_ client: IntegrationClient) {
        var clients = load().filter { $0.id != client.id }
        clients.append(client)
        save(clients)
    }

    func revoke(clientID: String) {
        save(load().filter { $0.id != clientID })
    }

    func markUsed(clientID: String, at date: Date = Date()) {
        var clients = load()
        guard let index = clients.firstIndex(where: { $0.id == clientID }) else {
            return
        }

        clients[index].lastUsedAt = date
        save(clients)
    }

    func isAuthorized(clientID: String, capability: IntegrationClient.Capability) -> Bool {
        guard let client = client(id: clientID) else {
            return false
        }

        return client.capabilities.contains(capability)
    }

    private func load() -> [IntegrationClient] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder.integration.decode([IntegrationClient].self, from: data)) ?? []
    }

    private func save(_ clients: [IntegrationClient]) {
        guard let data = try? JSONEncoder.integration.encode(clients) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
