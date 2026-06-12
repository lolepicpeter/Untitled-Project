import Foundation
import Security

struct KeychainCredentialStore<Value: Codable> {
    let service: String
    let account: String

    func load() throws -> Value? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialError.unhandledStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainCredentialError.invalidData
        }

        return try JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        var query = baseQuery
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainCredentialError.unhandledStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainCredentialError.unhandledStatus(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        throw KeychainCredentialError.unhandledStatus(status)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainCredentialError: LocalizedError {
    case invalidData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "The saved credential data is invalid."
        case let .unhandledStatus(status):
            "Keychain operation failed with status \(status)."
        }
    }
}
