import Foundation
import SwiftData
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
            isCloudWorkSuspended: { auth.isCloudWorkSuspended },
            stoppedWork: { auth.stoppedCloudWork },
            setStoppedWork: { auth.setStoppedCloudWork($0) }
        ))
        return vm
    }

    /// The Cloud Backup screen opened again: a new view model wired to the
    /// same `auth`, like the app's `configure(authService:modelContext:)`.
    /// The user has to leave the screen to delete the account.
    private func reopenedScreen(_ auth: AuthService, log: Log) -> BackupViewModel {
        backupViewModel(auth, log: log)
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

            // The user left Cloud Backup to delete; the reopened screen says so.
            let reopened = reopenedScreen(auth, log: log)
            #expect(reopened.stoppedNote == BackupViewModel.backupStoppedMessage, "\(failure)")
            #expect(reopened.errorMessage == nil) // not an error
            #expect(reopened.successMessage == nil)

            // Back Up Now again: the note goes away and the backup runs.
            await reopened.createBackup()
            #expect(reopened.stoppedNote == nil)
            #expect(reopenedScreen(auth, log: log).stoppedNote == nil)
            #expect(reopened.successMessage?.hasPrefix("Backed up") == true)
        }
    }

    @Test func backUpNow_stoppedByADeletionThatCompleted_showsNothing() async throws {
        let storage = InMemoryAuthStorage()
        let auth = signedInAuth(storage)
        let log = Log()
        let vm = backupViewModel(auth, log: log)
        let backup = Task { await vm.createBackup() }
        await waitUntil("backup started") { log.events.contains("backup started") }

        try await auth.deleteAccount(serverDelete: {})
        await backup.value

        #expect(!auth.isAuthenticated)
        #expect(vm.stoppedNote == nil)
        #expect(vm.errorMessage == nil)
        #expect(auth.stoppedCloudWork == nil)

        // A Cloud Backup screen opened after the deletion shows nothing either,
        // including once someone signs in again.
        #expect(reopenedScreen(auth, log: log).stoppedNote == nil)
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        auth.restoreSession()
        #expect(reopenedScreen(auth, log: log).stoppedNote == nil)
    }

    @Test func stoppedNote_isClearedBySignOut() async {
        let storage = InMemoryAuthStorage()
        let auth = signedInAuth(storage)
        let log = Log()
        let vm = backupViewModel(auth, log: log)
        let backup = Task { await vm.createBackup() }
        await waitUntil("backup started") { log.events.contains("backup started") }
        _ = try? await auth.deleteAccount(serverDelete: { throw ServerDown() })
        await backup.value
        #expect(reopenedScreen(auth, log: log).stoppedNote == BackupViewModel.backupStoppedMessage)

        await auth.signOut()
        #expect(auth.stoppedCloudWork == nil)

        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        auth.restoreSession()
        #expect(reopenedScreen(auth, log: log).stoppedNote == nil)
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
        let reopened = reopenedScreen(auth, log: log)
        #expect(reopened.stoppedNote == BackupViewModel.restoreStoppedMessage)
        #expect(reopened.errorMessage == nil)

        // Choosing the backup again restores it and clears the note.
        reopened.initiateRestore(backup: metadata())
        await reopened.confirmRestore()
        #expect(log.events.contains("restored"))
        #expect(reopened.stoppedNote == nil)
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
        #expect(vm.selectedBackup == nil)
        let reopened = reopenedScreen(auth, log: log)
        #expect(reopened.stoppedNote == BackupViewModel.restoreStoppedMessage)
        #expect(reopened.errorMessage == nil)
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

    // MARK: - #275 item 1: signing back in after sign-out dropped a backup

    /// The sessions in the backup `upload` sent: the gzip part of the
    /// multipart body, decoded like `BackupService.downloadBackup`.
    private func uploadedLocations(_ upload: SeenRequest) throws -> [String] {
        let boundary = try #require(upload.header("Content-Type")?.components(separatedBy: "boundary=").last)
        let body = try #require(upload.body)
        let start = try #require(body.range(of: Data("Content-Type: application/gzip\r\n\r\n".utf8))).upperBound
        let end = try #require(body.range(of: Data("\r\n--\(boundary)".utf8), in: start..<body.endIndex)).lowerBound
        let json = try (body.subdata(in: start..<end) as NSData).decompressed(using: .zlib) as Data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(BackupPayload.self, from: json).sessions.map(\.location).sorted()
    }

    /// Kate's conditions on #277: sign-out drops the in-flight scheduled
    /// backup but keeps the local data and its owner, and once the same
    /// account signs back in, the next session's automatic backup uploads
    /// everything, including the changes the dropped backup never sent.
    /// No backup runs at sign-in itself; `scheduleBackup(modelContext:)` is
    /// what `ActiveSessionViewModel.endSession` calls, and it snapshots the
    /// whole store.
    @Test func signOutDuringAScheduledBackup_keepsTheData_andTheNextAutoBackupAfterSigningBackInSendsIt() async throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let owner = LocalDataOwner(defaults: UserDefaults(suiteName: "DeletionFollowupTests.\(UUID().uuidString)")!)
        let ownership = LocalDataOwnershipViewModel()
        ownership.owner = owner

        // The first upload hangs until cancelled; later ones succeed.
        let server = FakeServer()
        let storage = InMemoryAuthStorage()
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        let client = testClient(storage, server: server) { request, _ in
            switch (request.method, request.path) {
            case ("POST", let path) where path.hasPrefix("/storage/v1/object/backups/"):
                let uploads = server.requests.filter { $0.path.hasPrefix("/storage/v1/object/backups/") }
                if uploads.count == 1 { try await Task.sleep(for: .seconds(60)) }
                return .status(200, #"{"Key":"backups/x","Id":"1"}"#)
            case ("POST", "/rest/v1/backup_metadata"):
                return .status(201, """
                [{"id":"\(UUID().uuidString)","user_id":"\(TestUser.id.uuidString)","storage_path":"p",
                  "file_size_bytes":1,"schema_version":1,"session_count":3,"hand_count":1,
                  "created_at":"2026-10-28T10:00:00+00:00"}]
                """)
            case ("GET", "/rest/v1/backup_metadata"):
                return .status(200, "[]")
            default:
                return .status(204, "")
            }
        }
        let auth = AuthService(client: client)
        auth.localDataOwner = owner
        auth.restoreSession()
        ownership.signedIn(TestUser.id, modelContext: context)

        func addSession(_ location: String, withHand: Bool = false) throws {
            let session = Session(location: location)
            context.insert(session)
            if withHand {
                let hand = TestHelpers.foldHand()
                hand.session = session
                context.insert(hand)
            }
            try context.save()
        }
        func uploads() -> [SeenRequest] {
            server.requests.filter { $0.path.hasPrefix("/storage/v1/object/backups/") }
        }
        func metadataInserts() -> [SeenRequest] {
            server.requests.filter { $0.method == "POST" && $0.path == "/rest/v1/backup_metadata" }
        }

        // A session ends and its automatic backup starts uploading.
        try addSession("Backed up before", withHand: true)
        try addSession("Unsent")
        auth.scheduleBackup(modelContext: context)
        await waitUntil("first upload started") { uploads().count == 1 }

        // Sign out while it's in flight.
        await auth.signOut()
        ownership.signedOut()
        for _ in 0..<20 { await Task.yield() }
        #expect(!auth.isAuthenticated)
        #expect(auth.backupStatus == nil)
        #expect(metadataInserts().isEmpty) // the dropped backup never finished

        // (1) The local data and its owner are intact.
        let stored = try ModelContext(container).fetch(FetchDescriptor<Session>())
        #expect(stored.map(\.location).sorted() == ["Backed up before", "Unsent"])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Hand>()) == 1)
        #expect(owner.ownerId == TestUser.id)

        // The same account signs back in: it still owns the data, no prompt.
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        auth.restoreSession()
        ownership.signedIn(TestUser.id, modelContext: context)
        #expect(auth.isAuthenticated)
        #expect(owner.ownerId == TestUser.id)
        #expect(!ownership.isShowingChoice)
        #expect(!ownership.backupsBlocked)

        // (2) The next session's automatic backup sends everything, including "Unsent".
        try addSession("Next session")
        auth.scheduleBackup(modelContext: context)
        await waitUntil("backup finished") { auth.backupStatus?.hasPrefix("Backed up") == true }

        #expect(uploads().count == 2)
        let upload = try #require(uploads().last)
        let path = upload.path.removingPercentEncoding ?? upload.path
        #expect(path.hasPrefix("/storage/v1/object/backups/\(TestUser.id.uuidString.lowercased())/"))
        #expect(try uploadedLocations(upload) == ["Backed up before", "Next session", "Unsent"])
        let insert = try #require(metadataInserts().first)
        #expect(metadataInserts().count == 1)
        #expect(insert.json?["session_count"] as? Int == 3)
        #expect(insert.json?["hand_count"] as? Int == 1)
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

    @Test func backupThenRestore_reloadAndRestoreFail_showsTheRestoreError_andTryAgainRestoresThenReloads() async {
        let list = Log(), create = Log(), restore = Log()
        let vm = reloadFailsOnce(list: list, create: create, restore: restore, downloadFailures: 1)

        vm.initiateRestore(backup: metadata())
        await vm.backupThenRestore()
        #expect(vm.errorMessage == UserFacingError.timeoutMessage) // the restore's error wins
        #expect(restore.events.isEmpty)
        #expect(list.events.count == 1)

        await vm.retry()
        #expect(create.events == ["upload"]) // no second upload
        #expect(restore.events == ["restored"])
        #expect(vm.errorMessage == nil)
        // The failed reload isn't dropped: the restore's success reloads the list.
        #expect(list.events.count == 2)
        #expect(vm.backups.count == 1)
        #expect(vm.successMessage?.hasPrefix("Restored") == true)
    }
}
