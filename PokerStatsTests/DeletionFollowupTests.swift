import Foundation
import Testing
@testable import PokerStats

private struct ServerDown: Error {}

@MainActor
private final class Log {
    var events: [String] = []
    func count(_ event: String) -> Int { events.filter { $0 == event }.count }
}

private func metadata() -> BackupMetadata {
    BackupMetadata(
        id: UUID(), userId: UUID(), storagePath: "p", fileSizeBytes: 1,
        schemaVersion: 1, sessionCount: 1, handCount: 0, createdAt: .now
    )
}

private let emptyPayload = BackupPayload(
    schemaVersion: BackupPayload.currentSchemaVersion, createdAt: .now,
    appVersion: "1.0.0", sessions: [], settings: nil
)

/// Follow-ups to #267: the note for a manual backup or restore that a
/// deletion stopped (#268), and Kate's Lows (#275).
@Suite("Deletion Follow-up Tests", .timeLimit(.minutes(1)))
@MainActor
struct DeletionFollowupTests {

    private func signedInAuth(_ storage: InMemoryAuthStorage = InMemoryAuthStorage()) -> AuthService {
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        let auth = AuthService(client: testClient(storage) { _, _ in .status(204, "") })
        auth.restoreSession()
        return auth
    }

    /// Wired to `auth` like the app. The first backup and the first download
    /// run until cancelled; later ones finish right away.
    private func backupViewModel(_ auth: AuthService, log: Log) -> BackupViewModel {
        let vm = BackupViewModel()
        vm.configure(BackupViewModel.Actions(
            isSignedIn: { auth.isAuthenticated },
            listBackups: { [metadata()] },
            createBackup: {
                try await auth.performCloudWork {
                    log.events.append("backup started")
                    if log.count("backup started") == 1 { try await Task.sleep(for: .seconds(60)) }
                    return metadata()
                }
            },
            downloadBackup: { _ in
                try await auth.performCloudWork {
                    log.events.append("download started")
                    if log.count("download started") == 1 { try await Task.sleep(for: .seconds(60)) }
                    return emptyPayload
                }
            },
            restoreBackup: { _ in log.events.append("restored") },
            isCloudWorkSuspended: { auth.isCloudWorkSuspended }
        ))
        return vm
    }

    // MARK: - #268: say when a deletion that didn't complete stopped a manual backup or restore

    @Test func backUpNow_stoppedByADeletionThatDidNotComplete_showsANeutralNote() async {
        let failures: [any Error] = [ServerDown(), AccountDeletionError.reauthenticationCancelled]
        for failure in failures {
            let auth = signedInAuth()
            let log = Log()
            let vm = backupViewModel(auth, log: log)
            let backup = Task { await vm.createBackup() }
            await waitUntil("backup started") { log.events.contains("backup started") }

            _ = try? await auth.deleteAccount(serverDelete: {
                #expect(vm.stoppedNote == nil, "nothing while the deletion runs")
                throw failure
            })
            await backup.value

            #expect(vm.stoppedNote == BackupViewModel.backupStoppedMessage, "\(failure)")
            #expect(vm.errorMessage == nil) // not an error
            #expect(vm.successMessage == nil)

            // Back Up Now again: the note goes away and the backup runs.
            await vm.createBackup()
            #expect(vm.stoppedNote == nil)
            #expect(vm.successMessage?.hasPrefix("Backed up") == true)
        }
    }

    @Test func backUpNow_stoppedByADeletionThatCompleted_showsNothing() async throws {
        let auth = signedInAuth()
        let log = Log()
        let vm = backupViewModel(auth, log: log)
        let backup = Task { await vm.createBackup() }
        await waitUntil("backup started") { log.events.contains("backup started") }

        try await auth.deleteAccount(serverDelete: {})
        await backup.value

        #expect(!auth.isAuthenticated)
        #expect(vm.stoppedNote == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func manualRestore_stoppedByAFailedDeletion_showsTheRestoreNote() async {
        let auth = signedInAuth()
        let log = Log()
        let vm = backupViewModel(auth, log: log)
        vm.initiateRestore(backup: metadata())
        let restore = Task { await vm.confirmRestore() }
        await waitUntil("download started") { log.events.contains("download started") }

        _ = try? await auth.deleteAccount(serverDelete: { throw ServerDown() })
        await restore.value

        #expect(!log.events.contains("restored"))
        #expect(vm.stoppedNote == BackupViewModel.restoreStoppedMessage)
        #expect(vm.errorMessage == nil)

        // Choosing the backup again restores it and clears the note.
        vm.initiateRestore(backup: metadata())
        await vm.confirmRestore()
        #expect(log.events.contains("restored"))
        #expect(vm.stoppedNote == nil)
    }

    @Test func backUpFirstThenRestore_stoppedDuringTheBackup_showsTheRestoreNote() async {
        let auth = signedInAuth()
        let log = Log()
        let vm = backupViewModel(auth, log: log)
        vm.initiateRestore(backup: metadata())
        let run = Task { await vm.backupThenRestore() }
        await waitUntil("backup started") { log.events.contains("backup started") }

        _ = try? await auth.deleteAccount(serverDelete: { throw ServerDown() })
        await run.value

        #expect(log.events == ["backup started"]) // no download, no restore
        #expect(vm.stoppedNote == BackupViewModel.restoreStoppedMessage)
        #expect(vm.errorMessage == nil)
        #expect(vm.selectedBackup == nil)
    }

    // MARK: - #275 item 1: sign-out drops the scheduled backup

    @Test func signOut_dropsTheScheduledBackup_soALaterFailedDeletionDoesNotRunIt() async {
        let storage = InMemoryAuthStorage()
        let auth = signedInAuth(storage)
        let log = Log()
        auth.scheduleBackup {
            log.events.append("backup started")
            defer { log.events.append("backup stopped") }
            try await Task.sleep(for: .seconds(60))
            return metadata()
        }
        await waitUntil("backup started") { log.events.contains("backup started") }

        await auth.signOut()
        await waitUntil("backup stopped") { log.events.contains("backup stopped") }
        #expect(!auth.isAuthenticated)
        #expect(auth.backupStatus == nil) // no "Backing up..." left behind

        // Signed in again, then a deletion that fails resumes backups.
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        auth.restoreSession()
        #expect(auth.isAuthenticated)
        _ = try? await auth.deleteAccount(serverDelete: { throw ServerDown() })
        for _ in 0..<20 { await Task.yield() }

        #expect(log.events == ["backup started", "backup stopped"])
        #expect(auth.backupStatus == nil)
    }

    // MARK: - #275 item 2: backup first, then restore, when the list reload fails

    /// Backup succeeds, then the list reload fails once.
    private func reloadFailsOnce(list: Log, create: Log, restore: Log, downloadFailures: Int = 0) -> BackupViewModel {
        let downloads = Log()
        let vm = BackupViewModel()
        vm.configure(BackupViewModel.Actions(
            isSignedIn: { true },
            listBackups: {
                list.events.append("list")
                if list.count("list") == 1 { throw SupabaseError.httpError(statusCode: 503, message: "raw") }
                return [metadata()]
            },
            createBackup: {
                create.events.append("upload")
                return metadata()
            },
            downloadBackup: { _ in
                downloads.events.append("download")
                if downloads.count("download") <= downloadFailures { throw URLError(.timedOut) }
                return emptyPayload
            },
            restoreBackup: { _ in restore.events.append("restored") }
        ))
        return vm
    }

    @Test func backupThenRestore_reloadFails_restoresAnyway_andKeepsTheReloadError() async {
        let list = Log(), create = Log(), restore = Log()
        let vm = reloadFailsOnce(list: list, create: create, restore: restore)

        vm.initiateRestore(backup: metadata())
        await vm.backupThenRestore()

        #expect(create.events == ["upload"])
        #expect(restore.events == ["restored"]) // the backup finished, so the restore went ahead
        #expect(vm.successMessage?.hasPrefix("Restored") == true)
        #expect(vm.errorMessage == UserFacingError.serverErrorMessage) // the reload error stays up
        #expect(vm.canRetry)

        // Try Again reloads the list; it doesn't upload a second backup (#260).
        await vm.retry()
        #expect(list.events.count == 2)
        #expect(create.events == ["upload"])
        #expect(restore.events == ["restored"])
        #expect(vm.backups.count == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test func backupThenRestore_reloadAndRestoreFail_showsTheRestoreError_andTryAgainOnlyRestores() async {
        let list = Log(), create = Log(), restore = Log()
        let vm = reloadFailsOnce(list: list, create: create, restore: restore, downloadFailures: 1)

        vm.initiateRestore(backup: metadata())
        await vm.backupThenRestore()
        #expect(vm.errorMessage == UserFacingError.timeoutMessage) // the restore's error wins
        #expect(restore.events.isEmpty)

        await vm.retry()
        #expect(create.events == ["upload"]) // no second upload
        #expect(restore.events == ["restored"])
        #expect(vm.errorMessage == nil)
    }
}
