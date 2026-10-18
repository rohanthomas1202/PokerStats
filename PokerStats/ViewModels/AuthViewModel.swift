import Foundation
import AuthenticationServices

@Observable
@MainActor
final class AuthViewModel {
    var isShowingSignIn = false
    var isProcessing = false
    var errorMessage: String?

    private let authService: AuthService

    /// Performs the account deletion; tests replace it.
    private let performDeleteAccount: @MainActor () async throws -> Void

    init(authService: AuthService, performDeleteAccount: (@MainActor () async throws -> Void)? = nil) {
        self.authService = authService
        self.performDeleteAccount = performDeleteAccount ?? { try await authService.deleteAccount() }
    }

    // MARK: - Apple Sign In

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let authorizationCode = credential.authorizationCode else {
                errorMessage = "Missing Apple credentials."
                return
            }

            isProcessing = true
            errorMessage = nil

            Task {
                do {
                    try await authService.signInWithApple(
                        identityToken: identityToken,
                        authorizationCode: authorizationCode,
                        fullName: credential.fullName,
                        appleUserId: credential.user
                    )
                    isShowingSignIn = false
                } catch {
                    errorMessage = error.localizedDescription
                }
                isProcessing = false
            }

        case .failure(let error):
            // User cancelled is not an error
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign Out

    func signOut() {
        Task {
            await authService.signOut()
        }
    }

    // MARK: - Delete Account

    var isShowingDeleteConfirmation = false
    var isShowingDeleteFinalConfirmation = false

    /// What Settings shows when account deletion fails.
    struct DeleteAccountFailure: Equatable {
        enum Kind: Equatable {
            /// Nothing was disconnected; trying again is safe.
            case retryable
            /// Apple ID was disconnected but server cleanup failed. The user may
            /// be signed out and must sign in with Apple again before retrying.
            case appleDisconnected
        }

        let kind: Kind
        let title: String
        let message: String

        static let retryable = DeleteAccountFailure(
            kind: .retryable,
            title: "Couldn't Delete Account",
            message: "Your account wasn't deleted. Check your connection and try again."
        )
        static let appleDisconnected = DeleteAccountFailure(
            kind: .appleDisconnected,
            title: "Couldn't Finish Deleting Account",
            message: "Your Apple ID was disconnected, but some account data wasn't deleted. Sign in with Apple again, then try again."
        )
    }

    /// True while the deletion request is running; Settings shows a blocking overlay.
    private(set) var isDeletingAccount = false
    /// Set when deletion fails; Settings shows it in an alert with a retry action.
    var deleteAccountFailure: DeleteAccountFailure?
    /// Kept so "Try Again" re-runs the same success handler.
    private var pendingOnDeleted: (@MainActor () -> Void)?

    /// `onDeleted` (wiping local data) runs only after the server confirms the
    /// deletion. On cancel or failure, local data is kept.
    @discardableResult
    func deleteAccount(onDeleted: @escaping @MainActor () -> Void = {}) -> Task<Void, Never> {
        pendingOnDeleted = onDeleted
        isDeletingAccount = true
        deleteAccountFailure = nil

        return Task {
            do {
                try await performDeleteAccount()
                pendingOnDeleted = nil
                onDeleted()
            } catch AccountDeletionError.reauthenticationCancelled {
                // User dismissed the Apple sheet; nothing was deleted.
            } catch AccountDeletionError.cleanupFailedAfterAppleRevoke {
                deleteAccountFailure = .appleDisconnected
            } catch {
                deleteAccountFailure = .retryable
            }
            isDeletingAccount = false
        }
    }

    /// "Try Again" from the failure alert.
    @discardableResult
    func retryDeleteAccount() -> Task<Void, Never> {
        deleteAccount(onDeleted: pendingOnDeleted ?? {})
    }
}
