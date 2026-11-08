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
///
/// The unsent-changes flag lives in the owner's UserDefaults (#300). Each
/// test makes its own owner on a ThrowawayDefaults, which the owner holds for
/// the whole test; the suite stores none and runs serialized.
@Suite("Sign-in Backup Tests", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SignInBackupTests {
    private let storage = InMemoryAuthStorage()
    /// A store with one session, so the sign-in backup has something to send.
    private let container: ModelContainer

    init() throws {
        container = try TestHelpers.createContainer()
        container.mainContext.insert(Session(location: "Local session"))
        try container.mainContext.save()
    }

    private var context: ModelContext { container.mainContext }

    /// The ownership view model on the test's owner store.
    private func ownershipModel(_ owner: LocalDataOwner) -> LocalDataOwnershipViewModel {
        let ownership = LocalDataOwnershipViewModel()
        ownership.owner = owner
        return ownership
    }

    private func freshOwner() -> LocalDataOwner {
        LocalDataOwner(defaults: ThrowawayDefaults("SignInBackupTests"))
    }

    /// Signed out, with the test's own owner store.
    private func signedOutAuth(_ owner: LocalDataOwner) -> AuthService {
        let auth = AuthService(client: testClient(storage) { _, _ in .status(204, "") })
        auth.localDataOwner = owner
        return auth
    }

    private func signIn(_ auth: AuthService) {
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        auth.restoreSession()
    }

    /// An AuthService whose backup requests go to `server` and succeed.
    private func appPathAuth(_ owner: LocalDataOwner, server: FakeServer) -> AuthService {
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
        return auth
    }

    private func uploads(_ server: FakeServer) -> [String] {
        server.requests.map(\.path).filter { $0.hasPrefix("/storage/v1/object/backups/") }
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
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let auth = signedOutAuth(owner)
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
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        #expect(auth.isBackupPending, "Backup must be scheduled before waiting for completion")
        await waitUntil("sign-in backup finished") { !auth.isBackupPending }
        #expect(!auth.hasUnsentChanges)

        // A second sign-in event with nothing new to send runs nothing.
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events == ["session backup started", "sign-in backup"])
    }

    @Test func sameOwner_sessionEndedWhileSignedOut_backsUpOnceAtSignIn() async throws {
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let auth = signedOutAuth(owner)
        try endSessionWhileSignedOut(auth)

        signIn(auth)
        let log = Log()
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        #expect(auth.isBackupPending, "Backup must be scheduled before waiting for completion")
        await waitUntil("sign-in backup finished") { !auth.isBackupPending }
        #expect(log.count("sign-in backup") == 1)
        #expect(!auth.hasUnsentChanges)
    }

    /// #300: the app is killed after a session ended while signed out. A new
    /// AuthService on the same device (the relaunch) still backs up at sign-in.
    @Test func sameOwner_relaunchBeforeSignIn_stillBacksUpAtSignIn() async throws {
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        try endSessionWhileSignedOut(signedOutAuth(owner))

        let relaunched = signedOutAuth(owner)
        #expect(relaunched.hasUnsentChanges)
        signIn(relaunched)
        let log = Log()
        relaunched.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        #expect(relaunched.isBackupPending, "Backup must be scheduled before waiting for completion")
        await waitUntil("sign-in backup finished") { !relaunched.isBackupPending }
        #expect(log.count("sign-in backup") == 1)
        #expect(!relaunched.hasUnsentChanges)
        #expect(!owner.hasUnsentChanges)
    }

    /// A failed backup leaves the changes unsent across a relaunch too.
    @Test func failedBackup_staysUnsentAfterRelaunch() async {
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let auth = signedOutAuth(owner)
        signIn(auth)
        auth.scheduleBackup { throw URLError(.notConnectedToInternet) }
        #expect(auth.isBackupPending, "Backup must be scheduled before waiting for completion")
        await waitUntil("backup failed") { !auth.isBackupPending }

        #expect(signedOutAuth(owner).hasUnsentChanges)
    }

    /// Without this change nothing backed up at sign-in; with nothing
    /// unsent, that stays true.
    @Test func sameOwner_nothingUnsent_noBackupAtSignIn() async {
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let auth = signedOutAuth(owner)
        signIn(auth)
        let log = Log()
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
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
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let server = FakeServer()
        let auth = appPathAuth(owner, server: server)
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        context.insert(Session(location: "Played while signed out"))
        try context.save()
        auth.scheduleBackup(modelContext: context) // signed out: the session's backup can't run
        #expect(auth.hasUnsentChanges)
        #expect(server.requests.isEmpty)

        signIn(auth)
        auth.backUpUnsentChangesAtSignIn(modelContext: context)
        #expect(auth.isBackupPending, "Backup must be scheduled before waiting for completion")
        await waitUntil("sign-in backup finished") { !auth.isBackupPending }
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
        let owner = freshOwner()
        owner.adopt(otherAccount)
        let auth = signedOutAuth(owner)
        try endSessionWhileSignedOut(auth)

        signIn(auth)
        #expect(owner.resolve(signedIn: TestUser.id, storeIsEmpty: false) == .needsChoice) // the owner check
        let log = Log()
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events.isEmpty)
        #expect(auth.backupStatus == nil)
        #expect(owner.ownerId == otherAccount)
        #expect(auth.hasUnsentChanges) // still owed to the owner
    }

    /// #311: the app's path never uploads another account's data at
    /// sign-in, even with changes unsent and a store full of its sessions.
    @Test func anotherAccountOwnsTheData_signInSequence_uploadsNothing() async throws {
        let otherAccount = UUID()
        let owner = freshOwner()
        owner.adopt(otherAccount)
        let server = FakeServer()
        let auth = appPathAuth(owner, server: server)
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        context.insert(Session(location: "Another account's session"))
        try context.save()
        auth.scheduleBackup(modelContext: context) // signed out
        #expect(auth.hasUnsentChanges)

        signIn(auth)
        let ownership = ownershipModel(owner)
        ownership.signedIn(TestUser.id, modelContext: context, authService: auth)
        for _ in 0..<20 { await Task.yield() }

        #expect(ownership.isShowingChoice)
        #expect(!auth.isBackupPending)
        #expect(uploads(server).isEmpty)
        #expect(owner.ownerId == otherAccount)
        #expect(auth.hasUnsentChanges)
    }

    /// #311: data with no owner (Delete All Data cleared it, or never signed
    /// in) is adopted by the owner check at sign-in, then backed up once.
    @Test func noOwner_adoptedAtSignIn_backsUpOnce() async throws {
        let owner = freshOwner()
        let auth = signedOutAuth(owner)
        try endSessionWhileSignedOut(auth)

        signIn(auth)
        let log = Log()
        // Before the owner check nothing runs: the data isn't this account's yet.
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events.isEmpty)

        #expect(owner.resolve(signedIn: TestUser.id, storeIsEmpty: false) == .owned) // the owner check adopts it
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        #expect(auth.isBackupPending, "Backup must be scheduled before waiting for completion")
        await waitUntil("sign-in backup finished") { log.count("sign-in backup") == 1 && !auth.isBackupPending }
        #expect(!auth.hasUnsentChanges)

        // A repeated sign-in event runs nothing more.
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(log.count("sign-in backup") == 1)
    }

    /// #311, the app's path: the adopted store uploads once, to the signed-in
    /// account's folder. #326: through the sign-in sequence, so it fails if the
    /// backup runs before the owner check (no owner yet, so nothing would upload).
    @Test func noOwner_signInSequence_uploadsTheAdoptedStoreOnce() async throws {
        let owner = freshOwner()
        let server = FakeServer()
        let auth = appPathAuth(owner, server: server)
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        context.insert(Session(location: "Played before signing in"))
        try context.save()
        auth.scheduleBackup(modelContext: context) // signed out

        signIn(auth)
        let ownership = ownershipModel(owner)
        ownership.signedIn(TestUser.id, modelContext: context, authService: auth)
        #expect(auth.isBackupPending)
        await waitUntil("sign-in backup finished") { !auth.isBackupPending }
        ownership.signedIn(TestUser.id, modelContext: context, authService: auth) // a repeated sign-in event
        for _ in 0..<20 { await Task.yield() }

        let paths = uploads(server)
        #expect(paths.count == 1)
        let path = try #require(paths.first).removingPercentEncoding ?? ""
        #expect(path.hasPrefix("/storage/v1/object/backups/\(TestUser.id.uuidString.lowercased())/"))
        #expect(owner.ownerId == TestUser.id)
        #expect(!auth.hasUnsentChanges)
    }

    /// An empty store isn't uploaded at sign-in, so the auto-restore that
    /// runs for an empty store never races an empty backup (#311).
    @Test func emptyStore_signInSequence_noBackupAtSignIn() async throws {
        let owner = freshOwner()
        let server = FakeServer()
        let auth = appPathAuth(owner, server: server)
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        auth.scheduleBackup(modelContext: context) // signed out
        #expect(auth.hasUnsentChanges)

        signIn(auth)
        ownershipModel(owner).signedIn(TestUser.id, modelContext: context, authService: auth)
        for _ in 0..<20 { await Task.yield() }

        #expect(owner.ownerId == TestUser.id)
        #expect(!auth.isBackupPending)
        #expect(uploads(server).isEmpty)
        #expect(auth.hasUnsentChanges)
    }

    /// #326: the test overload checks the store too, so an empty store
    /// skips the supplied backup and keeps the flag.
    @Test func emptyStore_suppliedBackup_doesNotRun() async throws {
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let auth = signedOutAuth(owner)
        try endSessionWhileSignedOut(auth)
        let empty = try TestHelpers.createContainer()

        signIn(auth)
        let log = Log()
        auth.backUpUnsentChangesAtSignIn(modelContext: empty.mainContext) {
            log.events.append("sign-in backup")
            return metadata()
        }
        for _ in 0..<20 { await Task.yield() }

        #expect(log.events.isEmpty)
        #expect(!auth.isBackupPending)
        #expect(auth.hasUnsentChanges)
    }

    // MARK: - Deletion pending: no backup

    @Test func accountDeletionRunning_noBackupAtSignIn_norAfterItStops() async throws {
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let auth = signedOutAuth(owner)
        try endSessionWhileSignedOut(auth)
        signIn(auth)

        await auth.suspendBackups()
        let log = Log()
        auth.backUpUnsentChangesAtSignIn(modelContext: context) {
            log.events.append("sign-in backup")
            return metadata()
        }
        auth.resumeBackups()
        for _ in 0..<20 { await Task.yield() }
        #expect(log.events.isEmpty)
        #expect(auth.backupStatus == nil)
    }

    @Test func finishedAccountDeletion_leavesNothingUnsent() async {
        let owner = freshOwner()
        owner.adopt(TestUser.id)
        let auth = signedOutAuth(owner)
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
