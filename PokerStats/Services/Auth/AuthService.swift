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

    private let client = SupabaseClient.shared
    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AuthService")

    // MARK: - Initialization

    func initialize() {
        // Restore session from Keychain
        if let tokenString = KeychainHelper.read(.accessToken),
           let userIdString = KeychainHelper.read(.userId),
           let id = UUID(uuidString: userIdString) {
            isAuthenticated = true
            userId = id
            userEmail = KeychainHelper.read(.userEmail)

            // Check if token needs refresh (non-blocking)
            if isTokenExpired(tokenString) {
                Task {
                    await silentRefresh()
                }
            }
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
            try KeychainHelper.save(appleUserId, for: .appleUserId)
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
        if let token = KeychainHelper.read(.accessToken) {
            try? await client.signOut(accessToken: token)
        }

        KeychainHelper.deleteAll()
        isAuthenticated = false
        userEmail = nil
        userId = nil
        error = nil
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
                backupStatus = "Backup failed: \(error.localizedDescription)"
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
        try await deleteAccount(serverDelete: {
            // Apple-linked accounts re-confirm with Sign in with Apple; the
            // fresh authorization code lets the edge function revoke the
            // Apple token before deleting the account (App Review 5.1.1(v)).
            let reauthenticator = AppleReauthenticator()
            let deleter = AccountDeleter(
                appleUserId: { KeychainHelper.read(.appleUserId) },
                appleAuthorizationCode: { try await reauthenticator.authorizationCode() },
                callDeleteFunction: { try await supabase.callEdgeFunction("delete-account", body: $0) }
            )
            try await deleter.run()
        })
    }

    /// Order: stop backups, then the server delete, then clear the Keychain
    /// and auth state. The caller wipes local SwiftData only after this
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
        try KeychainHelper.save(session.accessToken, for: .accessToken)
        try KeychainHelper.save(session.refreshToken, for: .refreshToken)
        try KeychainHelper.save(session.user.id.uuidString, for: .userId)
        userId = session.user.id
        if let email = session.user.email {
            try KeychainHelper.save(email, for: .userEmail)
            userEmail = email
        }
    }

    private func silentRefresh() async {
        guard let refreshToken = KeychainHelper.read(.refreshToken) else {
            await signOut()
            return
        }

        do {
            let session = try await client.refreshSession(refreshToken: refreshToken)
            try storeSession(session)
        } catch {
            await signOut()
        }
    }

    private func checkAppleCredentialState() {
        guard let appleUserId = KeychainHelper.read(.appleUserId) else { return }

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
