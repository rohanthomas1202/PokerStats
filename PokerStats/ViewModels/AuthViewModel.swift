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

    // MARK: - Google Sign In (placeholder — requires GoogleSignIn SDK)

    func handleGoogleSignIn() {
        // TODO: Integrate GoogleSignIn SDK
        // 1. GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        // 2. On success, get user.idToken.tokenString
        // 3. Call authService.signInWithGoogle(idToken: tokenString)
        errorMessage = "Google Sign-In is not yet configured."
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

    func deleteAccount() {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                try await authService.deleteAccount()
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
