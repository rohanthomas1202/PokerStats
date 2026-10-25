import Foundation

/// Body sent to the `delete-account` edge function.
struct DeleteAccountRequest: Encodable, Sendable, Equatable {
    /// Fresh Sign in with Apple authorization code. The function exchanges it
    /// and revokes the Apple token (App Review 5.1.1(v)). Codes are single-use
    /// and short-lived, so one is requested right before each deletion.
    let authorizationCode: String?
}

enum AccountDeletionError: LocalizedError, Equatable {
    /// The user dismissed the Apple re-authentication sheet.
    case reauthenticationCancelled
    /// The server revoked the Apple token, then a later cleanup step failed.
    /// Apple signs the user out, but their account data is still on the server.
    case cleanupFailedAfterAppleRevoke
    /// 422 `apple_account_mismatch`: the Apple ID on this device isn't the one
    /// this account signed in with. Nothing was deleted.
    case appleAccountMismatch
    /// 422 `apple_identity_missing` or `apple_token_invalid`, or any other
    /// `retryable: false` failure. Retrying can't help. Nothing was deleted.
    case needsSupport
    /// 503 `server_not_configured`. Nothing was deleted; try again later.
    case temporarilyUnavailable

    var errorDescription: String? {
        switch self {
        case .reauthenticationCancelled:
            "Account deletion was cancelled."
        case .cleanupFailedAfterAppleRevoke:
            "Apple ID disconnected, but account data wasn't fully deleted."
        case .appleAccountMismatch:
            "This Apple ID doesn't match your account."
        case .needsSupport:
            "Your account couldn't be deleted."
        case .temporarilyUnavailable:
            "Account deletion is temporarily unavailable."
        }
    }
}

/// The `delete-account` failure body: `{ error, code, retryable, step, apple_revoked? }`.
/// Each field is decoded on its own, so one field with an unexpected type
/// leaves that field nil instead of dropping the rest (notably `apple_revoked`).
struct DeleteAccountFailureBody: Decodable {
    let code: String?
    let retryable: Bool?
    let appleRevoked: Bool?

    private enum CodingKeys: String, CodingKey {
        case code, retryable, appleRevoked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        retryable = try? container.decodeIfPresent(Bool.self, forKey: .retryable)
        appleRevoked = try? container.decodeIfPresent(Bool.self, forKey: .appleRevoked)
    }

    /// The body of a `delete-account` non-2xx response, or nil for any other error.
    static func from(_ error: Error) -> (status: Int, body: DeleteAccountFailureBody?)? {
        guard case SupabaseError.httpError(let status, let message) = error else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (status, try? decoder.decode(Self.self, from: Data(message.utf8)))
    }
}

/// Server-side part of account deletion, with its dependencies injected so it
/// can be tested without the Keychain, Apple UI, or network.
@MainActor
struct AccountDeleter {
    /// The stored Apple user ID, if this account signed in with Apple.
    let appleUserId: @MainActor () -> String?
    /// Shows the Sign in with Apple sheet and returns a fresh authorization code.
    let appleAuthorizationCode: @MainActor () async throws -> String
    /// POSTs to the `delete-account` edge function; throws on a non-2xx response.
    let callDeleteFunction: @MainActor (DeleteAccountRequest) async throws -> Void

    func run() async throws {
        do {
            try await send()
        } catch {
            throw Self.mapped(error)
        }
    }

    private func send() async throws {
        // Signed in with Apple on this device: confirm with Apple up front.
        if appleUserId() != nil {
            try await sendWithFreshAppleCode()
            return
        }
        // Otherwise the server decides from the Supabase identities. If the
        // account has an Apple identity anyway (e.g. linked by email), it asks
        // for a code; confirm with Apple and retry once.
        do {
            try await callDeleteFunction(DeleteAccountRequest(authorizationCode: nil))
        } catch let error where Self.isAppleReauthRequired(error) {
            try await sendWithFreshAppleCode()
        }
    }

    private func sendWithFreshAppleCode() async throws {
        let code = try await appleAuthorizationCode()
        try await callDeleteFunction(DeleteAccountRequest(authorizationCode: code))
    }

    /// Maps a `delete-account` failure to an `AccountDeletionError` by `code`,
    /// then by `retryable`. Anything left (`delete_failed`, a second
    /// `apple_reauth_required`, a retryable or unreadable body, a network
    /// error) is returned unchanged and shown as the generic retryable error.
    static func mapped(_ error: Error) -> Error {
        guard let body = DeleteAccountFailureBody.from(error)?.body else { return error }
        if body.appleRevoked == true { return AccountDeletionError.cleanupFailedAfterAppleRevoke }
        switch body.code {
        case "apple_account_mismatch":
            return AccountDeletionError.appleAccountMismatch
        case "apple_identity_missing", "apple_token_invalid":
            return AccountDeletionError.needsSupport
        case "server_not_configured":
            return AccountDeletionError.temporarilyUnavailable
        case "apple_reauth_required", "delete_failed":
            return error
        default:
            return body.retryable == false ? AccountDeletionError.needsSupport : error
        }
    }

    /// The `delete-account` 400 that means "send a fresh Apple authorization code".
    static func isAppleReauthRequired(_ error: Error) -> Bool {
        guard let failure = DeleteAccountFailureBody.from(error) else { return false }
        return failure.status == 400 && failure.body?.code == "apple_reauth_required"
    }
}
