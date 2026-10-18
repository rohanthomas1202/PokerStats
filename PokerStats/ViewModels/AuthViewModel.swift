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
    /// Set when account deletion fails; Settings shows it in an alert.
    /// Separate from `errorMessage`, which the sign-in sheet shows.
    var deleteAccountErrorMessage: String?

    /// `onDeleted` runs only after the server-side deletion succeeded, so local
    /// data isn't wiped when the user cancels Apple re-authentication or the
    /// deletion fails.
    @discardableResult
    func deleteAccount(onDeleted: @escaping @MainActor () -> Void = {}) -> Task<Void, Never> {
        isProcessing = true
        deleteAccountErrorMessage = nil

        return Task {
            do {
                try await performDeleteAccount()
                onDeleted()
            } catch AccountDeletionError.reauthenticationCancelled {
                // User dismissed the Apple sheet; nothing was deleted.
            } catch {
                deleteAccountErrorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
