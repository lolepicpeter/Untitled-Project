import Foundation

struct AllegroBackendConnection: Codable, Equatable, Identifiable {
    var connectionID: String
    var brokerBaseURL: String
    var connectedAt: Date
    var accountID: String? = nil
    var login: String? = nil
    var accountDisplayName: String? = nil
    var companyName: String? = nil
    var companyTaxID: String? = nil

    var id: String { connectionID }

    var displayName: String {
        [accountDisplayName, login]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Allegro account"
    }

    var shopName: String {
        login?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? displayName
    }

    var legalSellerName: String {
        companyName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Seller details unavailable"
    }

    func enriched(with account: AllegroBackendAccount) -> AllegroBackendConnection {
        var connection = self
        connection.accountID = account.id
        connection.login = account.login
        connection.accountDisplayName = account.displayName
        connection.companyName = account.companyName
        connection.companyTaxID = account.companyTaxID
        return connection
    }
}

struct AllegroBackendConnectionStore {
    private static let storageKey = "allegroBackendConnection"
    private static let storageListKey = "allegroBackendConnections"
    private static let activeConnectionIDKey = "allegroBackendConnection.activeID"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AllegroBackendConnection? {
        if let activeID = userDefaults.string(forKey: Self.activeConnectionIDKey),
           let connection = loadAll().first(where: { $0.connectionID == activeID }) {
            return connection
        }
        return loadAll().first
    }

    func loadAll() -> [AllegroBackendConnection] {
        let decoder = JSONDecoder()
        if let data = userDefaults.data(forKey: Self.storageListKey),
           let connections = try? decoder.decode([AllegroBackendConnection].self, from: data) {
            return connections.sorted { $0.connectedAt > $1.connectedAt }
        }

        guard let data = userDefaults.data(forKey: Self.storageKey),
              let connection = try? decoder.decode(AllegroBackendConnection.self, from: data) else {
            return []
        }
        saveAll([connection])
        userDefaults.set(connection.connectionID, forKey: Self.activeConnectionIDKey)
        return [connection]
    }

    func save(_ connection: AllegroBackendConnection) {
        var connections = loadAll().filter { existing in
            guard existing.connectionID != connection.connectionID else { return false }
            if let accountID = connection.accountID, !accountID.isEmpty {
                return existing.accountID != accountID
            }
            return true
        }
        connections.insert(connection, at: 0)
        saveAll(connections)
        userDefaults.set(connection.connectionID, forKey: Self.activeConnectionIDKey)
        guard let data = try? JSONEncoder().encode(connection) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func saveAll(_ connections: [AllegroBackendConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        userDefaults.set(data, forKey: Self.storageListKey)
    }

    func activate(_ connection: AllegroBackendConnection) {
        userDefaults.set(connection.connectionID, forKey: Self.activeConnectionIDKey)
        guard let data = try? JSONEncoder().encode(connection) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    func delete(_ connection: AllegroBackendConnection) {
        let remaining = loadAll().filter { $0.connectionID != connection.connectionID }
        saveAll(remaining)
        if userDefaults.string(forKey: Self.activeConnectionIDKey) == connection.connectionID {
            if let next = remaining.first {
                activate(next)
            } else {
                userDefaults.removeObject(forKey: Self.activeConnectionIDKey)
                userDefaults.removeObject(forKey: Self.storageKey)
            }
        }
    }

    func delete() {
        userDefaults.removeObject(forKey: Self.storageKey)
        userDefaults.removeObject(forKey: Self.storageListKey)
        userDefaults.removeObject(forKey: Self.activeConnectionIDKey)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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

    func account(connectionID: String) async throws -> AllegroBackendAccount {
        let url = brokerBaseURL.appending(path: "allegro/connections/\(connectionID)/account")
        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AllegroBackendConnectionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let brokerError = try? JSONDecoder().decode(AllegroBackendErrorResponse.self, from: data)
            throw AllegroBackendConnectionError.requestFailed(message: brokerError?.error.message)
        }

        do {
            return try JSONDecoder().decode(AllegroBackendAccountResponse.self, from: data).account
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
    var totalAvailable: Int?
    var filterMode: String?
}

struct AllegroBackendAccount: Decodable, Equatable {
    var id: String?
    var login: String?
    var email: String?
    var firstName: String?
    var lastName: String?
    var company: AllegroBackendAccountCompany?

    var companyName: String? {
        company?.name
    }

    var companyTaxID: String? {
        company?.taxId
    }

    var displayName: String {
        let personName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let candidates: [String?] = [companyName, login, personName, email]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Allegro account"
    }
}

struct AllegroBackendAccountCompany: Decodable, Equatable {
    var name: String?
    var taxId: String?
}

private struct AllegroBackendOrdersResponse: Decodable {
    let orders: [AllegroCheckoutForm]
    let meta: AllegroBackendOrdersMeta?
}

private struct AllegroBackendAccountResponse: Decodable {
    let account: AllegroBackendAccount
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
