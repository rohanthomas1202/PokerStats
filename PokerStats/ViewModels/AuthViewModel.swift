import Foundation
import AuthenticationServices
import os

@Observable
@MainActor
final class AuthViewModel {
    var isShowingSignIn = false
    var isProcessing = false
    var errorMessage: String?

    private let authService: AuthService

    /// Performs the account deletion; tests replace it.
    private let performDeleteAccount: @MainActor () async throws -> Void

    /// Performs the Supabase sign-in with Apple's credential; tests replace it.
    private let performAppleSignIn: @MainActor (AppleSignInCredential) async throws -> Void

    init(
        authService: AuthService,
        performDeleteAccount: (@MainActor () async throws -> Void)? = nil,
        performAppleSignIn: (@MainActor (AppleSignInCredential) async throws -> Void)? = nil
    ) {
        self.authService = authService
        self.performDeleteAccount = performDeleteAccount ?? { try await authService.deleteAccount() }
        self.performAppleSignIn = performAppleSignIn ?? { credential in
            try await authService.signInWithApple(
                identityToken: credential.identityToken,
                rawNonce: credential.rawNonce
            )
        }
    }

    // MARK: - Apple Sign In

    struct AppleSignInCredential: Sendable {
        let identityToken: Data
        let authorizationCode: Data
        let fullName: PersonNameComponents?
        let appleUserId: String
        /// Raw nonce whose SHA-256 went to Apple in the request.
        let rawNonce: String
    }

    /// Shown when Apple or Supabase rejects the sign-in. Details go to the log only.
    static let signInFailedMessage = "Couldn't sign in with Apple. Please try again."
    /// Shown when Apple's response is incomplete or no attempt is in progress.
    static let signInIncompleteMessage = "Sign-in didn't finish. Please try again."

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AuthViewModel")

    /// Nonce for the sign-in attempt in progress. Memory only, used once.
    @ObservationIgnored private var pendingNonce: SignInNonce?

    /// SignInWithAppleButton's request closure; runs once per attempt.
    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email, .fullName]
        request.nonce = startAppleSignInAttempt()
    }

    /// Makes a fresh nonce for this attempt and returns the hash Apple gets.
    func startAppleSignInAttempt() -> String {
        let nonce = SignInNonce()
        pendingNonce = nonce
        errorMessage = nil // a repeat failure then re-announces for VoiceOver
        return nonce.hashed
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let authorizationCode = credential.authorizationCode else {
                pendingNonce = nil
                Self.logger.error("Apple sign-in returned no identity token or authorization code")
                errorMessage = Self.signInIncompleteMessage
                return
            }
            completeAppleSignIn(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: credential.fullName,
                appleUserId: credential.user
            )

        case .failure(let error):
            pendingNonce = nil
            // User cancelled is not an error
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            Self.logSignInFailure(error, step: "apple")
            errorMessage = Self.signInFailedMessage
        }
    }

    /// Sends Apple's credential to Supabase with this attempt's raw nonce,
    /// then forgets the nonce. Returns nil if no attempt was started.
    @discardableResult
    func completeAppleSignIn(
        identityToken: Data,
        authorizationCode: Data,
        fullName: PersonNameComponents?,
        appleUserId: String
    ) -> Task<Void, Never>? {
        guard let nonce = pendingNonce else {
            errorMessage = Self.signInIncompleteMessage
            return nil
        }
        pendingNonce = nil

        let credential = AppleSignInCredential(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName,
            appleUserId: appleUserId,
            rawNonce: nonce.raw
        )
        isProcessing = true
        errorMessage = nil

        return Task {
            do {
                try await performAppleSignIn(credential)
                isShowingSignIn = false
            } catch {
                Self.logSignInFailure(error, step: "supabase")
                errorMessage = Self.signInFailedMessage
            }
            isProcessing = false
        }
    }

    /// Logs the error kind and status publicly; the server's message stays
    /// private. Never logs the credential, tokens, or nonce.
    private static func logSignInFailure(_ error: Error, step: StaticString) {
        let stepName = "\(step)"
        switch error {
        case SupabaseError.httpError(let statusCode, let message):
            logger.error("Sign in with Apple failed at \(stepName, privacy: .public): HTTP \(statusCode, privacy: .public) \(message, privacy: .private)")
        default:
            let kind = String(describing: type(of: error))
            logger.error("Sign in with Apple failed at \(stepName, privacy: .public): \(kind, privacy: .public) \(error.localizedDescription, privacy: .private)")
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
            /// Trying again now can't help; the alert has only OK, no Try Again.
            case notRetryable
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
        static let appleAccountMismatch = DeleteAccountFailure(
            kind: .notRetryable,
            title: "Couldn't Delete Account",
            message: "The Apple ID on this device doesn't match your account. Your account wasn't deleted. To delete it, use a device signed in with the Apple ID you used for PokerStats."
        )
        /// The address is a placeholder until the owner picks one (#76).
        static let needsSupport = DeleteAccountFailure(
            kind: .notRetryable,
            title: "Couldn't Delete Account",
            message: "Your account couldn't be deleted. Contact support at [CONTACT_EMAIL]."
        )
        /// The server isn't ready (503), so an immediate retry would fail again.
        /// Only OK is shown, matching "Try again later."
        static let temporarilyUnavailable = DeleteAccountFailure(
            kind: .notRetryable,
            title: "Couldn't Delete Account",
            message: "Account deletion is temporarily unavailable. Your account wasn't deleted. Try again later."
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
            } catch AccountDeletionError.appleAccountMismatch {
                deleteAccountFailure = .appleAccountMismatch
            } catch AccountDeletionError.needsSupport {
                deleteAccountFailure = .needsSupport
            } catch AccountDeletionError.temporarilyUnavailable {
                deleteAccountFailure = .temporarilyUnavailable
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
