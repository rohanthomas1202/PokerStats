import Foundation
import SwiftData
import Testing
@testable import PokerStats

private struct ServerDown: Error {}
private struct InjectedSaveFailure: Error {}

@MainActor
private final class EventLog {
    var events: [String] = []
}

private func metadata() -> BackupMetadata {
    BackupMetadata(
        id: UUID(), userId: UUID(), storagePath: "p", fileSizeBytes: 1,
        schemaVersion: 1, sessionCount: 1, handCount: 0, createdAt: .now
    )
}

@Suite("Account Deletion Cleanup Tests", .timeLimit(.minutes(1)))
@MainActor
struct AccountDeletionCleanupTests {

    // MARK: - Fixtures

    /// Two sessions (3 hands) and settings, all saved.
    private func seededContainer() throws -> ModelContainer {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let a = Session(location: "A", status: .completed, buyIn: 100)
        let b = Session(location: "B", status: .completed, buyIn: 200)
        context.insert(a)
        context.insert(b)
        for (number, session) in [(1, a), (2, a), (1, b)] {
            let hand = TestHelpers.foldHand(number: number)
            hand.session = session
            context.insert(hand)
        }
        context.insert(Settings(defaultStakes: "2/5", defaultBuyIn: 500))
        try context.save()
        return container
    }

    private func counts(_ context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<Session>()),
            try context.fetchCount(FetchDescriptor<Hand>()),
            try context.fetchCount(FetchDescriptor<Settings>()),
        ]
    }

    /// An `AuthService` signed in as `TestUser` on an in-memory session
    /// store, so deletion's local sign-out never touches the real Keychain.
    private func signedInAuth() -> AuthService {
        let storage = InMemoryAuthStorage()
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        let auth = AuthService(client: testClient(storage) { _, _ in .status(204, "") })
        auth.restoreSession()
        return auth
    }

    /// Starts a backup that runs until cancelled, and waits until it is in flight.
    private func startEndlessBackup(_ auth: AuthService, log: EventLog) async {
        auth.scheduleBackup {
            log.events.append("backup started")
            defer { log.events.append("backup stopped") }
            try await Task.sleep(for: .seconds(60))
            return metadata()
        }
        await waitUntil("backup started") { log.events.contains("backup started") }
    }

    /// Cloud work that runs until cancelled, then (like a download that has
    /// already returned) finishes anyway with `payload`.
    private func ignoresCancellation(_ log: EventLog, _ name: String) async -> BackupPayload {
        log.events.append("\(name) started")
        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        log.events.append("\(name) stopped")
        return payload()
    }

    private func payload() -> BackupPayload {
        let session = SessionDTO(
            id: UUID(), startTime: .now, endTime: .now, location: "From Deleted Account",
            gameType: "cash", stakes: "1/3", notes: "", status: "completed",
            buyIn: 300, rebuys: 0, addOns: 0, cashOut: 450, tipRake: 0,
            tiltLevel: nil, energyLevel: nil, focusLevel: nil,
            tableConfigJson: nil, hands: []
        )
        return BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion, createdAt: .now,
            appVersion: "1.0.0", sessions: [session], settings: nil
        )
    }

    private func locations(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<Session>()).map(\.location).sorted()
    }

    // MARK: - Local wipe

    @Test func wipe_removesSessionsHandsAndSettings() throws {
        let container = try seededContainer()
        let context = container.mainContext
        #expect(try counts(context) == [2, 3, 1])

        try LocalDataWiper(modelContext: context).wipe()

        #expect(try counts(context) == [0, 0, 0])
        #expect(!context.hasChanges)
    }

    @Test func wipe_failedSave_leavesLocalDataIntact() throws {
        let container = try seededContainer()
        let context = container.mainContext
        var wiper = LocalDataWiper(modelContext: context)
        wiper.save = { _ in throw InjectedSaveFailure() }

        #expect(throws: InjectedSaveFailure.self) { try wiper.wipe() }
        #expect(try counts(context) == [2, 3, 1])
    }

    @Test func settingsViewModel_wipeAfterAccountDeletion_clearsStoreAndResetsFields() throws {
        let container = try seededContainer()
        let context = container.mainContext
        let vm = SettingsViewModel()
        vm.loadSettings(from: context)
        #expect(vm.defaultBuyIn == "500")

        vm.wipeAfterAccountDeletion(from: context)

        #expect(try counts(context) == [0, 0, 0])
        #expect(vm.defaultBuyIn == "200")
        #expect(vm.defaultStakes == "1/2")
        #expect(vm.defaultGameType == .cash)
    }

    // MARK: - Pending backup

    @Test func deletion_stopsInFlightBackup_beforeServerDelete() async throws {
        let auth = signedInAuth()
        let log = EventLog()
        await startEndlessBackup(auth, log: log)

        try await auth.deleteAccount(serverDelete: { log.events.append("server delete") })

        #expect(log.events == ["backup started", "backup stopped", "server delete"])
        #expect(auth.backupStatus == nil) // a cancelled backup reports nothing
    }

    @Test func noBackupStartsWhileServerDeleteRuns() async throws {
        let auth = signedInAuth()
        let log = EventLog()

        try await auth.deleteAccount(serverDelete: {
            auth.scheduleBackup {
                log.events.append("backup ran")
                return metadata()
            }
            for _ in 0..<20 { await Task.yield() }
            log.events.append("server delete")
        })
        for _ in 0..<20 { await Task.yield() }

        #expect(log.events == ["server delete"])
    }

    @Test func backupsResumeAfterDeletion_succeedsOrFails() async throws {
        for fails in [false, true] {
            let auth = signedInAuth()
            let log = EventLog()
            _ = try? await auth.deleteAccount(serverDelete: { if fails { throw ServerDown() } })

            auth.scheduleBackup {
                log.events.append("backup ran")
                return metadata()
            }
            await waitUntil("backup ran") { log.events.contains("backup ran") }
            #expect(log.events == ["backup ran"], "fails: \(fails)")
        }
    }

    @Test func serverFailure_propagatesAsDeletionFailed() async {
        let auth = signedInAuth()
        await #expect(throws: AuthServiceError.self) {
            try await auth.deleteAccount(serverDelete: { throw ServerDown() })
        }
        #expect(!auth.isLoading)
    }

    @Test func replacedBackup_doesNotReportFailure() async {
        let auth = signedInAuth()
        let log = EventLog()
        await startEndlessBackup(auth, log: log)

        auth.scheduleBackup {
            log.events.append("second backup")
            return metadata()
        }
        await waitUntil("second backup reported") {
            log.events.contains("backup stopped") && auth.backupStatus?.hasPrefix("Backed up") == true
        }
        #expect(auth.backupStatus == "Backed up 1 sessions")
    }

    // MARK: - Whole flow: Settings' delete account

    @Test func success_cancelsBackup_deletesOnServer_thenWipesLocalData() async throws {
        let container = try seededContainer()
        let context = container.mainContext
        let auth = signedInAuth()
        let log = EventLog()
        await startEndlessBackup(auth, log: log)
        #expect(auth.isAuthenticated)
        let settings = SettingsViewModel()
        let vm = AuthViewModel(authService: auth, performDeleteAccount: {
            try await auth.deleteAccount(serverDelete: {
                let before = try counts(context)
                #expect(before == [2, 3, 1]) // nothing wiped yet
                log.events.append("server delete")
            })
        })

        await vm.deleteAccount {
            log.events.append("local wipe")
            settings.wipeAfterAccountDeletion(from: context)
        }.value

        #expect(log.events == ["backup started", "backup stopped", "server delete", "local wipe"])
        #expect(try counts(context) == [0, 0, 0])
        #expect(!auth.isAuthenticated)
        #expect(vm.deleteAccountFailure == nil)
    }

    @Test func serverFailure_keepsLocalData_andShowsError() async throws {
        let container = try seededContainer()
        let context = container.mainContext
        let auth = signedInAuth()
        let wiped = EventLog()
        let vm = AuthViewModel(authService: auth, performDeleteAccount: {
            try await auth.deleteAccount(serverDelete: { throw ServerDown() })
        })

        await vm.deleteAccount {
            wiped.events.append("wiped")
            SettingsViewModel().wipeAfterAccountDeletion(from: context)
        }.value

        #expect(wiped.events.isEmpty)
        #expect(try counts(context) == [2, 3, 1])
        #expect(vm.deleteAccountFailure == .retryable)
    }

    // MARK: - Manual backup and restores in flight (#61)

    @Test func deletion_stopsManualBackup_beforeServerDelete() async throws {
        let auth = signedInAuth()
        let log = EventLog()
        let backup = Task {
            try await auth.performCloudWork {
                log.events.append("manual backup started")
                defer { log.events.append("manual backup stopped") }
                try await Task.sleep(for: .seconds(60))
                return metadata()
            }
        }
        await waitUntil("manual backup started") { log.events.contains("manual backup started") }

        try await auth.deleteAccount(serverDelete: { log.events.append("server delete") })

        #expect(log.events == ["manual backup started", "manual backup stopped", "server delete"])
        await #expect(throws: CancellationError.self) { try await backup.value }
    }

    @Test func backUpNow_goesThroughTheSuspendCheck() async throws {
        let auth = signedInAuth()
        let log = EventLog()
        let vm = BackupViewModel()
        vm.configure(BackupViewModel.Actions(
            isSignedIn: { auth.isAuthenticated },
            listBackups: { [] },
            createBackup: {
                try await auth.performCloudWork {
                    log.events.append("uploaded")
                    return metadata()
                }
            },
            downloadBackup: { _ in throw ServerDown() },
            restoreBackup: { _ in }
        ))

        _ = try? await auth.deleteAccount(serverDelete: {
            await vm.createBackup()
            throw ServerDown()
        })

        #expect(log.events.isEmpty)
        #expect(vm.errorMessage == nil) // stopped by the deletion, not an error
    }

    @Test func autoRestoreInFlight_isStopped_andWritesNothing() async throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let auth = signedInAuth()
        let log = EventLog()
        let flag = freshFlag()
        let restore = AutoRestore(
            modelContext: context,
            listBackups: { [metadata()] },
            downloadBackup: { _ in await ignoresCancellation(log, "download") },
            flag: flag,
            checkCanWrite: { try auth.checkRestoreCanWrite() }
        )
        let banner = AutoRestoreViewModel()
        let run = banner.start(isSignedIn: { auth.isAuthenticated }) {
            try await auth.performCloudWork { try await restore.run() }
        }
        await waitUntil("download started") { log.events.contains("download started") }

        // The deletion fails, so the user stays signed in with their data.
        _ = try? await auth.deleteAccount(serverDelete: {
            log.events.append("server delete")
            throw ServerDown()
        })
        await run.value

        #expect(log.events == ["download started", "download stopped", "server delete"])
        #expect(try locations(context).isEmpty)
        #expect(!flag.isSet) // the next launch tries again
        #expect(banner.status == nil) // no failure banner for a stop by deletion
    }

    @Test func manualRestoreInFlight_isStopped_andWritesNothing() async throws {
        let container = try seededContainer()
        let context = container.mainContext
        let auth = signedInAuth()
        let log = EventLog()
        let owner = LocalDataOwner(defaults: UserDefaults(suiteName: "AccountDeletionCleanupTests.\(UUID().uuidString)")!)
        let service = BackupService(authService: auth, modelContext: context, owner: owner)
        let vm = BackupViewModel()
        vm.configure(BackupViewModel.Actions(
            isSignedIn: { auth.isAuthenticated },
            listBackups: { [] },
            createBackup: { metadata() },
            downloadBackup: { _ in
                try await auth.performCloudWork { await ignoresCancellation(log, "download") }
            },
            restoreBackup: { try service.restoreBackup($0) }
        ))
        let backup = metadata()
        vm.initiateRestore(backup: backup)
        let restore = Task { await vm.confirmRestore() }
        await waitUntil("download started") { log.events.contains("download started") }

        _ = try? await auth.deleteAccount(serverDelete: {
            log.events.append("server delete")
            throw ServerDown()
        })
        await restore.value

        #expect(log.events == ["download started", "download stopped", "server delete"])
        #expect(try counts(context) == [2, 3, 1])
        #expect(try locations(context) == ["A", "B"])
        #expect(vm.errorMessage == nil)
        #expect(vm.successMessage == nil)
        #expect(!vm.isRestoring)
    }

    @Test func restoreWrite_refusesWhileDeletionRuns_orSignedOut() async throws {
        let container = try seededContainer()
        let context = container.mainContext
        let auth = signedInAuth()
        let owner = LocalDataOwner(defaults: UserDefaults(suiteName: "AccountDeletionCleanupTests.\(UUID().uuidString)")!)
        let service = BackupService(authService: auth, modelContext: context, owner: owner)

        try await auth.deleteAccount(serverDelete: {
            #expect(throws: CancellationError.self) { try service.restoreBackup(payload()) }
            await #expect(throws: CancellationError.self) {
                _ = try await auth.performCloudWork { metadata() }
            }
        })

        // Deleted and signed out: still refused.
        #expect(!auth.isAuthenticated)
        #expect(throws: SupabaseError.self) { try service.restoreBackup(payload()) }
        await #expect(throws: BackupError.self) {
            _ = try await auth.performCloudWork { metadata() }
        }
        #expect(try locations(context) == ["A", "B"])
        #expect(UserFacingError(SupabaseError.sessionChanged).message(for: .restore, isSignedIn: false)
            == UserFacingError.sessionChangedSignedOutMessage)
    }

    // MARK: - Re-entrancy (#61)

    @Test func suspendNests_andOnlyTheLastResumeEndsIt() async {
        let auth = signedInAuth()

        await auth.suspendBackups()
        await auth.suspendBackups()
        auth.resumeBackups()
        #expect(auth.isCloudWorkSuspended)
        auth.resumeBackups()
        #expect(!auth.isCloudWorkSuspended)
        auth.resumeBackups() // an extra resume doesn't go below zero
        await auth.suspendBackups()
        #expect(auth.isCloudWorkSuspended)
    }

    @Test func secondDeleteRequest_whileOneRuns_startsNothing() async {
        let auth = signedInAuth()
        let calls = EventLog()
        let vm = AuthViewModel(authService: auth, performDeleteAccount: {
            calls.events.append("delete")
            try await Task.sleep(for: .milliseconds(50))
        })

        let first = vm.deleteAccount()
        let second = vm.deleteAccount()
        await first.value
        await second.value

        #expect(calls.events == ["delete"])
        #expect(!vm.isDeletingAccount)

        // Once it has finished, a new request runs again.
        await vm.deleteAccount().value
        #expect(calls.events == ["delete", "delete"])
    }

    // MARK: - Dropped backup runs again (#61)

    @Test func backupStoppedByDeletion_runsAgain_whenDeletionFailsOrIsCancelled() async throws {
        let failures: [any Error] = [ServerDown(), AccountDeletionError.reauthenticationCancelled]
        for failure in failures {
            let auth = signedInAuth()
            let log = EventLog()
            auth.scheduleBackup {
                log.events.append("backup started")
                if log.events.filter({ $0 == "backup started" }).count == 1 {
                    // The first run is in flight when the deletion starts.
                    try await Task.sleep(for: .seconds(60))
                }
                return metadata()
            }
            await waitUntil("backup started") { log.events.contains("backup started") }

            _ = try? await auth.deleteAccount(serverDelete: { throw failure })

            await waitUntil("backup ran again") { auth.backupStatus == "Backed up 1 sessions" }
            #expect(log.events == ["backup started", "backup started"], "\(failure)")
        }
    }

    @Test func backupHeldDuringDeletion_runsAfterAFailedDeletion() async throws {
        let auth = signedInAuth()
        let log = EventLog()

        _ = try? await auth.deleteAccount(serverDelete: {
            auth.scheduleBackup {
                log.events.append("backup ran")
                return metadata()
            }
            for _ in 0..<20 { await Task.yield() }
            #expect(log.events.isEmpty)
            throw ServerDown()
        })

        await waitUntil("held backup ran") { log.events.contains("backup ran") }
        #expect(log.events == ["backup ran"])
    }

    @Test func backupStoppedByDeletion_doesNotRunAgain_afterSuccess() async throws {
        let auth = signedInAuth()
        let log = EventLog()
        await startEndlessBackup(auth, log: log)

        try await auth.deleteAccount(serverDelete: { log.events.append("server delete") })
        for _ in 0..<20 { await Task.yield() }

        #expect(log.events == ["backup started", "backup stopped", "server delete"])
        #expect(auth.backupStatus == nil)
    }
}
