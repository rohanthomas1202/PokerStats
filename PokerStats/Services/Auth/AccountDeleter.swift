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

    var errorDescription: String? {
        switch self {
        case .reauthenticationCancelled:
            "Account deletion was cancelled."
        }
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
        var code: String?
        if appleUserId() != nil {
            code = try await appleAuthorizationCode()
        }
        try await callDeleteFunction(DeleteAccountRequest(authorizationCode: code))
    }
}
