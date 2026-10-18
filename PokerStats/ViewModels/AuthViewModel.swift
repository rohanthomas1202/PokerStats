import Foundation
import AuthenticationServices

@Observable
@MainActor
final class AuthViewModel {
    var isShowingSignIn = false
    var isProcessing = false
    var errorMessage: String?

    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
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

    /// `onDeleted` runs only after the server-side deletion succeeded, so local
    /// data isn't wiped when the user cancels Apple re-authentication or the
    /// deletion fails.
    func deleteAccount(onDeleted: @escaping @MainActor () -> Void = {}) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                try await authService.deleteAccount()
                onDeleted()
            } catch AccountDeletionError.reauthenticationCancelled {
                // User dismissed the Apple sheet; nothing was deleted.
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
