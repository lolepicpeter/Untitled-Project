import Foundation
import Observation

@MainActor
@Observable
final class ClientStore {
    var clients: [Client] = []

    @ObservationIgnored private let storageKey = "clients"
    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func load() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            clients = []
            return
        }

        clients = (try? JSONDecoder().decode([Client].self, from: data)) ?? []
    }

    func save(_ client: Client) {
        if let index = clients.firstIndex(where: { $0.id == client.id }) {
            clients[index] = client
        } else {
            clients.append(client)
        }

        clients.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        persist()
    }

    func delete(_ client: Client) {
        clients.removeAll { $0.id == client.id }
        persist()
    }

    func replaceAll(_ newClients: [Client]) {
        clients = newClients.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(clients) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
