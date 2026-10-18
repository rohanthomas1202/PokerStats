import Foundation
import SwiftData
import Testing
@testable import PokerStats

private struct DownloadFailed: Error {}

@MainActor
private final class Flag {
    var value = false
}

/// A flag backed by its own UserDefaults suite, unset.
@MainActor
func freshFlag() -> AutoRestoreFlag {
    let defaults = UserDefaults(suiteName: "AutoRestoreTests.\(UUID().uuidString)")!
    return AutoRestoreFlag(defaults: defaults)
}

@Suite("Auto Restore Tests")
@MainActor
struct AutoRestoreTests {

    // MARK: - Fixtures

    private let metadata = BackupMetadata(
        id: UUID(), userId: UUID(), storagePath: "u/backup.json.gz",
        fileSizeBytes: 100, schemaVersion: 1, sessionCount: 1, handCount: 2,
        createdAt: .now
    )

    private func backupPayload() -> BackupPayload {
        let hands = (1...2).map { n in
            HandDTO(
                id: UUID(), handNumber: n, timestamp: .now, preflopAction: "call",
                faced3Bet: false, threeBetResponse: nil, postflopResult: nil,
                didCBet: nil, notes: "", position: "CO"
            )
        }
        let session = SessionDTO(
            id: UUID(), startTime: .now, endTime: .now, location: "From Backup",
            gameType: "cash", stakes: "1/3", notes: "", status: "completed",
            buyIn: 300, rebuys: 0, addOns: 0, cashOut: 450, tipRake: 0,
            tiltLevel: nil, energyLevel: nil, focusLevel: nil,
            tableConfigJson: nil, hands: hands
        )
        return BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion, createdAt: .now,
            appVersion: "1.0.0", sessions: [session], settings: nil
        )
    }

    /// Committed sessions, read through a fresh context.
    private func storedLocations(_ container: ModelContainer) throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<Session>()).map(\.location).sorted()
    }

    // MARK: - Tests

    @Test func sessionSavedDuringDownload_survives_andRestoreIsSkipped() async throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let autoRestore = AutoRestore(
            modelContext: context,
            listBackups: { [metadata] in [metadata] },
            downloadBackup: { _ in
                // Slow download: the user starts and saves a session meanwhile.
                await Task.yield()
                context.insert(Session(location: "Started Mid-Download"))
                try context.save()
                await Task.yield()
                return backupPayload()
            },
            flag: freshFlag()
        )

        let outcome = try await autoRestore.run()

        #expect(outcome == .skippedDataAppearedDuringDownload)
        #expect(try storedLocations(container) == ["Started Mid-Download"])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Hand>()) == 0)
    }

    @Test func unsavedSessionDuringDownload_survives_andRestoreIsSkipped() async throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let autoRestore = AutoRestore(
            modelContext: context,
            listBackups: { [metadata] in [metadata] },
            downloadBackup: { _ in
                // Inserted but not yet saved (autosave hasn't run).
                context.insert(Session(location: "Unsaved Mid-Download"))
                return backupPayload()
            },
            flag: freshFlag()
        )

        #expect(try await autoRestore.run() == .skippedDataAppearedDuringDownload)
        let visible = try context.fetch(FetchDescriptor<Session>()).map(\.location)
        #expect(visible == ["Unsaved Mid-Download"])
        try context.save()
        #expect(try storedLocations(container) == ["Unsaved Mid-Download"])
    }

    @Test func storeStillEmpty_restoresBackup() async throws {
        let container = try TestHelpers.createContainer()
        let autoRestore = AutoRestore(
            modelContext: container.mainContext,
            listBackups: { [metadata] in [metadata] },
            downloadBackup: { _ in backupPayload() },
            flag: freshFlag()
        )

        #expect(try await autoRestore.run() == .restored(sessionCount: 1))
        #expect(try storedLocations(container) == ["From Backup"])
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Hand>()) == 2)
    }

    @Test func downloadFailure_changesNothing() async throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let autoRestore = AutoRestore(
            modelContext: context,
            listBackups: { [metadata] in [metadata] },
            downloadBackup: { _ in throw DownloadFailed() },
            flag: freshFlag()
        )

        await #expect(throws: DownloadFailed.self) { try await autoRestore.run() }
        #expect(!context.hasChanges)
        #expect(try storedLocations(container).isEmpty)
    }

    @Test func noBackups_changesNothing() async throws {
        let container = try TestHelpers.createContainer()
        let downloaded = Flag()
        let autoRestore = AutoRestore(
            modelContext: container.mainContext,
            listBackups: { [] },
            downloadBackup: { _ in
                downloaded.value = true
                return backupPayload()
            },
            flag: freshFlag()
        )

        #expect(try await autoRestore.run() == .noBackups)
        #expect(!downloaded.value)
        #expect(try storedLocations(container).isEmpty)
    }

    @Test func existingLocalData_skipsBeforeAnyNetworkCall() async throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        context.insert(Session(location: "Existing"))
        try context.save()
        let listed = Flag()
        let autoRestore = AutoRestore(
            modelContext: context,
            listBackups: {
                listed.value = true
                return []
            },
            downloadBackup: { _ in backupPayload() },
            flag: freshFlag()
        )

        #expect(try await autoRestore.run() == .skippedLocalDataExists)
        #expect(!listed.value)
        #expect(try storedLocations(container) == ["Existing"])
    }

    @Test func restoreIfStoreEmpty_returnsFalseAndTouchesNothingWhenDataExists() throws {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        context.insert(Session(location: "Mine"))
        try context.save()

        let restored = try LocalDataRestorer(modelContext: context).restoreIfStoreEmpty(backupPayload())

        #expect(!restored)
        #expect(!context.hasChanges)
        #expect(try storedLocations(container) == ["Mine"])
    }
}
