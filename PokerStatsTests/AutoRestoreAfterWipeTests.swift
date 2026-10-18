import Foundation
import SwiftData
import Testing
@testable import PokerStats

private struct ListFailed: Error {}

@MainActor
private final class Calls {
    var list = 0
    var download = 0
}

/// #49: Delete All Data must not be undone by auto-restore on a later launch.
@Suite("Auto Restore After Wipe Tests")
@MainActor
struct AutoRestoreAfterWipeTests {

    private let metadata = BackupMetadata(
        id: UUID(), userId: UUID(), storagePath: "u/backup.json.gz",
        fileSizeBytes: 100, schemaVersion: 1, sessionCount: 1, handCount: 0,
        createdAt: .now
    )

    private func payload() -> BackupPayload {
        let session = SessionDTO(
            id: UUID(), startTime: .now, endTime: .now, location: "From Backup",
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

    /// One "launch": a new AutoRestore on a fresh context of the same store,
    /// with a cloud backup available.
    private func launch(
        _ container: ModelContainer,
        flag: AutoRestoreFlag,
        calls: Calls,
        backups: Bool = true
    ) async throws -> AutoRestore.Outcome {
        try await AutoRestore(
            modelContext: ModelContext(container),
            listBackups: { [metadata] in
                calls.list += 1
                return backups ? [metadata] : []
            },
            downloadBackup: { [self] _ in
                calls.download += 1
                return payload()
            },
            flag: flag
        ).run()
    }

    private func sessionCount(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<Session>())
    }

    private func settingsViewModel(_ flag: AutoRestoreFlag) -> SettingsViewModel {
        let vm = SettingsViewModel()
        vm.autoRestoreFlag = flag
        return vm
    }

    @Test func freshInstall_emptyStore_autoRestores_andSetsFlag() async throws {
        let container = try TestHelpers.createContainer()
        let flag = freshFlag()
        let calls = Calls()

        #expect(try await launch(container, flag: flag, calls: calls) == .restored(sessionCount: 1))
        #expect(try sessionCount(container) == 1)
        #expect(flag.isSet)
    }

    @Test func deleteAllData_thenRelaunch_doesNotRestore() async throws {
        let container = try TestHelpers.createContainer()
        let flag = freshFlag()
        let calls = Calls()
        // Older install: the user has data and a backup, but no flag yet.
        container.mainContext.insert(Session(location: "Mine"))
        try container.mainContext.save()
        #expect(!flag.isSet)

        settingsViewModel(flag).deleteAllData(from: container.mainContext)
        #expect(try sessionCount(container) == 0)
        #expect(flag.isSet)

        #expect(try await launch(container, flag: flag, calls: calls) == .skippedAlreadyRan)
        #expect(try sessionCount(container) == 0)
        #expect(calls.list == 0)
        #expect(calls.download == 0)
    }

    @Test func restoreThenWipe_thenSignOutAndBackIn_doesNotRestore() async throws {
        let container = try TestHelpers.createContainer()
        let flag = freshFlag()
        let calls = Calls()
        #expect(try await launch(container, flag: flag, calls: calls) == .restored(sessionCount: 1))

        settingsViewModel(flag).deleteAllData(from: container.mainContext)
        // Sign out and back in as the same user: auth flips true again.
        #expect(try await launch(container, flag: flag, calls: calls) == .skippedAlreadyRan)
        #expect(try await launch(container, flag: flag, calls: calls) == .skippedAlreadyRan)

        #expect(try sessionCount(container) == 0)
        #expect(calls.download == 1) // only the first launch
    }

    @Test func noBackups_setsFlag() async throws {
        let container = try TestHelpers.createContainer()
        let flag = freshFlag()
        #expect(try await launch(container, flag: flag, calls: Calls(), backups: false) == .noBackups)
        #expect(flag.isSet)
    }

    @Test func localDataExists_setsFlag() async throws {
        let container = try TestHelpers.createContainer()
        container.mainContext.insert(Session(location: "Mine"))
        try container.mainContext.save()
        let flag = freshFlag()
        #expect(try await launch(container, flag: flag, calls: Calls()) == .skippedLocalDataExists)
        #expect(flag.isSet)
    }

    @Test func error_leavesFlagUnset_soNextLaunchRetries() async throws {
        let container = try TestHelpers.createContainer()
        let flag = freshFlag()
        let failing = AutoRestore(
            modelContext: container.mainContext,
            listBackups: { throw ListFailed() },
            downloadBackup: { [self] _ in payload() },
            flag: flag
        )
        await #expect(throws: ListFailed.self) { try await failing.run() }
        #expect(!flag.isSet)

        #expect(try await launch(container, flag: flag, calls: Calls()) == .restored(sessionCount: 1))
    }

    @Test func accountDeletion_clearsFlag_soNextSignInIsLikeAFreshInstall() async throws {
        let container = try TestHelpers.createContainer()
        let flag = freshFlag()
        flag.set()

        settingsViewModel(flag).wipeAfterAccountDeletion(from: container.mainContext)

        #expect(!flag.isSet)
        #expect(try await launch(container, flag: flag, calls: Calls()) == .restored(sessionCount: 1))
    }

    @Test func manualRestore_ignoresFlag() throws {
        let container = try TestHelpers.createContainer()
        let flag = freshFlag()
        flag.set()
        try LocalDataRestorer(modelContext: container.mainContext).restore(payload())
        #expect(try sessionCount(container) == 1)
    }
}
