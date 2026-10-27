import AuthenticationServices
import Foundation
import Testing
@testable import PokerStats

@MainActor
private final class Calls {
    var count = 0
}

@MainActor
private final class Nonces {
    var sentToSupabase: [String] = []
    var sentToApple: [String] = []
}

private let metadata = BackupMetadata(
    id: UUID(), userId: UUID(), storagePath: "u/backup.json.gz",
    fileSizeBytes: 100, schemaVersion: 1, sessionCount: 1, handCount: 2,
    createdAt: .now
)

private let emptyPayload = BackupPayload(
    schemaVersion: BackupPayload.currentSchemaVersion, createdAt: .now,
    appVersion: "1.0.0", sessions: [], settings: nil
)

/// Try Again re-runs the failed action, and Sign Out asks first (#36).
@Suite("Retry And Sign Out Tests")
@MainActor
struct RetryAndSignOutTests {

    // MARK: - Manual backup and restore

    /// Each closure fails `failures` times, then succeeds.
    private func backupViewModel(
        listFailures: Int = 0,
        createFailures: Int = 0,
        downloadFailures: Int = 0,
        error: any Error = URLError(.notConnectedToInternet),
        list: Calls = Calls(),
        create: Calls = Calls(),
        download: Calls = Calls(),
        restore: Calls = Calls()
    ) -> BackupViewModel {
        let vm = BackupViewModel()
        vm.configure(BackupViewModel.Actions(
            isSignedIn: { true },
            listBackups: {
                list.count += 1
                if list.count <= listFailures { throw error }
                return [metadata]
            },
            createBackup: {
                create.count += 1
                if create.count <= createFailures { throw error }
                return metadata
            },
            downloadBackup: { _ in
                download.count += 1
                if download.count <= downloadFailures { throw error }
                return emptyPayload
            },
            restoreBackup: { _ in restore.count += 1 }
        ))
        return vm
    }

    @Test func backupFailure_showsPlainCopy_andTryAgainRunsTheBackupAgain() async {
        let create = Calls()
        let vm = backupViewModel(createFailures: 1, create: create)

        await vm.createBackup()
        #expect(vm.errorMessage == UserFacingError.offlineMessage)
        #expect(vm.canRetry)
        #expect(create.count == 1)

        await vm.retry()
        #expect(create.count == 2)
        #expect(vm.errorMessage == nil)
        #expect(!vm.canRetry)
        #expect(vm.successMessage?.hasPrefix("Backed up") == true)
    }

    @Test func restoreFailure_tryAgainRestoresTheSameBackup() async {
        let download = Calls()
        let restore = Calls()
        let vm = backupViewModel(downloadFailures: 1, error: URLError(.timedOut), download: download, restore: restore)

        vm.initiateRestore(backup: metadata)
        await vm.confirmRestore()
        #expect(vm.errorMessage == UserFacingError.timeoutMessage)
        #expect(restore.count == 0)
        #expect(vm.selectedBackup == nil)

        await vm.retry()
        #expect(download.count == 2)
        #expect(restore.count == 1)
        #expect(vm.errorMessage == nil)
        #expect(vm.successMessage?.hasPrefix("Restored") == true)
    }

    @Test func backupThenRestore_failedBackup_tryAgainRunsBothSteps() async {
        let create = Calls()
        let restore = Calls()
        let vm = backupViewModel(createFailures: 1, create: create, restore: restore)

        vm.initiateRestore(backup: metadata)
        await vm.backupThenRestore()
        #expect(vm.errorMessage != nil)
        #expect(restore.count == 0)

        await vm.retry()
        #expect(create.count == 2)
        #expect(restore.count == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadFailure_tryAgainLoadsAgain() async {
        let list = Calls()
        let vm = backupViewModel(listFailures: 1, error: SupabaseError.httpError(statusCode: 503, message: "raw"), list: list)

        await vm.loadBackups()
        #expect(vm.errorMessage == UserFacingError.serverErrorMessage)
        #expect(vm.backups.isEmpty)

        await vm.retry()
        #expect(list.count == 2)
        #expect(vm.backups.count == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test func backupTooNew_offersNoTryAgain() async {
        let vm = backupViewModel(downloadFailures: 1, error: BackupError.schemaVersionTooNew(99))
        vm.initiateRestore(backup: metadata)
        await vm.confirmRestore()
        #expect(vm.errorMessage == UserFacingError.backupTooNewMessage)
        #expect(!vm.canRetry)
    }

    @Test func backupError_neverShowsTheRawText() async {
        let vm = backupViewModel(createFailures: 1, error: SupabaseError.httpError(statusCode: 400, message: "raw server text"))
        await vm.createBackup()
        #expect(vm.errorMessage == UserFacingError.unknownMessage(for: .backup))
        #expect(vm.errorMessage?.contains("raw") == false)
    }

    // MARK: - Auto-restore banner

    @Test func autoRestoreFailure_staysUp_andTryAgainRunsTheRestoreAgain() async {
        let runs = Calls()
        let vm = AutoRestoreViewModel()

        await vm.start {
            runs.count += 1
            if runs.count == 1 { throw URLError(.notConnectedToInternet) }
            return .restored(sessionCount: 4)
        }.value
        #expect(vm.message == "Restore didn't finish. \(UserFacingError.offlineMessage)")
        #expect(vm.isFailed)
        #expect(vm.canRetry)

        let retry = vm.retry()
        #expect(vm.message == "Restoring from cloud...")
        await retry?.value
        #expect(runs.count == 2)
        #expect(vm.message == "Restored 4 sessions")
        #expect(!vm.canRetry)
        #expect(vm.retry() == nil)
    }

    @Test func autoRestoreFailure_dismissHidesTheBanner() async {
        let vm = AutoRestoreViewModel()
        await vm.start { throw SupabaseError.httpError(statusCode: 500, message: "raw") }.value
        #expect(vm.message == "Restore didn't finish. \(UserFacingError.serverErrorMessage)")
        vm.dismiss()
        #expect(vm.message == nil)
        #expect(vm.retry() == nil)
    }

    @Test func autoRestoreSkipped_showsNothing() async {
        let vm = AutoRestoreViewModel()
        await vm.start { .skippedLocalDataExists }.value
        #expect(vm.status == nil)
    }

    // MARK: - Sign-in Try Again

    @Test func signInTryAgain_runsAppleAndSupabaseAgain_withAFreshNonce() async throws {
        let nonces = Nonces()
        let vm = AuthViewModel(
            authService: AuthService(),
            performAppleSignIn: { credential in
                nonces.sentToSupabase.append(credential.rawNonce)
                if nonces.sentToSupabase.count == 1 { throw URLError(.notConnectedToInternet) }
            },
            performAppleAuthorization: { hashedNonce in
                nonces.sentToApple.append(hashedNonce)
                return AppleAuthorization(
                    identityToken: Data("id-token".utf8),
                    authorizationCode: Data("code".utf8),
                    fullName: nil,
                    appleUserId: "001234.abc"
                )
            }
        )
        vm.isShowingSignIn = true

        _ = vm.startAppleSignInAttempt()
        await vm.completeAppleSignIn(
            identityToken: Data("id-token".utf8),
            authorizationCode: Data("code".utf8),
            fullName: nil,
            appleUserId: "001234.abc"
        )?.value
        #expect(vm.errorMessage == UserFacingError.offlineMessage)
        #expect(vm.isShowingSignIn)

        await vm.retrySignIn().value
        let sent = nonces.sentToSupabase
        #expect(nonces.sentToApple.count == 1)
        #expect(sent.count == 2)
        #expect(sent.first != sent.last)
        #expect(SignInNonce.sha256Hex(sent.last ?? "") == nonces.sentToApple.first)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isShowingSignIn)
        #expect(!vm.isProcessing)
    }

    @Test func signInTryAgain_cancelledByUser_showsNoError() async {
        let supabase = Calls()
        let vm = AuthViewModel(
            authService: AuthService(),
            performAppleSignIn: { _ in supabase.count += 1 },
            performAppleAuthorization: { _ in throw ASAuthorizationError(.canceled) }
        )
        await vm.retrySignIn().value
        #expect(vm.errorMessage == nil)
        #expect(!vm.isProcessing)
        #expect(supabase.count == 0)
    }

    @Test func signInServerError_showsServerCopy() async {
        let vm = AuthViewModel(
            authService: AuthService(),
            performAppleSignIn: { _ in throw SupabaseError.httpError(statusCode: 502, message: "raw") }
        )
        _ = vm.startAppleSignInAttempt()
        await vm.completeAppleSignIn(
            identityToken: Data("id-token".utf8),
            authorizationCode: Data("code".utf8),
            fullName: nil,
            appleUserId: "001234.abc"
        )?.value
        #expect(vm.errorMessage == UserFacingError.serverErrorMessage)
    }

    // MARK: - Sign Out

    @Test func signOut_asksFirst_thenSignsOutAndShowsFeedback() async {
        let signOuts = Calls()
        let vm = AuthViewModel(authService: AuthService(), performSignOut: { signOuts.count += 1 })

        vm.requestSignOut()
        #expect(vm.isShowingSignOutConfirmation)
        #expect(signOuts.count == 0)
        #expect(vm.signOutFeedback == nil)

        await vm.confirmSignOut(feedbackDuration: .seconds(60)).value
        #expect(signOuts.count == 1)
        #expect(!vm.isShowingSignOutConfirmation)
        #expect(vm.signOutFeedback == "Signed out. Your stats stay on this iPhone.")
    }

    @Test func signOut_cancelled_staysSignedIn() {
        let signOuts = Calls()
        let vm = AuthViewModel(authService: AuthService(), performSignOut: { signOuts.count += 1 })
        vm.requestSignOut()
        vm.isShowingSignOutConfirmation = false // Cancel
        #expect(signOuts.count == 0)
        #expect(vm.signOutFeedback == nil)
    }

    @Test func signOutFeedback_hidesAfterAWhile() async {
        let vm = AuthViewModel(authService: AuthService(), performSignOut: {})
        await vm.confirmSignOut(feedbackDuration: .milliseconds(10)).value
        #expect(vm.signOutFeedback != nil)
        while vm.signOutFeedback != nil { await Task.yield() }
        #expect(vm.signOutFeedback == nil)
    }
}
