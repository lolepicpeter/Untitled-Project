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

    func orders(connectionID: String, days: Int = 30, limit: Int = 500) async throws -> AllegroBackendOrdersResult {
        var components = URLComponents(url: brokerBaseURL.appending(path: "allegro/connections/\(connectionID)/orders"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "days", value: "\(min(max(days, 1), 365))"),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 1000))")
        ]

        guard let url = components?.url else {
            throw AllegroBackendConnectionError.invalidBrokerURL
        }

        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AllegroBackendConnectionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let brokerError = try? JSONDecoder().decode(AllegroBackendErrorResponse.self, from: data)
            throw AllegroBackendConnectionError.requestFailed(message: brokerError?.error.message)
        }

        do {
            let response = try JSONDecoder().decode(AllegroBackendOrdersResponse.self, from: data)
            return AllegroBackendOrdersResult(orders: response.orders, meta: response.meta)
        } catch {
            throw AllegroBackendConnectionError.decodingFailed(Self.describeDecodingError(error, data: data))
        }
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

    private static func describeDecodingError(_ error: Error, data: Data) -> String {
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<non-UTF8 response>"

        if let decodingError = error as? DecodingError {
            return "\(decodingError.debugDescription) Response starts with: \(preview)"
        }

        return "\(error.localizedDescription) Response starts with: \(preview)"
    }
}

struct AllegroBackendOrdersResult: Equatable {
    var orders: [AllegroCheckoutForm]
    var meta: AllegroBackendOrdersMeta?
}

struct AllegroBackendOrdersMeta: Decodable, Equatable {
    var from: String?
    var to: String?
    var limit: Int?
    var fetched: Int?
    var filterMode: String?
}

private struct AllegroBackendOrdersResponse: Decodable {
    let orders: [AllegroCheckoutForm]
    let meta: AllegroBackendOrdersMeta?
}

private struct AllegroBackendErrorResponse: Decodable {
    let error: AllegroBackendErrorBody
}

private struct AllegroBackendErrorBody: Decodable {
    let message: String
}

enum AllegroBackendConnectionError: LocalizedError {
    case invalidBrokerURL
    case missingConnectionID
    case authorizationFailed(String)
    case invalidResponse
    case requestFailed(message: String?)
    case decodingFailed(String)
    case disconnectFailed

    var errorDescription: String? {
        switch self {
        case .invalidBrokerURL:
            return "Add a valid HTTPS Allegro broker URL before connecting."
        case .missingConnectionID:
            return "The Allegro broker did not return a connection ID."
        case let .authorizationFailed(error):
            return "Allegro connection failed: \(error)"
        case .invalidResponse:
            return "The Allegro broker returned an invalid response."
        case let .requestFailed(message):
            if message == "Connection not found." {
                return "Allegro needs to be reconnected."
            }
            return message ?? "The Allegro broker request failed."
        case let .decodingFailed(reason):
            return "Could not read the Allegro broker response: \(reason)"
        case .disconnectFailed:
            return "Could not disconnect the Allegro broker connection."
        }
    }
}
