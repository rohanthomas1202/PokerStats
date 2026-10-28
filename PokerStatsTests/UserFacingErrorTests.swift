import Auth
import Foundation
import Functions
import PostgREST
import Storage
import SwiftData
import Testing
@testable import PokerStats

private struct SomethingOdd: LocalizedError {
    var errorDescription: String? { "NSURLErrorDomain -1009 raw SDK text" }
}

private func response(_ statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.supabase.co")!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private func authAPIError(_ statusCode: Int) -> AuthError {
    .api(message: "raw", errorCode: .unknown, underlyingData: Data(), underlyingResponse: response(statusCode))
}

/// Each error category gets its own short copy, and no raw error text reaches the user (#36).
@Suite("User Facing Error Tests")
@MainActor
struct UserFacingErrorTests {

    // MARK: - Categories

    @Test(arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
    ])
    func offline(_ code: URLError.Code) {
        #expect(UserFacingError(URLError(code)) == .offline)
    }

    @Test func offline_whenTheTokenRefreshCouldNotReachTheServer() {
        #expect(UserFacingError(SupabaseError.refreshUnavailable) == .offline)
    }

    @Test func timeout() {
        #expect(UserFacingError(URLError(.timedOut)) == .timeout)
        #expect(UserFacingError(SupabaseError.httpError(statusCode: 408, message: "")) == .timeout)
    }

    @Test func authExpired() {
        #expect(UserFacingError(SupabaseError.sessionExpired) == .authExpired)
        #expect(UserFacingError(SupabaseError.httpError(statusCode: 401, message: "jwt expired")) == .authExpired)
        #expect(UserFacingError(AuthError.sessionMissing) == .authExpired)
        #expect(UserFacingError(authAPIError(401)) == .authExpired)
        #expect(UserFacingError(HTTPError(data: Data(), response: response(401))) == .authExpired)
        #expect(UserFacingError(StorageError(statusCode: "401", message: "Unauthorized")) == .authExpired)
        #expect(UserFacingError(StorageError(statusCode: "400", message: "jwt expired", error: "InvalidJWT")) == .authExpired)
        #expect(UserFacingError(PostgrestError(code: "PGRST301", message: "JWT expired")) == .authExpired)
    }

    @Test(arguments: [500, 502, 503, 504, 599])
    func serverError(_ statusCode: Int) {
        #expect(UserFacingError(SupabaseError.httpError(statusCode: statusCode, message: "boom")) == .serverError)
        #expect(UserFacingError(HTTPError(data: Data("<html>".utf8), response: response(statusCode))) == .serverError)
        #expect(UserFacingError(StorageError(statusCode: "\(statusCode)", message: "boom")) == .serverError)
        #expect(UserFacingError(FunctionsError.httpError(code: statusCode, data: Data())) == .serverError)
        #expect(UserFacingError(authAPIError(statusCode)) == .serverError)
    }

    @Test func serverError_whenPostgRESTCannotReachTheDatabase() {
        #expect(UserFacingError(PostgrestError(code: "PGRST002", message: "Could not query the database")) == .serverError)
    }

    @Test func backupTooNew() {
        #expect(UserFacingError(BackupError.schemaVersionTooNew(99)) == .backupTooNew)
    }

    @Test func sessionChanged() {
        #expect(UserFacingError(SupabaseError.sessionChanged) == .sessionChanged)
        #expect(UserFacingError(AuthError.refreshDiscarded) == .sessionChanged)
    }

    @Test func notSignedIn() {
        #expect(UserFacingError(BackupError.notAuthenticated) == .notSignedIn)
    }

    @Test func unknown() {
        #expect(UserFacingError(SomethingOdd()) == .unknown)
        #expect(UserFacingError(SupabaseError.httpError(statusCode: 400, message: "bad")) == .unknown)
        #expect(UserFacingError(StorageError(statusCode: "404", message: "Object not found")) == .unknown)
        #expect(UserFacingError(PostgrestError(code: "42501", message: "permission denied")) == .unknown)
        #expect(UserFacingError(BackupError.decompressionFailed) == .unknown)
        #expect(UserFacingError(URLError(.badServerResponse)) == .unknown)
    }

    // MARK: - Copy

    @Test func offlineTimeoutAuthServerAndTooNew_eachHaveTheirOwnCopy() {
        let categories: [UserFacingError] = [.offline, .timeout, .authExpired, .serverError, .backupTooNew]
        let messages = categories.map { $0.message(for: .backup) }
        #expect(Set(messages).count == categories.count)
        #expect(UserFacingError.offline.message(for: .backup) == "Couldn't reach the server. Your data on this phone is safe. Try again.")
        #expect(UserFacingError.serverError.message(for: .backup) != UserFacingError.offline.message(for: .backup))
    }

    @Test func unknownCopy_dependsOnTheAction() {
        #expect(UserFacingError.unknown.message(for: .backup) == "Couldn't back up right now. Your data on this phone is safe. Try again.")
        #expect(UserFacingError.unknown.message(for: .signIn) == AuthViewModel.signInFailedMessage)
        let actions: [UserFacingError.Action] = [.signIn, .loadBackups, .backup, .restore, .autoRestore, .deleteAllData]
        #expect(Set(actions.map { UserFacingError.unknown.message(for: $0) }).count == actions.count)
    }

    @Test func authExpiredWhileSigningIn_isTheSignInCopy() {
        #expect(UserFacingError.authExpired.message(for: .signIn) == AuthViewModel.signInFailedMessage)
    }

    /// #222: the session-changed copy says what to do next.
    @Test func sessionChangedCopy_givesANextStep() {
        #expect(UserFacingError.sessionChanged.message(for: .backup) == "You signed out or switched accounts before this finished. Try again.")
        #expect(UserFacingError.sessionChanged.message(for: .backup, isSignedIn: false) == "You signed out before this finished. Sign in and try again.")
    }

    @Test func bannerCopy_saysWhichActionFailed() {
        #expect(UserFacingError.offline.bannerMessage(for: .backup) == "Backup didn't finish. \(UserFacingError.offlineMessage)")
        #expect(UserFacingError.timeout.bannerMessage(for: .autoRestore) == "Restore didn't finish. \(UserFacingError.timeoutMessage)")
        #expect(UserFacingError.unknown.bannerMessage(for: .autoRestore) == "Couldn't restore your backup. Try again.")
    }

    @Test func copyNeverContainsTheRawError() {
        let errors: [any Error] = [
            SomethingOdd(),
            SupabaseError.httpError(statusCode: 503, message: "upstream raw"),
            StorageError(statusCode: "500", message: "storage raw"),
            BackupError.schemaVersionTooNew(99),
        ]
        let actions: [UserFacingError.Action] = [.signIn, .loadBackups, .backup, .restore, .autoRestore, .deleteAllData]
        for error in errors {
            for action in actions {
                let shown = UserFacingError(error).bannerMessage(for: action)
                #expect(!shown.contains(error.localizedDescription))
                #expect(!shown.contains("raw"))
                #expect(!shown.contains("HTTP"))
            }
        }
    }

    @Test func retryIsOfferedOnlyWhenItCanHelp() {
        #expect(UserFacingError.offline.isRetryable)
        #expect(UserFacingError.timeout.isRetryable)
        #expect(UserFacingError.serverError.isRetryable)
        #expect(UserFacingError.unknown.isRetryable)
        #expect(!UserFacingError.backupTooNew.isRetryable)
        #expect(!UserFacingError.notSignedIn.isRetryable)
        #expect(!UserFacingError.authExpired.isRetryable)
    }

    // MARK: - Through supabase-swift

    /// A signed-in backup service whose requests all get `reply`.
    private func uploadFailure(_ reply: FakeReply) async throws -> UserFacingError {
        let container = try TestHelpers.createContainer()
        let storage = InMemoryAuthStorage()
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        let client = testClient(storage) { _, _ in reply }
        let auth = AuthService(client: client)
        auth.restoreSession()
        let service = BackupService(authService: auth, modelContext: container.mainContext, client: client)
        do {
            _ = try await service.createAndUploadBackup()
            Issue.record("the backup should have failed")
            return .unknown
        } catch {
            return UserFacingError(error)
        }
    }

    @Test func storageUpload_offline_isOffline() async throws {
        #expect(try await uploadFailure(.urlError(.notConnectedToInternet)) == .offline)
    }

    @Test func storageUpload_timeout_isTimeout() async throws {
        #expect(try await uploadFailure(.urlError(.timedOut)) == .timeout)
    }

    @Test func storageUpload_5xx_isServerError() async throws {
        #expect(try await uploadFailure(.status(500, #"{"statusCode":"500","error":"Internal","message":"boom"}"#)) == .serverError)
        #expect(try await uploadFailure(.status(502, "<html>Bad Gateway</html>")) == .serverError)
    }

    /// AuthService passes the SDK's error through, so sign-in copy can tell offline apart.
    @Test func signIn_offline_showsOfflineCopy() async {
        let client = testClient(InMemoryAuthStorage()) { _, _ in .urlError(.notConnectedToInternet) }
        let vm = AuthViewModel(authService: AuthService(client: client))
        _ = vm.startAppleSignInAttempt()
        await vm.completeAppleSignIn(
            identityToken: Data("id.token".utf8),
            authorizationCode: Data("code".utf8),
            fullName: nil,
            appleUserId: TestUser.appleUserId
        )?.value
        #expect(vm.errorMessage == UserFacingError.offlineMessage)
    }
}
