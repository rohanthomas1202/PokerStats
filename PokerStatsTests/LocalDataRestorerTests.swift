import Foundation
import SwiftData
import Testing
@testable import PokerStats

private struct InjectedSaveFailure: Error {}

@Suite("Local Data Restorer Tests")
@MainActor
struct LocalDataRestorerTests {

    // MARK: - Fixtures

    /// Container with two local sessions ("Local A" with 2 hands, "Local B" with 1)
    /// and local settings, all saved.
    private func seededContainer() throws -> ModelContainer {
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        let a = Session(location: "Local A", status: .completed, buyIn: 100)
        let b = Session(location: "Local B", status: .completed, buyIn: 200)
        context.insert(a)
        context.insert(b)
        for (n, session) in [(1, a), (2, a), (1, b)] {
            let hand = TestHelpers.foldHand(number: n)
            hand.session = session
            context.insert(hand)
        }
        context.insert(Settings(defaultStakes: "1/2", currency: "USD"))
        try context.save()
        return container
    }

    private func handDTO(_ number: Int, id: UUID = UUID()) -> HandDTO {
        HandDTO(
            id: id, handNumber: number, timestamp: .now, preflopAction: "raise",
            faced3Bet: false, threeBetResponse: nil, postflopResult: nil,
            didCBet: nil, notes: "", position: "BTN"
        )
    }

    private func sessionDTO(_ location: String, id: UUID = UUID(), hands: [HandDTO]) -> SessionDTO {
        SessionDTO(
            id: id, startTime: .now, endTime: .now, location: location,
            gameType: "cash", stakes: "2/5", notes: "", status: "completed",
            buyIn: 500, rebuys: 0, addOns: 0, cashOut: 800, tipRake: 0,
            tiltLevel: nil, energyLevel: nil, focusLevel: nil,
            tableConfigJson: nil, hands: hands
        )
    }

    private func payload(
        schemaVersion: Int = BackupPayload.currentSchemaVersion,
        sessions: [SessionDTO]? = nil
    ) -> BackupPayload {
        BackupPayload(
            schemaVersion: schemaVersion,
            createdAt: .now,
            appVersion: "1.0.0",
            sessions: sessions ?? [
                sessionDTO("Backup X", hands: [handDTO(1), handDTO(2), handDTO(3)]),
            ],
            settings: SettingsDTO(
                id: UUID(), defaultGameType: "cash", defaultStakes: "2/5",
                defaultBuyIn: 500, currency: "EUR"
            )
        )
    }

    /// Reads what's committed to the store through a fresh context, so
    /// unsaved changes in the restore's context don't count.
    private func persisted(_ container: ModelContainer) throws -> (locations: [String], hands: Int, currencies: [String]) {
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<Session>()).map(\.location).sorted()
        let hands = try context.fetchCount(FetchDescriptor<Hand>())
        let currencies = try context.fetch(FetchDescriptor<Settings>()).map(\.currency)
        return (sessions, hands, currencies)
    }

    // MARK: - Happy path

    @Test func restore_replacesLocalDataWithBackup() throws {
        let container = try seededContainer()
        try LocalDataRestorer(modelContext: container.mainContext).restore(payload())

        let stored = try persisted(container)
        #expect(stored.locations == ["Backup X"])
        #expect(stored.hands == 3)
        #expect(stored.currencies == ["EUR"])
        let session = try #require(try ModelContext(container).fetch(FetchDescriptor<Session>()).first)
        #expect(session.hands.count == 3)
    }

    @Test func restore_savesExactlyOnce() throws {
        let container = try seededContainer()
        var saves = 0
        var restorer = LocalDataRestorer(modelContext: container.mainContext)
        restorer.save = { context in
            saves += 1
            try context.save()
        }
        try restorer.restore(payload())
        #expect(saves == 1)
        #expect(try persisted(container).locations == ["Backup X"])
    }

    // MARK: - Failure injection

    @Test func failedSave_leavesLocalDataIntact() throws {
        let container = try seededContainer()
        var restorer = LocalDataRestorer(modelContext: container.mainContext)
        restorer.save = { context in
            // Delete and insert are pending at this point; fail the commit.
            #expect(context.hasChanges)
            throw InjectedSaveFailure()
        }

        #expect(throws: InjectedSaveFailure.self) {
            try restorer.restore(payload())
        }

        // Nothing committed, and the restore's context was rolled back too.
        let stored = try persisted(container)
        #expect(stored.locations == ["Local A", "Local B"])
        #expect(stored.hands == 3)
        #expect(stored.currencies == ["USD"])
        let context = container.mainContext
        #expect(!context.hasChanges)
        let visible = try context.fetch(FetchDescriptor<Session>()).map(\.location).sorted()
        #expect(visible == ["Local A", "Local B"])
        #expect(try context.fetchCount(FetchDescriptor<Hand>()) == 3)
    }

    @Test func failedSave_thenLaterSave_doesNotCommitPartialRestore() throws {
        let container = try seededContainer()
        var restorer = LocalDataRestorer(modelContext: container.mainContext)
        restorer.save = { _ in throw InjectedSaveFailure() }
        #expect(throws: InjectedSaveFailure.self) { try restorer.restore(payload()) }

        // e.g. autosave or the next user edit saving the same context.
        try container.mainContext.save()

        #expect(try persisted(container).locations == ["Local A", "Local B"])
    }

    // MARK: - Validation before mutation

    @Test func schemaTooNew_failsBeforeTouchingData() throws {
        let container = try seededContainer()
        var saveCalled = false
        var restorer = LocalDataRestorer(modelContext: container.mainContext)
        restorer.save = { _ in saveCalled = true }

        #expect(throws: BackupError.self) {
            try restorer.restore(payload(schemaVersion: BackupPayload.currentSchemaVersion + 1))
        }
        #expect(!saveCalled)
        #expect(!container.mainContext.hasChanges)
        #expect(try persisted(container).locations == ["Local A", "Local B"])
    }

    @Test func duplicateSessionIDs_failBeforeTouchingData() throws {
        let container = try seededContainer()
        let id = UUID()
        let bad = payload(sessions: [
            sessionDTO("Dup 1", id: id, hands: []),
            sessionDTO("Dup 2", id: id, hands: []),
        ])

        #expect(throws: BackupError.self) {
            try LocalDataRestorer(modelContext: container.mainContext).restore(bad)
        }
        #expect(!container.mainContext.hasChanges)
        #expect(try persisted(container).locations == ["Local A", "Local B"])
    }

    @Test func duplicateHandIDs_failBeforeTouchingData() throws {
        let container = try seededContainer()
        let id = UUID()
        let bad = payload(sessions: [
            sessionDTO("S1", hands: [handDTO(1, id: id)]),
            sessionDTO("S2", hands: [handDTO(1, id: id)]),
        ])

        #expect(throws: BackupError.self) {
            try LocalDataRestorer(modelContext: container.mainContext).restore(bad)
        }
        #expect(try persisted(container).hands == 3)
    }

    @Test func pendingUnrelatedEdits_surviveFailedRestore() throws {
        let container = try seededContainer()
        let context = container.mainContext
        context.insert(Session(location: "Unsaved C"))

        var restorer = LocalDataRestorer(modelContext: context)
        restorer.save = { _ in throw InjectedSaveFailure() }
        #expect(throws: InjectedSaveFailure.self) { try restorer.restore(payload()) }

        #expect(try persisted(container).locations == ["Local A", "Local B", "Unsaved C"])
    }
}
