import Foundation

struct AllegroBackendConnection: Codable, Equatable {
    var connectionID: String
    var brokerBaseURL: String
    var connectedAt: Date

    var displayName: String {
        "Allegro account"
    }
}

struct AllegroBackendConnectionStore {
    private static let storageKey = "allegroBackendConnection"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AllegroBackendConnection? {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(AllegroBackendConnection.self, from: data)
    }

    func save(_ connection: AllegroBackendConnection) {
        guard let data = try? JSONEncoder().encode(connection) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func delete() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}

struct AllegroBackendConnectionClient {
    let brokerBaseURL: URL
    let urlSession: URLSession

    init?(brokerBaseURL: String, urlSession: URLSession = .shared) {
        let trimmed = brokerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        self.brokerBaseURL = url
        self.urlSession = urlSession
    }

    func startURL() -> URL {
        brokerBaseURL.appending(path: "allegro/oauth/start")
    }

    func disconnect(connectionID: String) async throws {
        var request = URLRequest(url: brokerBaseURL.appending(path: "allegro/connections/\(connectionID)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 || httpResponse.statusCode == 404 else {
            throw AllegroBackendConnectionError.disconnectFailed
        }
    }
}

enum AllegroBackendConnectionError: LocalizedError {
    case invalidBrokerURL
    case missingConnectionID
    case authorizationFailed(String)
    case disconnectFailed

    var errorDescription: String? {
        switch self {
        case .invalidBrokerURL:
            "Add a valid HTTPS Allegro broker URL before connecting."
        case .missingConnectionID:
            "The Allegro broker did not return a connection ID."
        case let .authorizationFailed(error):
            "Allegro connection failed: \(error)"
        case .disconnectFailed:
            "Could not disconnect the Allegro broker connection."
        }
    }
}
