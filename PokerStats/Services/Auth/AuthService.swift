import Foundation
import AuthenticationServices

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
        appleUserId: String
    ) async throws {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthServiceError.appleSignInFailed("Invalid identity token")
        }

        isLoading = true
        error = nil

        do {
            let session = try await client.signInWithIdToken(
                provider: .apple,
                idToken: tokenString
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

    // MARK: - Sign In with Google

    func signInWithGoogle(idToken: String) async throws {
        isLoading = true
        error = nil

        do {
            let session = try await client.signInWithIdToken(
                provider: .google,
                idToken: idToken
            )

            try storeSession(session)
            isAuthenticated = true
            isLoading = false
        } catch {
            isLoading = false
            let authError = AuthServiceError.googleSignInFailed(error.localizedDescription)
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

    // MARK: - Delete Account

    func deleteAccount() async throws {
        isLoading = true
        error = nil

        do {
            // Call Edge Function to delete all server-side data
            try await client.callEdgeFunction("delete-account")

            // Revoke Apple credential if applicable
            // (Apple token revocation requires the authorization code,
            // which we don't persist. The Edge Function handles server-side cleanup.)

            KeychainHelper.deleteAll()
            isAuthenticated = false
            userEmail = nil
            userId = nil
            isLoading = false
        } catch {
            isLoading = false
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
    case googleSignInFailed(String)
    case sessionExpired
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .appleSignInFailed(let msg): "Apple Sign In failed: \(msg)"
        case .googleSignInFailed(let msg): "Google Sign In failed: \(msg)"
        case .sessionExpired: "Session expired. Please sign in again."
        case .deletionFailed(let msg): "Account deletion failed: \(msg)"
        }
    }
}
