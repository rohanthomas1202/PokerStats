import Foundation
import os

/// Where the session tokens live. The app uses the Keychain; tests use an
/// in-memory fake (unsigned CI has no Keychain entitlement).
protocol TokenStore: Sendable {
    func read(_ key: KeychainHelper.Key) -> String?
    func save(_ value: String, for key: KeychainHelper.Key) throws
    func deleteAll()
}

struct KeychainTokenStore: TokenStore {
    func read(_ key: KeychainHelper.Key) -> String? { KeychainHelper.read(key) }
    func save(_ value: String, for key: KeychainHelper.Key) throws { try KeychainHelper.save(value, for: key) }
    func deleteAll() { KeychainHelper.deleteAll() }
}

extension Notification.Name {
    /// Posted on the main actor, with the `SupabaseClient` as the object, after
    /// a definitive auth failure has cleared the stored tokens.
    static let supabaseSessionInvalidated = Notification.Name("com.rohanthomas.PokerStats.supabaseSessionInvalidated")
}

/// The one place a token refresh is run and its failure is classified.
///
/// - Success: saves the new tokens.
/// - Definitive auth failure (401, or 400 with a refresh-token/session error,
///   or no refresh token stored): clears the stored tokens, calls
///   `onInvalidated` so the UI flips to signed out, throws `.sessionExpired`.
/// - Anything else (offline, timeout, 5xx, ...): leaves the tokens and the
///   signed-in state alone and throws `.refreshUnavailable`; the next request
///   or app launch tries again.
struct SessionRefresher: Sendable {
    let store: any TokenStore
    let refresh: @Sendable (_ refreshToken: String) async throws -> AuthSession
    let onInvalidated: @Sendable () async -> Void

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "SessionRefresher")

    func refreshStoredSession() async throws -> AuthSession {
        guard let refreshToken = store.read(.refreshToken) else {
            Self.logger.error("Token refresh: no refresh token stored; signing out")
            await invalidate()
            throw SupabaseError.sessionExpired
        }

        let session: AuthSession
        do {
            session = try await refresh(refreshToken)
        } catch where Self.isDefinitiveAuthFailure(error) {
            Self.logger.error("Token refresh rejected; signing out: \(error.localizedDescription, privacy: .private)")
            await invalidate()
            throw SupabaseError.sessionExpired
        } catch {
            Self.logger.error("Token refresh failed; keeping session: \(String(describing: type(of: error)), privacy: .public) \(error.localizedDescription, privacy: .private)")
            throw SupabaseError.refreshUnavailable
        }

        try store.save(session.accessToken, for: .accessToken)
        try store.save(session.refreshToken, for: .refreshToken)
        try store.save(session.user.id.uuidString, for: .userId)
        if let email = session.user.email {
            try store.save(email, for: .userEmail)
        }
        return session
    }

    /// Supabase Auth error codes that mean the refresh token or session is gone for good.
    static let definitiveErrorCodes: Set<String> = [
        "invalid_grant",
        "refresh_token_not_found",
        "refresh_token_already_used",
        "session_not_found",
        "session_expired",
        "user_not_found",
        "user_banned",
    ]

    static func isDefinitiveAuthFailure(_ error: Error) -> Bool {
        guard case SupabaseError.httpError(let statusCode, let message) = error else { return false }
        if statusCode == 401 { return true }
        guard statusCode == 400 || statusCode == 403 else { return false }
        return errorCodes(in: message).contains { definitiveErrorCodes.contains($0) }
    }

    /// Reads `error` (older GoTrue) and `error_code` (newer) from the JSON body.
    private static func errorCodes(in message: String) -> [String] {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return ["error", "error_code"].compactMap { json[$0] as? String }
    }

    private func invalidate() async {
        store.deleteAll()
        await onInvalidated()
    }
}
