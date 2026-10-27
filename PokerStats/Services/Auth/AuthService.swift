import Auth
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
    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AuthService")
    @ObservationIgnored nonisolated(unsafe) private var authEventsTask: Task<Void, Never>?

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    deinit {
        authEventsTask?.cancel()
    }

    // MARK: - Initialization

    func initialize() {
        KeychainSessionStorage().removeLegacyItems()
        restoreSession()
        observeAuthChanges()

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

    /// Signed-in state comes from the session the SDK stored. Returns true
    /// when that session has expired; the SDK refreshes it when the auth
    /// change stream starts (`observeAuthChanges()`) or on the next request.
    @discardableResult
    func restoreSession() -> Bool {
        guard let session = client.auth.currentSession else { return false }
        apply(session.user)
        return session.isExpired
    }

    /// Follows the SDK's auth events. A refresh the server rejects for good
    /// (refresh token not found or already used, session gone) makes the SDK
    /// remove the session and emit `.signedOut`; a transient failure emits
    /// nothing and the session stays. Idempotent.
    func observeAuthChanges() {
        guard authEventsTask == nil else { return }
        let changes = client.auth.authStateChanges
        authEventsTask = Task { [weak self] in
            for await (event, session) in changes {
                guard let self else { return }
                switch event {
                case .signedOut, .userDeleted:
                    self.clearSignedInState()
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session { self.apply(session.user) }
                default:
                    break
                }
            }
        }
    }

    /// The Apple user ID (`sub`) of the signed-in account's Apple identity.
    var appleUserId: String? {
        guard let identity = client.auth.currentUser?.identities?.first(where: { $0.provider == "apple" }) else {
            return nil
        }
        return identity.identityData?["sub"]?.stringValue ?? identity.id
    }

    // MARK: - Sign In with Apple

    /// `rawNonce` is the value whose SHA-256 went to Apple; Supabase checks it
    /// against the ID token's `nonce` claim.
    func signInWithApple(identityToken: Data, rawNonce: String) async throws {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthServiceError.appleSignInFailed("Invalid identity token")
        }

        isLoading = true
        error = nil

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: tokenString, nonce: rawNonce)
            )
            apply(session.user)
            isLoading = false
        } catch {
            isLoading = false
            // The caller maps the original error to plain copy (offline, 5xx, ...)
            // and logs it; only the error's type is kept here.
            self.error = .appleSignInFailed(String(describing: type(of: error)))
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        // The SDK removes the local session first; the server call is best effort.
        try? await client.auth.signOut()
        clearSignedInState()
    }

    /// Resets the signed-in UI state. Callers clear the stored session.
    private func clearSignedInState() {
        isAuthenticated = false
        userEmail = nil
        userId = nil
        error = nil
    }

    private func apply(_ user: User) {
        isAuthenticated = true
        userId = user.id
        userEmail = user.email
    }

    // MARK: - Auto Backup

    private(set) var backupStatus: String?
    private var backupTask: Task<Void, Never>?
    /// True while account deletion runs; no new backup starts.
    private var backupsSuspended = false

    func scheduleBackup(modelContext: ModelContext) {
        guard isAuthenticated else { return }
        scheduleBackup {
            try await BackupService(authService: self, modelContext: modelContext).createAndUploadBackup()
        }
    }

    /// Runs `backup` as the one pending backup, replacing any earlier one.
    /// Separate so tests can supply the work.
    func scheduleBackup(_ backup: @escaping @MainActor () async throws -> BackupMetadata) {
        guard !backupsSuspended else { return }
        backupTask?.cancel()
        backupTask = Task {
            backupStatus = "Backing up..."
            do {
                let metadata = try await backup()
                if Task.isCancelled { return }
                backupStatus = "Backed up \(metadata.sessionCount) sessions"
            } catch {
                // A cancelled backup was replaced or stopped; it reports nothing.
                if Task.isCancelled { return }
                UserFacingError.log(error, action: .backup, to: Self.logger)
                backupStatus = UserFacingError(error).bannerMessage(for: .backup, isSignedIn: isAuthenticated)
            }
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            backupStatus = nil
        }
    }

    /// Cancels the scheduled or in-flight backup, waits until it has stopped,
    /// and blocks new ones until `resumeBackups()`.
    func suspendBackups() async {
        backupsSuspended = true
        let task = backupTask
        backupTask = nil
        task?.cancel()
        await task?.value
        backupStatus = nil
    }

    func resumeBackups() {
        backupsSuspended = false
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        let supabase = self.client
        let appleUserId = self.appleUserId
        try await deleteAccount(serverDelete: {
            // Apple-linked accounts re-confirm with Sign in with Apple; the
            // fresh authorization code lets the edge function revoke the
            // Apple token before deleting the account (App Review 5.1.1(v)).
            let reauthenticator = AppleReauthenticator()
            let deleter = AccountDeleter(
                appleUserId: { appleUserId },
                appleAuthorizationCode: { try await reauthenticator.authorizationCode() },
                callDeleteFunction: { try await supabase.callEdgeFunction("delete-account", body: $0) }
            )
            try await deleter.run()
        })
    }

    /// Order: stop backups, then the server delete, then remove the local
    /// session and auth state. The caller wipes local SwiftData only after this
    /// returns, so a failed server delete leaves local data in place.
    /// Separate so tests can supply the server delete.
    func deleteAccount(serverDelete: @MainActor () async throws -> Void) async throws {
        // A backup landing after the server delete would recreate cloud data.
        await suspendBackups()
        defer { resumeBackups() }

        isLoading = true
        error = nil

        do {
            try await serverDelete()

            // The account is gone, so the server sign-out fails or is ignored;
            // the SDK removes the local session before calling it.
            try? await client.auth.signOut(scope: .local)
            clearSignedInState()
            isLoading = false
        } catch let error as AccountDeletionError {
            // Cancelled, or a server failure with its own alert: the caller shows these.
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

    private func checkAppleCredentialState() {
        guard let appleUserId else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserId) { [weak self] state, _ in
            Task { @MainActor in
                if state == .revoked || state == .notFound {
                    await self?.signOut()
                }
            }
        }
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
