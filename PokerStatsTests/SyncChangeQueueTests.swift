import Foundation
import Testing
@testable import PokerStats

/// The outgoing change queue's rules (#237), checked against design sections
/// 4.1, 4.4 and 9.6.
@Suite("Sync change queue")
struct SyncChangeQueueTests {

    // MARK: - seq

    @Test func seq_isStrictlyIncreasing() {
        var queue = SyncChangeQueue()
        queue.upsert(id: UUID(), fields: .session(SyncSessionFields(notes: "a")))
        queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "b")))
        queue.delete(table: .hands, id: UUID())
        #expect(queue.changes.map(\.seq) == [1, 2, 3])
        #expect(queue.nextSeq == 4)
    }

    @Test func nextSeq_neverGoesBack_whenTheQueueIsEmptied() throws {
        var queue = SyncChangeQueue(nextSeq: 41)
        queue.upsert(id: UUID(), fields: .session(SyncSessionFields(notes: "a")))
        queue.upsert(id: UUID(), fields: .session(SyncSessionFields(notes: "b")))
        let batch = try queue.nextBatch()
        _ = queue.apply(Self.ok(batch.map { SyncChangeResult(seq: $0.seq, outcome: .applied) }))
        #expect(queue.changes.isEmpty)
        #expect(queue.nextSeq == 43)

        queue.delete(table: .hands, id: UUID())
        queue.removeAll()
        #expect(queue.changes.isEmpty)
        queue.restore(table: .hands, id: UUID())
        #expect(queue.changes.map(\.seq) == [44])
        #expect(queue.nextSeq == 45)
    }

    // MARK: - Coalescing

    @Test func sameOp_mergesWithTheUnionOfFields_laterValuesWin() {
        var queue = SyncChangeQueue()
        let id = UUID()
        queue.upsert(id: id, fields: .session(SyncSessionFields(location: "Aria", notes: "tight table")))
        queue.upsert(id: id, fields: .session(SyncSessionFields(notes: "loose now", tiltLevel: .some(nil))))
        #expect(queue.changes == [
            .upsert(seq: 2, id: id, fields: .session(SyncSessionFields(location: "Aria", notes: "loose now", tiltLevel: .some(nil)))),
        ])
    }

    @Test func differentRows_doNotMerge() {
        var queue = SyncChangeQueue()
        let id = UUID()
        queue.upsert(id: id, fields: .hand(SyncHandFields(notes: "a")))
        queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "b")))
        // Same id, other table.
        queue.upsert(id: id, fields: .session(SyncSessionFields(notes: "c")))
        #expect(queue.changes.count == 3)
    }

    @Test func upsertThenDelete_staysTwoChanges() {
        var queue = SyncChangeQueue()
        let id = UUID()
        queue.upsert(id: id, fields: .hand(Self.handCreate()), isInsert: true)
        queue.delete(table: .hands, id: id)
        #expect(queue.changes.map(\.op) == [.upsert, .delete])
        #expect(queue.changes.map(\.seq) == [1, 2])
    }

    @Test(arguments: [SyncChange.Op.delete, .restore])
    func nothingMergesAcrossADeleteOrRestore(_ op: SyncChange.Op) {
        var queue = SyncChangeQueue()
        let id = UUID()
        queue.upsert(id: id, fields: .hand(SyncHandFields(notes: "a")))
        if op == .delete { queue.delete(table: .hands, id: id) } else { queue.restore(table: .hands, id: id) }
        queue.upsert(id: id, fields: .hand(SyncHandFields(notes: "b")))
        #expect(queue.changes.map(\.op) == [.upsert, op, .upsert])
        #expect(queue.changes.map(\.seq) == [1, 2, 3])
    }

    @Test func mergedChange_takesTheHighestSeq() {
        var queue = SyncChangeQueue()
        let session = UUID()
        let hand = UUID()
        queue.upsert(id: session, fields: .session(SyncSessionFields(notes: "a")))
        queue.upsert(id: hand, fields: .hand(Self.handCreate(session: session)), isInsert: true)
        queue.upsert(id: session, fields: .session(SyncSessionFields(stakes: "1/2")))
        #expect(queue.changes.map(\.id) == [hand, session])
        #expect(queue.changes.map(\.seq) == [2, 3])
    }

    /// Design 4.4: ending a session whose insert is still queued keeps the
    /// session ahead of its hands.
    @Test func mergeIntoAQueuedInsert_keepsTheInsertsSeq() throws {
        var queue = SyncChangeQueue()
        let session = UUID()
        let start = Date(timeIntervalSince1970: 1_792_289_469)
        let end = start.addingTimeInterval(3600)
        queue.upsert(
            id: session,
            fields: .session(SyncSessionFields(startTime: start, gameType: .cash, status: .active, buyIn: 200)),
            isInsert: true
        )
        let hands = [UUID(), UUID()]
        for hand in hands {
            queue.upsert(id: hand, fields: .hand(Self.handCreate(session: session)), isInsert: true)
        }
        queue.upsert(id: session, fields: .session(SyncSessionFields(endTime: .some(end), status: .completed, cashOut: 412.5)))

        #expect(queue.changes.map(\.id) == [session] + hands)
        #expect(queue.changes.map(\.seq) == [1, 2, 3])
        #expect(queue.nextSeq == 5)
        #expect(queue.changes.first == SyncChange.upsert(seq: 1, id: session, fields: .session(SyncSessionFields(
            startTime: start, endTime: .some(end), gameType: .cash, status: .completed, buyIn: 200, cashOut: 412.5
        ))))
        // The session still goes in the first batch, ahead of its hands.
        #expect(try queue.nextBatch().map(\.id) == [session] + hands)
    }

    @Test func handNumber_survivesAMergeIntoTheCreate() {
        var queue = SyncChangeQueue()
        let hand = UUID()
        queue.upsert(id: hand, fields: .hand(Self.handCreate()), isInsert: true)
        queue.upsert(id: hand, fields: .hand(SyncHandFields(notes: "villain overbet river")))
        guard case .hand(let fields)? = queue.changes.first?.fields else {
            Issue.record("Expected one hand upsert")
            return
        }
        #expect(queue.changes.count == 1)
        #expect(fields.handNumber == 17)
        #expect(fields.notes == "villain overbet river")
    }

    /// Every column takes part in a merge, from either side.
    @Test func merge_keepsEveryColumn() {
        let session = SyncSessionFields(
            startTime: .now, endTime: .some(nil), location: "Aria", stakes: "1/2", notes: "n", gameType: .tournament,
            status: .completed, buyIn: 1, rebuys: 2, addOns: 3, cashOut: 4, tipRake: 5, tiltLevel: .some(1),
            energyLevel: .some(nil), focusLevel: .some(5), tableConfig: .some(["seats": .number(9)]), loggingDeviceId: .some(UUID())
        )
        #expect(session.merged(with: SyncSessionFields()) == session)
        #expect(SyncSessionFields().merged(with: session) == session)

        let hand = SyncHandFields.create(
            sessionId: UUID(), handNumber: 3, playedAt: .now, preflopAction: .raise, faced3Bet: true, position: .bb,
            threeBetResponse: .some(.called), postflopResult: .some(nil), didCBet: .some(true), notes: "n"
        )
        #expect(hand.merged(with: SyncHandFields()) == hand)
        #expect(SyncHandFields().merged(with: hand) == hand)

        let settings = SyncSettingsFields(defaultGameType: .cash, defaultStakes: "1/2", defaultBuyIn: 200, currency: "USD")
        #expect(settings.merged(with: SyncSettingsFields()) == settings)
        #expect(SyncSettingsFields().merged(with: settings) == settings)
    }

    // MARK: - In flight

    @Test func sentChanges_areNeverMergedInto() throws {
        var queue = SyncChangeQueue()
        let id = UUID()
        queue.upsert(id: id, fields: .session(SyncSessionFields(notes: "a")), isInsert: true)
        let sent = try queue.nextBatch()
        queue.upsert(id: id, fields: .session(SyncSessionFields(notes: "b")))
        #expect(queue.changes.map(\.seq) == [1, 2])

        // The unsent one still merges with what follows it.
        queue.upsert(id: id, fields: .session(SyncSessionFields(stakes: "1/2")))
        #expect(queue.changes.map(\.seq) == [1, 3])

        _ = queue.apply(Self.ok(sent.map { SyncChangeResult(seq: $0.seq, outcome: .applied) }))
        #expect(queue.changes == [.upsert(seq: 3, id: id, fields: .session(SyncSessionFields(stakes: "1/2", notes: "b")))])
    }

    // MARK: - Batches

    @Test func batch_holdsAtMost500Changes_inSeqOrder() throws {
        var queue = SyncChangeQueue()
        for _ in 0..<501 {
            queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "n")))
        }
        let first = try queue.nextBatch()
        #expect(first.map(\.seq) == Array(1...500))
        _ = queue.apply(Self.ok(first.map { SyncChangeResult(seq: $0.seq, outcome: .applied) }))
        #expect(try queue.nextBatch().map(\.seq) == [501])
    }

    @Test func batch_staysWithinOneMegabyte() throws {
        var queue = SyncChangeQueue()
        let notes = String(repeating: "x", count: 10_000)
        for _ in 0..<150 {
            queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: notes)))
        }
        let batch = try queue.nextBatch()
        #expect(batch.count < 150)
        #expect(batch.count > 90)
        #expect(batch.map(\.seq) == Array(1...Int64(batch.count)))
        let request = SyncPushRequest(
            protocolVersion: SyncPushRequest.currentProtocol, deviceId: UUID(), appVersion: "1.1 (2026110801)",
            epoch: 0, changes: batch, firstSyncDone: false
        )
        #expect(try SyncCoding.encoder.encode(request).count <= SyncChangeQueue.maxBatchBytes)

        _ = queue.apply(Self.ok(batch.map { SyncChangeResult(seq: $0.seq, outcome: .applied) }))
        #expect(try queue.nextBatch().first?.seq == Int64(batch.count) + 1)
    }

    /// A push with no result for a sent change sends it again.
    @Test func batch_resendsSentChangesWithoutAResult() throws {
        var queue = SyncChangeQueue()
        queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "a")))
        queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "b")))
        _ = try queue.nextBatch()
        queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "c")))
        _ = queue.apply(Self.ok([SyncChangeResult(seq: 1, outcome: .applied)]))
        #expect(try queue.nextBatch().map(\.seq) == [2, 3])
    }

    // MARK: - Responses (9.6)

    @Test func okResults_removeAppliedSkippedPurgedAndRejected() throws {
        var queue = SyncChangeQueue()
        for _ in 0..<4 {
            queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "n")))
        }
        let batch = try queue.nextBatch()
        let rejected = SyncChangeResult(seq: 4, outcome: .rejected(reason: "23503"))
        let outcome = queue.apply(Self.ok([
            SyncChangeResult(seq: 1, outcome: .applied),
            SyncChangeResult(seq: 2, outcome: .skipped),
            SyncChangeResult(seq: 3, outcome: .purged),
            rejected,
        ]))
        #expect(batch.count == 4)
        #expect(outcome == .ok(rejected: [rejected]))
        #expect(queue.changes.isEmpty)
    }

    @Test(arguments: [
        (SyncPushResponse.upgradeRequired, SyncChangeQueue.PushOutcome.upgradeRequired),
        (.wiped, .wiped),
        (.accountMissing, .accountMissing),
        (.invalid, .invalid),
    ] as [(SyncPushResponse, SyncChangeQueue.PushOutcome)])
    func otherStatuses_leaveTheQueueUnchanged(_ response: SyncPushResponse, _ expected: SyncChangeQueue.PushOutcome) throws {
        var queue = SyncChangeQueue()
        queue.upsert(id: UUID(), fields: .hand(SyncHandFields(notes: "a")))
        _ = try queue.nextBatch()
        queue.delete(table: .hands, id: UUID())
        let before = queue
        #expect(queue.apply(response) == expected)
        #expect(queue == before)
    }

    // MARK: - Helpers

    private static func ok(_ results: [SyncChangeResult]) -> SyncPushResponse {
        .ok(revision: 1, results: results)
    }

    private static func handCreate(session: UUID = UUID()) -> SyncHandFields {
        .create(
            sessionId: session, handNumber: 17, playedAt: Date(timeIntervalSince1970: 1_792_289_469),
            preflopAction: .fold, faced3Bet: false, position: .btn
        )
    }
}
