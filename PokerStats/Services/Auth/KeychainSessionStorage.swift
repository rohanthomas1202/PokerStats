import Auth
import Foundation
import Security

/// Keychain storage for the Supabase session (supabase-swift `AuthLocalStorage`).
/// Items are readable after first unlock and are never synced or restored to
/// another device (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), as the
/// app's own token storage was before the SDK.
struct KeychainSessionStorage: AuthLocalStorage {
    enum KeychainError: Error {
        case saveFailed(OSStatus)
        case updateFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
    }

    func store(key: String, value: Data) throws {
        let query = Self.query(key)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = value
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.saveFailed(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.updateFailed(updateStatus)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var query = Self.query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.readFailed(status) }
        return result as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(Self.query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: key]
    }

    /// Items the app's own Supabase client stored before supabase-swift (#82).
    /// Removed on launch so an old refresh token doesn't stay on the device.
    static let legacyKeys = [
        "com.rohanthomas.PokerStats.accessToken",
        "com.rohanthomas.PokerStats.refreshToken",
        "com.rohanthomas.PokerStats.userId",
        "com.rohanthomas.PokerStats.userEmail",
        "com.rohanthomas.PokerStats.appleUserId",
    ]

    func removeLegacyItems() {
        for key in Self.legacyKeys {
            try? remove(key: key)
        }
    }
}
