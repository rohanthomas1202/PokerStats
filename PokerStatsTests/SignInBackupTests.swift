import Foundation
import SwiftData
import Testing
@testable import PokerStats

private func metadata() -> BackupMetadata {
    BackupMetadata(
        id: UUID(), userId: TestUser.id, storagePath: "p", fileSizeBytes: 1,
        schemaVersion: 1, sessionCount: 1, handCount: 0, createdAt: .now
    )
}

@MainActor
private final class Log {
    var events: [String] = []
    func count(_ event: String) -> Int { events.filter { $0 == event }.count }
}

/// #293: when the account that owns the local data signs back in with
/// changes no backup sent, one backup runs at sign-in. Nothing runs for
/// another account's data or while account deletion runs (#61).
@Suite("Sign-in Backup Tests", .timeLimit(.minutes(1)))
@MainActor
struct SignInBackupTests {
    private let storage = InMemoryAuthStorage()
    private let owner = LocalDataOwner(defaults: UserDefaults(suiteName: "SignInBackupTests.\(UUID().uuidString)")!)

    /// Signed out, with the isolated owner store.
    private func signedOutAuth() -> AuthService {
        let auth = AuthService(client: testClient(storage) { _, _ in .status(204, "") })
        auth.localDataOwner = owner
        return auth
    }

    private func signIn(_ auth: AuthService) {
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        auth.restoreSession()
    }

    /// A session ended while signed out: its automatic backup couldn't run.
    private func endSessionWhileSignedOut(_ auth: AuthService) throws {
        let container = try TestHelpers.createContainer()
        auth.scheduleBackup(modelContext: container.mainContext)
        #expect(auth.hasUnsentChanges)
        #expect(auth.backupStatus == nil)
    }

    // MARK: - Same owner: one backup

    @Test func sameOwner_backupDroppedBySignOut_backsUpOnceAtSignIn() async {
        owner.adopt(TestUser.id)
        let auth = signedOutAuth()
        signIn(auth)
        let log = Log()
        auth.scheduleBackup {
            log.events.append("session backup started")
            try await Task.sleep(for: .seconds(60))
            return metadata()
        }
        await waitUntil("session backup started") { log.events.contains("session backup started") }
        await auth.signOut()
        #expect(auth.hasUnsentChanges)

        signIn(auth)
        auth.backUpUnsentChangesAtSignIn {
            log.events.append("sign-in backup")
            return metadata()
        }
        await waitUntil("sign-in backup finished") { auth.backupStatus?.hasPrefix("Backed up") == true }
        #expect(!auth.hasUnsentChanges)

        // A second sign-in event with nothing new to send runs nothing.
        auth.backUpUnsentChangesAtSignIn {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events == ["session backup started", "sign-in backup"])
    }

    @Test func sameOwner_sessionEndedWhileSignedOut_backsUpOnceAtSignIn() async throws {
        owner.adopt(TestUser.id)
        let auth = signedOutAuth()
        try endSessionWhileSignedOut(auth)

        signIn(auth)
        let log = Log()
        auth.backUpUnsentChangesAtSignIn {
            log.events.append("sign-in backup")
            return metadata()
        }
        await waitUntil("sign-in backup finished") { auth.backupStatus?.hasPrefix("Backed up") == true }
        #expect(log.count("sign-in backup") == 1)
        #expect(!auth.hasUnsentChanges)
    }

    /// Without this change nothing backed up at sign-in; with nothing
    /// unsent, that stays true.
    @Test func sameOwner_nothingUnsent_noBackupAtSignIn() async {
        owner.adopt(TestUser.id)
        let auth = signedOutAuth()
        signIn(auth)
        let log = Log()
        auth.backUpUnsentChangesAtSignIn {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events.isEmpty)
        #expect(auth.backupStatus == nil)
    }

    /// The app's path: `backUpUnsentChangesAtSignIn(modelContext:)` uploads
    /// the whole store once, to the returning owner's folder.
    @Test func sameOwner_appPath_uploadsTheStoreOnceAtSignIn() async throws {
        owner.adopt(TestUser.id)
        let server = FakeServer()
        let client = testClient(storage, server: server) { request, _ in
            switch (request.method, request.path) {
            case ("POST", let path) where path.hasPrefix("/storage/v1/object/backups/"):
                return .status(200, #"{"Key":"backups/x","Id":"1"}"#)
            case ("POST", "/rest/v1/backup_metadata"):
                return .status(201, """
                [{"id":"\(UUID().uuidString)","user_id":"\(TestUser.id.uuidString)","storage_path":"p",
                  "file_size_bytes":1,"schema_version":1,"session_count":1,"hand_count":0,
                  "created_at":"2026-11-01T10:00:00+00:00"}]
                """)
            case ("GET", "/rest/v1/backup_metadata"):
                return .status(200, "[]")
            default:
                return .status(204, "")
            }
        }
        let auth = AuthService(client: client)
        auth.localDataOwner = owner
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        context.insert(Session(location: "Played while signed out"))
        try context.save()
        auth.scheduleBackup(modelContext: context) // signed out: the session's backup can't run
        #expect(auth.hasUnsentChanges)
        #expect(server.requests.isEmpty)

        signIn(auth)
        auth.backUpUnsentChangesAtSignIn(modelContext: context)
        await waitUntil("sign-in backup finished") { auth.backupStatus?.hasPrefix("Backed up") == true }
        auth.backUpUnsentChangesAtSignIn(modelContext: context)
        for _ in 0..<20 { await Task.yield() }

        let uploads = server.requests.filter { $0.path.hasPrefix("/storage/v1/object/backups/") }
        #expect(uploads.count == 1)
        let path = try #require(uploads.first).path.removingPercentEncoding ?? ""
        #expect(path.hasPrefix("/storage/v1/object/backups/\(TestUser.id.uuidString.lowercased())/"))
        #expect(!auth.hasUnsentChanges)
    }

    // MARK: - Mismatch: no backup

    @Test func anotherAccountOwnsTheData_noBackupAtSignIn() async throws {
        let otherAccount = UUID()
        owner.adopt(otherAccount)
        let auth = signedOutAuth()
        try endSessionWhileSignedOut(auth)

        signIn(auth)
        let log = Log()
        auth.backUpUnsentChangesAtSignIn {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events.isEmpty)
        #expect(auth.backupStatus == nil)
        #expect(owner.ownerId == otherAccount)
        #expect(auth.hasUnsentChanges) // still owed to the owner
    }

    /// Data with no owner (Delete All Data cleared it) isn't a returning owner.
    @Test func noOwner_noBackupAtSignIn() async throws {
        let auth = signedOutAuth()
        try endSessionWhileSignedOut(auth)

        signIn(auth)
        let log = Log()
        auth.backUpUnsentChangesAtSignIn {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events.isEmpty)
        #expect(auth.backupStatus == nil)
    }

    // MARK: - Deletion pending: no backup

    @Test func accountDeletionRunning_noBackupAtSignIn_norAfterItStops() async throws {
        owner.adopt(TestUser.id)
        let auth = signedOutAuth()
        try endSessionWhileSignedOut(auth)
        signIn(auth)

        await auth.suspendBackups()
        let log = Log()
        auth.backUpUnsentChangesAtSignIn {
            log.events.append("sign-in backup")
            return metadata()
        }
        auth.resumeBackups()
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events.isEmpty)
        #expect(auth.backupStatus == nil)
    }

    @Test func finishedAccountDeletion_leavesNothingUnsent() async {
        owner.adopt(TestUser.id)
        let auth = signedOutAuth()
        signIn(auth)
        auth.scheduleBackup {
            try await Task.sleep(for: .seconds(60))
            return metadata()
        }
        try? await auth.deleteAccount(serverDelete: {})
        #expect(!auth.isAuthenticated)
        #expect(!auth.hasUnsentChanges)
    }
}
