import Foundation
import SwiftData
import Testing
@testable import PokerStats

/// Which account owns the local stats, and the choice when a different
/// account signs in (#69). Account B is `TestUser`, the account with a test
/// session; account A is another id.
@Suite("Local Data Owner Tests")
@MainActor
struct LocalDataOwnerTests {
    private let accountA = UUID()
    private let accountB = TestUser.id
    private let owner: LocalDataOwner
    private let container: ModelContainer

    init() throws {
        owner = LocalDataOwner(defaults: UserDefaults(suiteName: "LocalDataOwnerTests.\(UUID().uuidString)")!)
        container = try TestHelpers.createContainer()
    }

    // MARK: - Helpers

    private var context: ModelContext { container.mainContext }

    private func addSession(_ location: String) throws {
        let session = Session(location: location)
        context.insert(session)
        let hand = TestHelpers.foldHand()
        hand.session = session
        context.insert(hand)
        try context.save()
    }

    private func storedLocations() throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<Session>()).map(\.location).sorted()
    }

    private func viewModel() -> LocalDataOwnershipViewModel {
        let viewModel = LocalDataOwnershipViewModel()
        viewModel.owner = owner
        viewModel.afterAlertDismisses = { $0() }
        return viewModel
    }

    /// Account A used the app, then signed out; account B signs in.
    private func accountBSignsInOverAccountAData() throws -> LocalDataOwnershipViewModel {
        let viewModel = viewModel()
        viewModel.signedIn(accountA, modelContext: context)
        try addSession("A's session")
        viewModel.signedOut()
        viewModel.signedIn(accountB, modelContext: context)
        return viewModel
    }

    /// An `AuthService` signed in as account B, whose requests go to `server`.
    private func signedInAuthService(server: FakeServer) -> (AuthService, SupabaseClient) {
        let storage = InMemoryAuthStorage()
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        let client = testClient(storage, server: server) { request, _ in
            switch (request.method, request.path) {
            case ("POST", let path) where path.hasPrefix("/storage/v1/object/backups/"):
                return .status(200, #"{"Key":"backups/x","Id":"1"}"#)
            case ("POST", "/rest/v1/backup_metadata"):
                return .status(201, """
                [{"id":"\(UUID().uuidString)","user_id":"\(TestUser.id.uuidString)","storage_path":"p",
                  "file_size_bytes":1,"schema_version":1,"session_count":1,"hand_count":1,
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
        return (auth, client)
    }

    private func uploads(_ server: FakeServer) -> [SeenRequest] {
        server.requests.filter { $0.path.hasPrefix("/storage/v1/object/backups/") }
    }

    // MARK: - Ownership rules

    @Test func firstSignIn_withNoOwner_adoptsTheData_andAsksNothing() throws {
        try addSession("Before any account")
        let viewModel = viewModel()

        viewModel.signedIn(accountB, modelContext: context)

        #expect(owner.ownerId == accountB)
        #expect(!viewModel.isShowingChoice)
        #expect(!viewModel.backupsBlocked)
    }

    @Test func sameAccountSigningBackIn_isUnchanged() throws {
        let viewModel = viewModel()
        viewModel.signedIn(accountA, modelContext: context)
        try addSession("A's session")
        viewModel.signedOut()

        viewModel.signedIn(accountA, modelContext: context)

        #expect(owner.ownerId == accountA)
        #expect(!viewModel.isShowingChoice)
        #expect(!viewModel.backupsBlocked)
        #expect(owner.allowsUpload(for: accountA))
    }

    @Test func differentAccount_withEmptyStore_adoptsIt_andAsksNothing() throws {
        let viewModel = viewModel()
        viewModel.signedIn(accountA, modelContext: context)
        viewModel.signedOut()

        viewModel.signedIn(accountB, modelContext: context)

        #expect(owner.ownerId == accountB)
        #expect(!viewModel.isShowingChoice)
    }

    @Test func differentAccount_withLocalData_asks_andBlocksUploads() throws {
        let viewModel = try accountBSignsInOverAccountAData()

        #expect(viewModel.isShowingChoice)
        #expect(viewModel.backupsBlocked)
        #expect(owner.ownerId == accountA)
        #expect(!owner.allowsUpload(for: accountB))
        #expect(try storedLocations() == ["A's session"])
    }

    // MARK: - No upload before the choice

    @Test func noUploadHappens_beforeTheChoice() async throws {
        let viewModel = try accountBSignsInOverAccountAData()
        #expect(viewModel.isShowingChoice)
        let server = FakeServer()
        let (auth, client) = signedInAuthService(server: server)
        #expect(auth.userId == accountB)

        // The automatic backup after a session ends doesn't start.
        auth.scheduleBackup(modelContext: context)
        #expect(auth.backupStatus == nil)

        // A direct backup (Back Up Now) is refused before any request.
        let service = BackupService(authService: auth, modelContext: context, client: client, owner: owner)
        await #expect(throws: BackupError.self) {
            _ = try await service.createAndUploadBackup()
        }
        #expect(server.requests.isEmpty)
        #expect(UserFacingError(BackupError.dataFromAnotherAccount) == .dataFromAnotherAccount)
        #expect(!UserFacingError.dataFromAnotherAccount.isRetryable)
    }

    // MARK: - Each choice

    @Test func backUpToThisAccount_adoptsTheData_andBacksUp() async throws {
        let viewModel = try accountBSignsInOverAccountAData()
        var backUpCalls = 0

        viewModel.backUpToThisAccount { backUpCalls += 1 }

        #expect(backUpCalls == 1)
        #expect(owner.ownerId == accountB)
        #expect(!viewModel.isShowingChoice)
        #expect(!viewModel.backupsBlocked)
        #expect(try storedLocations() == ["A's session"])

        // The upload now goes to account B's folder.
        let server = FakeServer()
        let (auth, client) = signedInAuthService(server: server)
        let service = BackupService(authService: auth, modelContext: context, client: client, owner: owner)
        let metadata = try await service.createAndUploadBackup()
        #expect(metadata.sessionCount == 1)
        let upload = try #require(uploads(server).first)
        let path = upload.path.removingPercentEncoding ?? upload.path
        #expect(path.hasPrefix("/storage/v1/object/backups/\(accountB.uuidString.lowercased())/"))
    }

    @Test func keepOnThisDeviceOnly_keepsTheData_andNeverUploads() async throws {
        let viewModel = try accountBSignsInOverAccountAData()

        viewModel.keepOnThisDeviceOnly()

        #expect(!viewModel.isShowingChoice)
        #expect(viewModel.backupsBlocked)
        #expect(owner.ownerId == accountA)
        #expect(try storedLocations() == ["A's session"])

        let server = FakeServer()
        let (auth, client) = signedInAuthService(server: server)
        auth.scheduleBackup(modelContext: context)
        #expect(auth.backupStatus == nil)
        let service = BackupService(authService: auth, modelContext: context, client: client, owner: owner)
        await #expect(throws: BackupError.self) {
            _ = try await service.createAndUploadBackup()
        }
        #expect(server.requests.isEmpty)

        // B signing in again keeps the choice and doesn't ask again.
        viewModel.signedOut()
        viewModel.signedIn(accountB, modelContext: context)
        #expect(!viewModel.isShowingChoice)
        #expect(viewModel.backupsBlocked)

        // Choose What to Do in Cloud Backup asks again.
        viewModel.showChoice()
        #expect(viewModel.isShowingChoice)
    }

    @Test func keepOnThisDeviceOnly_thenAccountASignsBackIn_isUnchanged() throws {
        let viewModel = try accountBSignsInOverAccountAData()
        viewModel.keepOnThisDeviceOnly()
        viewModel.signedOut()

        viewModel.signedIn(accountA, modelContext: context)

        #expect(!viewModel.isShowingChoice)
        #expect(!viewModel.backupsBlocked)
        #expect(owner.ownerId == accountA)
        #expect(owner.localOnlyUserId == nil)
    }

    @Test func deleteFromThisDevice_asksToConfirm_thenDeletesEverything() throws {
        let viewModel = try accountBSignsInOverAccountAData()
        context.insert(Settings())
        try context.save()

        viewModel.requestDelete()
        #expect(!viewModel.isShowingChoice)
        #expect(viewModel.isShowingDeleteConfirmation)
        #expect(try storedLocations() == ["A's session"])

        viewModel.confirmDelete(modelContext: context)

        #expect(try storedLocations().isEmpty)
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<Hand>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Settings>()) == 0)
        #expect(owner.ownerId == accountB)
        #expect(!viewModel.backupsBlocked)
        #expect(!viewModel.isShowingChoice)
        #expect(!viewModel.isShowingDeleteConfirmation)
    }

    @Test func cancellingDelete_returnsToTheChoice_andKeepsTheData() throws {
        let viewModel = try accountBSignsInOverAccountAData()

        viewModel.requestDelete()
        viewModel.cancelDelete()

        #expect(viewModel.isShowingChoice)
        #expect(viewModel.backupsBlocked)
        #expect(try storedLocations() == ["A's session"])
    }

    // MARK: - Presentation

    @Test func choiceWaitsForTheSignInSheetToClose() throws {
        let viewModel = viewModel()
        viewModel.signedIn(accountA, modelContext: context)
        try addSession("A's session")
        viewModel.signedOut()

        viewModel.deferPrompt()
        viewModel.signedIn(accountB, modelContext: context)
        #expect(!viewModel.isShowingChoice)
        #expect(viewModel.backupsBlocked)

        viewModel.resumePrompt()
        #expect(viewModel.isShowingChoice)
    }

    /// "Delete from This iPhone" closes the choice; the confirmation waits
    /// until that alert has dismissed, so SwiftUI doesn't drop it (#262).
    @Test func deleteConfirmation_waitsForTheChoiceToDismiss() throws {
        let viewModel = try accountBSignsInOverAccountAData()
        var pending: [@MainActor @Sendable () -> Void] = []
        viewModel.afterAlertDismisses = { pending.append($0) }

        viewModel.requestDelete()
        #expect(!viewModel.isShowingChoice)
        #expect(!viewModel.isShowingDeleteConfirmation)
        #expect(pending.count == 1)

        pending.removeFirst()()
        #expect(viewModel.isShowingDeleteConfirmation)
        #expect(!viewModel.isShowingChoice)

        // Cancel waits the same way before asking again.
        viewModel.cancelDelete()
        #expect(!viewModel.isShowingDeleteConfirmation)
        #expect(!viewModel.isShowingChoice)
        pending.removeFirst()()
        #expect(viewModel.isShowingChoice)
        #expect(try storedLocations() == ["A's session"])
    }

    @Test func deleteConfirmation_isDropped_whenSignedOutBeforeTheChoiceDismisses() throws {
        let viewModel = try accountBSignsInOverAccountAData()
        var pending: [@MainActor @Sendable () -> Void] = []
        viewModel.afterAlertDismisses = { pending.append($0) }

        viewModel.requestDelete()
        viewModel.signedOut()
        pending.removeFirst()()

        #expect(!viewModel.isShowingDeleteConfirmation)
        #expect(!viewModel.isShowingChoice)
    }

    // MARK: - Copy and accessibility

    @Test func choiceMessage_namesTheSignedInAccount_andTheKeptBackups() {
        let named = LocalDataOwnershipViewModel.choiceMessage(signedInAs: "b@example.com")
        #expect(named.contains("a different account than b@example.com."))
        #expect(named.contains("only the \(BackupService.keptBackupCount) newest are kept"))
        #expect(named.hasSuffix("Nothing is backed up until you choose."))

        // Sign in with Apple can leave the email unknown.
        for email in [nil, ""] as [String?] {
            let unnamed = LocalDataOwnershipViewModel.choiceMessage(signedInAs: email)
            #expect(unnamed.hasPrefix("The stats on this iPhone were saved with a different account. "))
            #expect(unnamed.contains("only the \(BackupService.keptBackupCount) newest are kept"))
        }
    }

    @Test func deleteMessage_mentionsSettings() {
        #expect(LocalDataOwnershipViewModel.deleteMessage == "This permanently deletes the sessions, hands and settings on this iPhone. Cloud backups aren't changed.")
    }

    /// While blocked, VoiceOver hears the reason with Back Up Now (#262).
    @Test func backUpNowHint_givesTheReasonOnlyWhileBlocked() throws {
        let viewModel = try accountBSignsInOverAccountAData()
        #expect(viewModel.backUpNowHint == LocalDataOwnershipViewModel.blockedMessage)

        viewModel.backUpToThisAccount {}
        #expect(viewModel.backUpNowHint.isEmpty)

        viewModel.signedOut()
        #expect(viewModel.backUpNowHint.isEmpty)
    }

    @Test func signingOut_hidesTheChoice() throws {
        let viewModel = try accountBSignsInOverAccountAData()

        viewModel.signedOut()

        #expect(!viewModel.isShowingChoice)
        #expect(!viewModel.backupsBlocked)
        viewModel.resumePrompt()
        #expect(!viewModel.isShowingChoice)
    }

    // MARK: - Backup, restore, and wipes

    @Test func backupWithNoOwner_adoptsTheData() async throws {
        try addSession("Before any account")
        let server = FakeServer()
        let (auth, client) = signedInAuthService(server: server)
        let service = BackupService(authService: auth, modelContext: context, client: client, owner: owner)

        _ = try await service.createAndUploadBackup()

        #expect(owner.ownerId == accountB)
        #expect(uploads(server).count == 1)
    }

    @Test func manualRestore_givesTheDataToTheSignedInAccount() throws {
        owner.adopt(accountA)
        owner.keepLocalOnly(for: accountB)
        try addSession("A's session")
        let (auth, client) = signedInAuthService(server: FakeServer())
        let service = BackupService(authService: auth, modelContext: context, client: client, owner: owner)
        let payload = BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion, createdAt: .now,
            appVersion: "1.0.0", sessions: [], settings: nil
        )

        try service.restoreBackup(payload)

        #expect(owner.ownerId == accountB)
        #expect(owner.localOnlyUserId == nil)
        #expect(owner.allowsUpload(for: accountB))
    }

    /// #311: a restore replaces the local store, so nothing is left unsent.
    @Test func manualRestore_clearsUnsentChanges() throws {
        owner.adopt(accountB)
        owner.hasUnsentChanges = true
        try addSession("B's unsent session")
        let (auth, client) = signedInAuthService(server: FakeServer())
        let service = BackupService(authService: auth, modelContext: context, client: client, owner: owner)
        let payload = BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion, createdAt: .now,
            appVersion: "1.0.0", sessions: [], settings: nil
        )

        try service.restoreBackup(payload)

        #expect(owner.ownerId == accountB)
        #expect(!owner.hasUnsentChanges)
    }

    /// #326: a backup that was already running when a manual restore wrote,
    /// and then failed, sets the flag again. Kept on purpose: the app can't
    /// tell whether that backup's snapshot is still covered by the restore, so a
    /// failed backup always leaves the data owed. The cost is at most one
    /// redundant upload at the next sign-in, never lost changes.
    @Test func backupFailingAfterManualRestore_leavesUnsentChangesSet() async throws {
        owner.adopt(accountB)
        try addSession("B's session")
        let (auth, client) = signedInAuthService(server: FakeServer())
        let gate = AsyncStream<Void>.makeStream()
        auth.scheduleBackup {
            for await _ in gate.stream {}
            throw URLError(.notConnectedToInternet)
        }
        #expect(!owner.hasUnsentChanges) // scheduling cleared it
        let service = BackupService(authService: auth, modelContext: context, client: client, owner: owner)
        try service.restoreBackup(BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion, createdAt: .now,
            appVersion: "1.0.0", sessions: [], settings: nil
        ))
        #expect(!owner.hasUnsentChanges)

        gate.continuation.finish()
        await waitUntil("backup failed") { !auth.isBackupPending }

        #expect(owner.hasUnsentChanges)
    }

    /// #311: when another account takes the data, the old owner's unsent
    /// changes are dropped. The same owner, or data with no owner, keeps them.
    @Test func ownerChange_clearsUnsentChanges() {
        owner.hasUnsentChanges = true
        owner.adopt(accountA) // no owner before
        #expect(owner.hasUnsentChanges)
        owner.adopt(accountA) // same owner
        #expect(owner.hasUnsentChanges)

        owner.adopt(accountB)

        #expect(owner.ownerId == accountB)
        #expect(!owner.hasUnsentChanges)
    }

    /// #311: B signs in over A's emptied store; the owner check gives B the
    /// store and A's unsent flag is cleared, so B's sign-in uploads nothing.
    @Test func signInOverAnotherAccountsEmptyStore_clearsUnsentChanges() {
        owner.adopt(accountA)
        owner.hasUnsentChanges = true

        viewModel().signedIn(accountB, modelContext: context)

        #expect(owner.ownerId == accountB)
        #expect(!owner.hasUnsentChanges)
    }

    @Test func deleteAllData_clearsTheOwner_butKeepsTheAutoRestoreFlag() throws {
        owner.adopt(accountA)
        owner.hasUnsentChanges = true
        try addSession("A's session") // has a hand (#263)
        let settings = SettingsViewModel()
        settings.localDataOwner = owner
        settings.autoRestoreFlag = freshFlag()

        settings.deleteAllData(from: context)

        #expect(try storedLocations().isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Hand>()) == 0)
        #expect(owner.ownerId == nil)
        #expect(!owner.hasUnsentChanges) // nothing left to send (#300)
        #expect(settings.autoRestoreFlag.isSet)
        #expect(settings.deleteAllDataFailure == nil)
    }

    @Test func accountDeletionWipe_clearsTheOwner_andTheAutoRestoreFlag() throws {
        owner.adopt(accountA)
        owner.hasUnsentChanges = true
        try addSession("A's session")
        let settings = SettingsViewModel()
        settings.localDataOwner = owner
        let flag = freshFlag()
        flag.set()
        settings.autoRestoreFlag = flag

        settings.wipeAfterAccountDeletion(from: context)

        #expect(owner.ownerId == nil)
        #expect(!owner.hasUnsentChanges) // the account and its backups are gone (#300)
        #expect(!flag.isSet)
        #expect(try storedLocations().isEmpty)
    }
}
