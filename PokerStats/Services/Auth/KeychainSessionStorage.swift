import Auth
import Foundation
import Security
import os

/// Keychain storage for the Supabase session (supabase-swift `AuthLocalStorage`).
/// Items are readable after first unlock and are never synced or restored to
/// another device (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), as the
/// app's own token storage was before the SDK.
///
/// supabase-swift catches the errors these methods throw and carries on, so
/// each failure is logged here (operation and OSStatus only, never the data).
/// It is not shown to the user, who can't act on a Keychain error: at worst a
/// refreshed session isn't saved, its refresh token is later rejected, and the
/// app signs out and asks them to sign in again.
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
            guard addStatus == errSecSuccess else { throw Self.logged(.saveFailed(addStatus)) }
        } else if updateStatus != errSecSuccess {
            throw Self.logged(.updateFailed(updateStatus))
        }
    }

    func retrieve(key: String) throws -> Data? {
        var query = Self.query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Self.logged(.readFailed(status)) }
        return result as? Data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(Self.query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Self.logged(.deleteFailed(status))
        }
    }

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "KeychainSessionStorage")

    private static func logged(_ error: KeychainError) -> KeychainError {
        logger.error("Keychain session storage failed: \(String(describing: error), privacy: .public)")
        return error
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
