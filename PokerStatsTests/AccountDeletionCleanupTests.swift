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

@Suite("Account Deletion Cleanup Tests")
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

    /// Starts a backup that runs until cancelled, and waits until it is in flight.
    private func startEndlessBackup(_ auth: AuthService, log: EventLog) async {
        auth.scheduleBackup {
            log.events.append("backup started")
            defer { log.events.append("backup stopped") }
            try await Task.sleep(for: .seconds(60))
            return metadata()
        }
        while !log.events.contains("backup started") { await Task.yield() }
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
        let auth = AuthService()
        let log = EventLog()
        await startEndlessBackup(auth, log: log)

        try await auth.deleteAccount(serverDelete: { log.events.append("server delete") })

        #expect(log.events == ["backup started", "backup stopped", "server delete"])
        #expect(auth.backupStatus == nil) // a cancelled backup reports nothing
    }

    @Test func noBackupStartsWhileServerDeleteRuns() async throws {
        let auth = AuthService()
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
            let auth = AuthService()
            let log = EventLog()
            _ = try? await auth.deleteAccount(serverDelete: { if fails { throw ServerDown() } })

            auth.scheduleBackup {
                log.events.append("backup ran")
                return metadata()
            }
            while !log.events.contains("backup ran") { await Task.yield() }
            #expect(log.events == ["backup ran"], "fails: \(fails)")
        }
    }

    @Test func serverFailure_propagatesAsDeletionFailed() async {
        let auth = AuthService()
        await #expect(throws: AuthServiceError.self) {
            try await auth.deleteAccount(serverDelete: { throw ServerDown() })
        }
        #expect(!auth.isLoading)
    }

    @Test func replacedBackup_doesNotReportFailure() async {
        let auth = AuthService()
        let log = EventLog()
        await startEndlessBackup(auth, log: log)

        auth.scheduleBackup {
            log.events.append("second backup")
            return metadata()
        }
        while !log.events.contains("backup stopped") || auth.backupStatus?.hasPrefix("Backed up") != true {
            await Task.yield()
        }
        #expect(auth.backupStatus == "Backed up 1 sessions")
    }

    // MARK: - Whole flow: Settings' delete account

    @Test func success_cancelsBackup_deletesOnServer_thenWipesLocalData() async throws {
        let container = try seededContainer()
        let context = container.mainContext
        let auth = AuthService()
        let log = EventLog()
        await startEndlessBackup(auth, log: log)
        let settings = SettingsViewModel()
        let vm = AuthViewModel(authService: auth, performDeleteAccount: {
            try await auth.deleteAccount(serverDelete: {
                #expect(try counts(context) == [2, 3, 1]) // nothing wiped yet
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
        let auth = AuthService()
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
}
