import Foundation
import os
import Security

/// Small secret storage. Tokens live here and nowhere else (never in UserDefaults or logs).
protocol SecureStore: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data?, for key: String) throws
}

enum SecureStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// Keychain generic passwords, readable after the first unlock and never synced or migrated to
/// another device (a restored backup has to sign in again).
struct KeychainStore: SecureStore {
    var service = "com.braincode.dreamer.session"

    func data(for key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw SecureStoreError.keychain(status)
        }
    }

    func set(_ data: Data?, for key: String) throws {
        let query = baseQuery(key)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStoreError.keychain(status) }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecureStoreError.keychain(status) }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }
}

/// For previews and tests.
final class InMemorySecureStore: SecureStore {
    private let storage = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

    func data(for key: String) throws -> Data? { storage.withLock { $0[key] } }
    func set(_ data: Data?, for key: String) throws { storage.withLock { $0[key] = data } }
}
