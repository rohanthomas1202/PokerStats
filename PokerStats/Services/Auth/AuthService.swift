import Foundation
import AuthenticationServices
import SwiftData
import os

@Observable
@MainActor
final class AuthService {
    // MARK: - State

    private(set) var isAuthenticated: Bool = false
    private(set) var userEmail: String?
    private(set) var userId: UUID?
    private(set) var isLoading: Bool = false
    private(set) var error: AuthServiceError?

    var displayEmail: String { userEmail ?? "Unknown" }

    private let client: SupabaseClient
    private var tokenStore: any TokenStore { client.tokenStore }
    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AuthService")
    @ObservationIgnored nonisolated(unsafe) private var invalidationObserver: (any NSObjectProtocol)?

    init(client: SupabaseClient = .shared) {
        self.client = client
        // A definitive refresh failure has already cleared the tokens; flip
        // the UI to match. Posted on the main actor, so this runs inline.
        invalidationObserver = NotificationCenter.default.addObserver(
            forName: .supabaseSessionInvalidated,
            object: client,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearSignedInState() }
        }
    }

    deinit {
        if let invalidationObserver {
            NotificationCenter.default.removeObserver(invalidationObserver)
        }
    }

    // MARK: - Initialization

    func initialize() {
        if restoreSession() {
            Task { await silentRefresh() }
        }

        // Check Apple credential state if applicable
        checkAppleCredentialState()

        // Register for Apple credential revocation
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.signOut()
            }
        }
    }

    /// Signed-in state comes from the stored tokens. Returns true when the
    /// stored access token has expired and needs `silentRefresh()`.
    @discardableResult
    func restoreSession() -> Bool {
        guard let tokenString = tokenStore.read(.accessToken),
              let userIdString = tokenStore.read(.userId),
              let id = UUID(uuidString: userIdString) else {
            return false
        }
        isAuthenticated = true
        userId = id
        userEmail = tokenStore.read(.userEmail)
        return isTokenExpired(tokenString)
    }

    // MARK: - Sign In with Apple

    func signInWithApple(
        identityToken: Data,
        authorizationCode: Data,
        fullName: PersonNameComponents?,
        appleUserId: String,
        rawNonce: String
    ) async throws {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthServiceError.appleSignInFailed("Invalid identity token")
        }

        isLoading = true
        error = nil

        do {
            let session = try await client.signInWithIdToken(
                provider: .apple,
                idToken: tokenString,
                nonce: rawNonce
            )

            try storeSession(session)
            try tokenStore.save(appleUserId, for: .appleUserId)
            isAuthenticated = true
            isLoading = false
        } catch {
            isLoading = false
            let authError = AuthServiceError.appleSignInFailed(error.localizedDescription)
            self.error = authError
            throw authError
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        // Best-effort server sign out
        if let token = tokenStore.read(.accessToken) {
            try? await client.signOut(accessToken: token)
        }

        tokenStore.deleteAll()
        clearSignedInState()
    }

    /// Resets the signed-in UI state. Callers clear the stored tokens.
    private func clearSignedInState() {
        isAuthenticated = false
        userEmail = nil
        userId = nil
        error = nil
    }

    // MARK: - Auto Backup

    private(set) var backupStatus: String?
    private var backupTask: Task<Void, Never>?

    func scheduleBackup(modelContext: ModelContext) {
        guard isAuthenticated else { return }
        backupTask?.cancel()
        backupTask = Task {
            backupStatus = "Backing up..."
            do {
                let backupService = BackupService(authService: self, modelContext: modelContext)
                let metadata = try await backupService.createAndUploadBackup()
                backupStatus = "Backed up \(metadata.sessionCount) sessions"
            } catch {
                backupStatus = "Backup failed: \(error.localizedDescription)"
            }
            try? await Task.sleep(for: .seconds(3))
            backupStatus = nil
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        isLoading = true
        error = nil

        do {
            // Apple-linked accounts re-confirm with Sign in with Apple; the
            // fresh authorization code lets the edge function revoke the
            // Apple token before deleting the account (App Review 5.1.1(v)).
            let reauthenticator = AppleReauthenticator()
            let supabase = self.client
            let deleter = AccountDeleter(
                appleUserId: { KeychainHelper.read(.appleUserId) },
                appleAuthorizationCode: { try await reauthenticator.authorizationCode() },
                callDeleteFunction: { try await supabase.callEdgeFunction("delete-account", body: $0) }
            )
            try await deleter.run()

            KeychainHelper.deleteAll()
            isAuthenticated = false
            userEmail = nil
            userId = nil
            isLoading = false
        } catch let error as AccountDeletionError {
            // Cancelled, or Apple revoked but cleanup failed: the caller shows these.
            isLoading = false
            throw error
        } catch {
            isLoading = false
            // Detail for debugging only; the user sees the generic message.
            Self.logger.error("Account deletion failed: \(error.localizedDescription)")
            let authError = AuthServiceError.deletionFailed(error.localizedDescription)
            self.error = authError
            throw authError
        }
    }

    // MARK: - Private Helpers

    private func storeSession(_ session: AuthSession) throws {
        try tokenStore.save(session.accessToken, for: .accessToken)
        try tokenStore.save(session.refreshToken, for: .refreshToken)
        try tokenStore.save(session.user.id.uuidString, for: .userId)
        userId = session.user.id
        if let email = session.user.email {
            try tokenStore.save(email, for: .userEmail)
            userEmail = email
        }
    }

    /// Only a definitive auth failure signs the user out (via
    /// `.supabaseSessionInvalidated`). Transient failures keep the session;
    /// the next request or launch refreshes again.
    func silentRefresh() async {
        do {
            let session = try await client.refreshStoredSession()
            userId = session.user.id
            if let email = session.user.email { userEmail = email }
        } catch {
            Self.logger.info("Silent refresh failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func checkAppleCredentialState() {
        guard let appleUserId = tokenStore.read(.appleUserId) else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserId) { [weak self] state, _ in
            Task { @MainActor in
                if state == .revoked || state == .notFound {
                    await self?.signOut()
                }
            }
        }
    }

    private func isTokenExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return true }

        var base64 = String(parts[1])
        while base64.count % 4 != 0 { base64 += "=" }

        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else {
            return true
        }

        return Date().timeIntervalSince1970 >= (exp - 30)
    }
}

// MARK: - Error

enum AuthServiceError: LocalizedError, Sendable {
    case appleSignInFailed(String)
    case sessionExpired
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .appleSignInFailed(let msg): "Apple Sign In failed: \(msg)"
        case .sessionExpired: "Session expired. Please sign in again."
        case .deletionFailed: "Your account wasn't deleted. Check your connection and try again. If you've been signed out, sign in and try again."
        }
    }
}
