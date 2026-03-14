import Foundation
import AuthenticationServices

@Observable
@MainActor
final class AuthViewModel {
    var isShowingSignIn = false
    var isProcessing = false
    var errorMessage: String?

    var email = ""
    var password = ""
    var isSignUpMode = false

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

    // MARK: - Email/Password Sign In

    func handleEmailSignIn() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            do {
                if isSignUpMode {
                    try await authService.signUpWithEmail(email: trimmedEmail, password: password)
                } else {
                    try await authService.signInWithEmail(email: trimmedEmail, password: password)
                }
                email = ""
                password = ""
                isShowingSignIn = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    // MARK: - Google Sign In (placeholder — requires GoogleSignIn SDK)

    func handleGoogleSignIn() {
        // TODO: Integrate GoogleSignIn SDK
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
