import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct AllegroOAuthToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var scope: String
    var expiresAt: Date
    var savedAt: Date

    var isExpired: Bool {
        expiresAt <= Date()
    }
}

struct AllegroOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: TimeInterval
    let scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }

    func storedToken(savedAt: Date = Date()) -> AllegroOAuthToken {
        AllegroOAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken ?? "",
            tokenType: tokenType,
            scope: scope ?? "",
            expiresAt: savedAt.addingTimeInterval(expiresIn),
            savedAt: savedAt
        )
    }
}

enum AllegroOAuthConfiguration {
    static let defaultRedirectURI = ""
    static let defaultScopes = [
        "allegro:api:orders:read",
        "allegro:api:profile:read"
    ]
}

struct AllegroOAuthTokenStore {
    private let keychain = KeychainCredentialStore<AllegroOAuthToken>(
        service: "InvoiceFlow.AllegroOAuth",
        account: "current"
    )

    func load() throws -> AllegroOAuthToken? {
        try keychain.load()
    }

    func save(_ token: AllegroOAuthToken) throws {
        try keychain.save(token)
    }

    func delete() throws {
        try keychain.delete()
    }
}

@MainActor
@Observable
final class AllegroOAuthConnector: NSObject {
    var settings: AllegroConnectionSettings
    var token: AllegroOAuthToken?
    var backendConnection: AllegroBackendConnection?
    var backendConnections: [AllegroBackendConnection] = []
    var backendAccount: AllegroBackendAccount?
    var statusMessage: StatusMessage?
    var isConnecting = false

    @ObservationIgnored private let tokenStore = AllegroOAuthTokenStore()
    @ObservationIgnored private let backendConnectionStore = AllegroBackendConnectionStore()
    @ObservationIgnored private var webAuthenticationSession: ASWebAuthenticationSession?
    @ObservationIgnored private var usesEphemeralWebAuthenticationSession = false

    override init() {
        settings = AllegroConnectionSettings.load()
        token = try? tokenStore.load()
        backendConnections = backendConnectionStore.loadAll()
        backendConnection = backendConnectionStore.load()
        super.init()
        if isConnected, settings.connectedAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.connectedAccountName = "Allegro account"
            settings.save()
        }
    }

    var isConnected: Bool {
        token != nil || backendConnection != nil
    }

    var connectionStatus: String {
        if let backendConnection {
            let connectedAt = backendConnection.connectedAt.formatted(date: .abbreviated, time: .shortened)
            return "Connected through broker since \(connectedAt)"
        }
        if let token {
            let expiry = token.expiresAt.formatted(date: .abbreviated, time: .shortened)
            return "Connected until \(expiry)"
        }
        return settings.displayStatus
    }

    func reload() {
        settings = AllegroConnectionSettings.load()
        token = try? tokenStore.load()
        backendConnections = backendConnectionStore.loadAll()
        backendConnection = backendConnectionStore.load()
    }

    func saveSettings(_ newSettings: AllegroConnectionSettings) {
        settings = newSettings
        settings.save()
    }

    func refreshBackendAccount() async {
        guard let backendConnection else {
            backendAccount = nil
            return
        }
        await refreshBackendAccount(for: backendConnection)
    }

    func refreshBackendAccount(for connection: AllegroBackendConnection) async {
        guard let client = AllegroBackendConnectionClient(brokerBaseURL: connection.brokerBaseURL) else {
            backendAccount = nil
            return
        }

        do {
            let account = try await client.account(connectionID: connection.connectionID)
            let enrichedConnection = connection.enriched(with: account)
            backendConnectionStore.save(enrichedConnection)
            backendConnections = backendConnectionStore.loadAll()
            if backendConnection?.connectionID == connection.connectionID {
                backendConnection = enrichedConnection
                backendAccount = account
                settings.connectedAccountName = account.displayName
                settings.save()
            }
        } catch {
            statusMessage = StatusMessage(error: error)
        }
    }

    func connect() async {
        guard settings.isConfigured else {
            statusMessage = StatusMessage(text: "Add Allegro client ID and redirect URI first.", systemImage: "exclamationmark.triangle", color: .orange)
            return
        }

        isConnecting = true
        statusMessage = nil
        defer { isConnecting = false }

        do {
            if !settings.normalizedBrokerBaseURL.isEmpty {
                try await connectThroughBroker()
                return
            }

            let pkce = try AllegroPKCEChallenge()
            let state = UUID().uuidString
            let client = AllegroClient(environment: settings.environment)
            let authorizationURL = try client.authorizationURL(
                clientID: settings.clientID,
                redirectURI: settings.redirectURI,
                state: state,
                scopes: AllegroOAuthConfiguration.defaultScopes,
                codeChallenge: pkce.challenge,
                codeChallengeMethod: "S256"
            )

            let callbackURL = try await authenticate(authorizationURL: authorizationURL, redirectURI: settings.redirectURI)
            let code = try authorizationCode(from: callbackURL, expectedState: state)
            let response = try await client.exchangeAuthorizationCode(
                code: code,
                clientID: settings.clientID,
                redirectURI: settings.redirectURI,
                codeVerifier: pkce.verifier
            )
            let storedToken = response.storedToken()
            try tokenStore.save(storedToken)
            token = storedToken

            settings.connectedAccountName = "Allegro account"
            settings.save()
            statusMessage = StatusMessage(text: "Allegro connected.", systemImage: "checkmark.circle", color: .green)
        } catch {
            statusMessage = StatusMessage(error: error)
        }
    }

    func connectAnotherShop() async {
        let previousEphemeralSetting = usesEphemeralWebAuthenticationSession
        usesEphemeralWebAuthenticationSession = true
        defer { usesEphemeralWebAuthenticationSession = previousEphemeralSetting }

        await connect()
        await refreshBackendAccount()
    }

    func switchAccount() async {
        let previousEphemeralSetting = usesEphemeralWebAuthenticationSession
        usesEphemeralWebAuthenticationSession = true
        defer { usesEphemeralWebAuthenticationSession = previousEphemeralSetting }

        if let backendConnection {
            await disconnect(connection: backendConnection)
        } else {
            await disconnectAsync()
        }
        await connect()
        await refreshBackendAccount()
    }

    func disconnect() {
        Task { await disconnectAsync() }
    }

    func disconnectAsync() async {
        guard let backendConnection else {
            backendConnectionStore.delete()
            backendConnections = []
            backendAccount = nil
            try? tokenStore.delete()
            token = nil
            settings.connectedAccountName = ""
            settings.save()
            statusMessage = StatusMessage(text: "Allegro disconnected.", systemImage: "xmark.circle", color: .secondary)
            return
        }
        await disconnect(connection: backendConnection)
    }

    func disconnectAllConnections() async {
        for connection in backendConnectionStore.loadAll() {
            if let client = AllegroBackendConnectionClient(brokerBaseURL: connection.brokerBaseURL) {
                try? await client.disconnect(connectionID: connection.connectionID)
            }
        }
        backendConnectionStore.delete()
        backendConnections = []
        backendConnection = nil
        backendAccount = nil
        try? tokenStore.delete()
        token = nil
        settings.connectedAccountName = ""
        settings.save()
        statusMessage = StatusMessage(text: "Allegro disconnected.", systemImage: "xmark.circle", color: .secondary)
    }

    func disconnect(connection: AllegroBackendConnection) async {
        do {
            if let client = AllegroBackendConnectionClient(brokerBaseURL: connection.brokerBaseURL) {
                try await client.disconnect(connectionID: connection.connectionID)
            }
            backendConnectionStore.delete(connection)
            backendConnections = backendConnectionStore.loadAll()
            backendConnection = backendConnectionStore.load()
            if backendConnection == nil {
                try? tokenStore.delete()
                token = nil
                backendAccount = nil
                settings.connectedAccountName = ""
            } else {
                backendAccount = nil
                settings.connectedAccountName = backendConnection?.displayName ?? ""
            }
            settings.save()
            statusMessage = StatusMessage(text: "Allegro disconnected.", systemImage: "xmark.circle", color: .secondary)
        } catch {
            statusMessage = StatusMessage(error: error)
        }
    }

    func activate(connection: AllegroBackendConnection) {
        backendConnectionStore.activate(connection)
        backendConnection = connection
        backendConnections = backendConnectionStore.loadAll()
        backendAccount = nil
        settings.connectedAccountName = connection.displayName
        settings.save()
    }

    private func connectThroughBroker() async throws {
        guard let client = AllegroBackendConnectionClient(brokerBaseURL: settings.normalizedBrokerBaseURL) else {
            throw AllegroBackendConnectionError.invalidBrokerURL
        }

        let callbackURL = try await authenticate(authorizationURL: client.startURL(), redirectURI: "invoiceflow://allegro/connected")
        let connectionID = try backendConnectionID(from: callbackURL)
        let connection = AllegroBackendConnection(
            connectionID: connectionID,
            brokerBaseURL: settings.normalizedBrokerBaseURL,
            connectedAt: Date()
        )
        backendConnectionStore.save(connection)
        backendConnection = connection
        settings.connectedAccountName = connection.displayName
        settings.save()
        await refreshBackendAccount()
        statusMessage = StatusMessage(text: "Allegro connected through broker.", systemImage: "checkmark.circle", color: .green)
    }

    private func backendConnectionID(from callbackURL: URL) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AllegroBackendConnectionError.missingConnectionID
        }
        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            throw AllegroBackendConnectionError.authorizationFailed(error)
        }
        guard let connectionID = queryItems.first(where: { $0.name == "connection_id" })?.value, !connectionID.isEmpty else {
            throw AllegroBackendConnectionError.missingConnectionID
        }
        return connectionID
    }

    private func authenticate(authorizationURL: URL, redirectURI: String) async throws -> URL {
        guard let callbackScheme = URLComponents(string: redirectURI)?.scheme, !callbackScheme.isEmpty else {
            throw AllegroOAuthError.invalidRedirectURI
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorizationURL, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AllegroOAuthError.missingCallbackURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = usesEphemeralWebAuthenticationSession
            webAuthenticationSession = session

            if !session.start() {
                continuation.resume(throwing: AllegroOAuthError.couldNotStartSession)
            }
        }
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AllegroOAuthError.missingAuthorizationCode
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            throw AllegroOAuthError.authorizationFailed(error)
        }

        let state = queryItems.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw AllegroOAuthError.stateMismatch
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AllegroOAuthError.missingAuthorizationCode
        }
        return code
    }
}

extension AllegroOAuthConnector: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #endif
    }
}

struct AllegroPKCEChallenge {
    let verifier: String
    let challenge: String

    init() throws {
        verifier = try Self.randomVerifier()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        challenge = Data(digest).base64URLEncodedString()
    }

    private static func randomVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw AllegroOAuthError.couldNotGenerateVerifier
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AllegroOAuthError: LocalizedError {
    case invalidRedirectURI
    case couldNotStartSession
    case couldNotGenerateVerifier
    case missingCallbackURL
    case missingAuthorizationCode
    case stateMismatch
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRedirectURI:
            "The Allegro redirect URI must include a URL scheme."
        case .couldNotStartSession:
            "Could not open the Allegro login page."
        case .couldNotGenerateVerifier:
            "Could not create a secure OAuth verifier."
        case .missingCallbackURL:
            "Allegro did not return a callback URL."
        case .missingAuthorizationCode:
            "Allegro did not return an authorization code."
        case .stateMismatch:
            "Allegro authorization returned with an invalid state value."
        case let .authorizationFailed(error):
            "Allegro authorization failed: \(error)"
        }
    }
}
