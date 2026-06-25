import Foundation

struct MarketplaceOrderReference: Codable, Equatable {
    var source: MarketplaceSource
    var orderID: String
    var orderNumber: String
    var importedAt: Date
    var externalStatus: String
    var sourceAccountID: String? = nil
    var sourceAccountName: String? = nil

    var displayTitle: String {
        let trimmedNumber = orderNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNumber.isEmpty ? orderID : trimmedNumber
    }
}

enum MarketplaceSource: String, Codable, CaseIterable, Identifiable {
    case allegro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allegro:
            "Allegro"
        }
    }
}

enum AllegroEnvironment: String, Codable, CaseIterable, Identifiable {
    case production
    case sandbox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .production:
            "Production"
        case .sandbox:
            "Sandbox"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .production:
            URL(string: "https://api.allegro.pl")!
        case .sandbox:
            URL(string: "https://api.allegro.pl.allegrosandbox.pl")!
        }
    }

    var authorizationBaseURL: URL {
        switch self {
        case .production:
            URL(string: "https://allegro.pl/auth/oauth/authorize")!
        case .sandbox:
            URL(string: "https://allegro.pl.allegrosandbox.pl/auth/oauth/authorize")!
        }
    }

    var tokenURL: URL {
        switch self {
        case .production:
            URL(string: "https://allegro.pl/auth/oauth/token")!
        case .sandbox:
            URL(string: "https://allegro.pl.allegrosandbox.pl/auth/oauth/token")!
        }
    }
}

struct AllegroConnectionSettings: Codable, Equatable {
    static let defaultBrokerBaseURL = "https://snapbuy-allegro-broker.onrender.com"

    private static let clientIDKey = "allegroConnection.clientID"
    private static let redirectURIKey = "allegroConnection.redirectURI"
    private static let environmentKey = "allegroConnection.environment"
    private static let connectedAccountNameKey = "allegroConnection.connectedAccountName"
    private static let brokerBaseURLKey = "allegroConnection.brokerBaseURL"

    var clientID: String
    var redirectURI: String
    var environment: AllegroEnvironment
    var connectedAccountName: String
    var brokerBaseURL: String

    var isConfigured: Bool {
        !normalizedBrokerBaseURL.isEmpty ||
        (!clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !redirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var normalizedBrokerBaseURL: String {
        brokerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayStatus: String {
        if !isConfigured {
            return "Not configured"
        }

        let account = connectedAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return account.isEmpty ? "Ready for OAuth" : "Connected: \(account)"
    }

    static func load(userDefaults: UserDefaults = .standard) -> AllegroConnectionSettings {
        let rawEnvironment = userDefaults.string(forKey: environmentKey) ?? AllegroEnvironment.production.rawValue
        return AllegroConnectionSettings(
            clientID: userDefaults.string(forKey: clientIDKey) ?? "",
            redirectURI: userDefaults.string(forKey: redirectURIKey) ?? "",
            environment: AllegroEnvironment(rawValue: rawEnvironment) ?? .production,
            connectedAccountName: userDefaults.string(forKey: connectedAccountNameKey) ?? "",
            brokerBaseURL: userDefaults.string(forKey: brokerBaseURLKey) ?? defaultBrokerBaseURL
        )
    }

    func save(userDefaults: UserDefaults = .standard) {
        userDefaults.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.clientIDKey)
        userDefaults.set(redirectURI.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.redirectURIKey)
        userDefaults.set(environment.rawValue, forKey: Self.environmentKey)
        userDefaults.set(connectedAccountName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.connectedAccountNameKey)
        userDefaults.set(normalizedBrokerBaseURL, forKey: Self.brokerBaseURLKey)
    }

    static func reset(userDefaults: UserDefaults = .standard) -> AllegroConnectionSettings {
        userDefaults.removeObject(forKey: clientIDKey)
        userDefaults.removeObject(forKey: redirectURIKey)
        userDefaults.removeObject(forKey: environmentKey)
        userDefaults.removeObject(forKey: connectedAccountNameKey)
        userDefaults.removeObject(forKey: brokerBaseURLKey)
        return load(userDefaults: userDefaults)
    }
}
