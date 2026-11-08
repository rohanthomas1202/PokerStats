import Foundation
import os

/// The outgoing change queue's rules (design sections 4.1, 4.4 and 9.6), as
/// an in-memory value. Persisting it (`OutgoingChange` and `SyncMeta.nextSeq`)
/// and enqueueing from the app's writes are #85; nothing in the app calls it
/// while `SyncFeature.isEnabled` is false.
struct SyncChangeQueue: Equatable, Sendable {
    /// Per-push limits (design 4.1).
    static let maxBatchChanges = 500
    static let maxBatchBytes = 1_000_000
    /// Room left in `maxBatchBytes` for the envelope around `changes`.
    static let envelopeBytes = 1_024

    struct Entry: Equatable, Sendable {
        var change: SyncChange
        /// The full upsert made when the row was created. An upsert merged
        /// into it keeps its `seq`, so a session still goes before its hands.
        var isInsert: Bool
        /// Handed out by `nextBatch()`. Never merged into; removed only by a
        /// result for its `seq`.
        var isSent: Bool
    }

    /// What applying a push response did to the queue (design 9.6).
    enum PushOutcome: Equatable, Sendable {
        /// Every change with a result was removed. `rejected` lists the ones
        /// the server refused; they are logged and dropped.
        case ok(rejected: [SyncChangeResult])
        /// The queue is kept; stop pushing until the app is updated.
        case upgradeRequired
        // The queue is unchanged for these three; the caller decides (9.6).
        case wiped
        case accountMissing
        case invalid
    }

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "SyncChangeQueue")

    /// The `seq` the next change gets. It never goes back, including when the
    /// queue is emptied (4.4).
    private(set) var nextSeq: Int64
    /// In `seq` order.
    private(set) var entries: [Entry] = []

    init(nextSeq: Int64 = 1) {
        precondition(nextSeq >= 1, "seq starts at 1")
        self.nextSeq = nextSeq
    }

    var changes: [SyncChange] { entries.map(\.change) }

    // MARK: - Enqueue

    /// `isInsert` marks the full upsert made when the row is created.
    mutating func upsert(id: UUID, fields: SyncChange.Fields, isInsert: Bool = false) {
        enqueue(.upsert(seq: nextSeq, id: id, fields: fields), isInsert: isInsert)
    }

    mutating func delete(table: SyncTable, id: UUID) {
        enqueue(.delete(seq: nextSeq, table: table, id: id), isInsert: false)
    }

    mutating func restore(table: SyncTable, id: UUID) {
        enqueue(.restore(seq: nextSeq, table: table, id: id), isInsert: false)
    }

    /// Merges into the latest change for the same row only if it is unsent
    /// and has the same op, so nothing merges across a `delete` or `restore`
    /// and an upsert never absorbs one. The merge takes the new `seq` and
    /// moves to the end, unless it merges into an insert, which keeps its
    /// `seq` and place.
    private mutating func enqueue(_ change: SyncChange, isInsert: Bool) {
        nextSeq += 1
        guard let index = entries.lastIndex(where: { $0.change.table == change.table && $0.change.id == change.id }),
              !entries[index].isSent,
              entries[index].change.op == change.op
        else {
            entries.append(Entry(change: change, isInsert: isInsert, isSent: false))
            return
        }
        let earlier = entries.remove(at: index)
        let merged: SyncChange
        if let old = earlier.change.fields, let new = change.fields {
            let seq = earlier.isInsert ? earlier.change.seq : change.seq
            merged = .upsert(seq: seq, id: change.id, fields: old.merged(with: new))
        } else {
            // A repeated delete or restore: the later one stands.
            merged = change
        }
        let entry = Entry(change: merged, isInsert: earlier.isInsert || isInsert, isSent: false)
        if earlier.isInsert {
            entries.insert(entry, at: index)
        } else {
            entries.append(entry)
        }
    }

    /// Empties the queue for a same-account reset (4.4). `nextSeq` keeps going.
    mutating func removeAll() {
        entries.removeAll()
    }

    // MARK: - Push

    /// The next push's changes: the oldest, in `seq` order, up to 500 changes
    /// and 1 MB. They are marked sent and never merged into again. Call once
    /// per push, after applying the previous response; sent changes that got
    /// no result go again, and the server skips any it already applied.
    /// The first change is always included, so the queue can't stall.
    mutating func nextBatch() throws -> [SyncChange] {
        var bytes = Self.envelopeBytes
        var count = 0
        for entry in entries {
            guard count < Self.maxBatchChanges else { break }
            let size = try Self.payloadSize(of: entry.change)
            guard count == 0 || bytes + size <= Self.maxBatchBytes else { break }
            bytes += size
            count += 1
        }
        for index in 0..<count {
            entries[index].isSent = true
        }
        return entries.prefix(count).map(\.change)
    }

    /// Applies a `sync_push` response (design 4.1 and 9.6).
    mutating func apply(_ response: SyncPushResponse) -> PushOutcome {
        switch response {
        case .ok(_, let results):
            let answered = Set(results.map(\.seq))
            entries.removeAll { $0.isSent && answered.contains($0.change.seq) }
            var rejected: [SyncChangeResult] = []
            for result in results {
                guard case .rejected(let reason) = result.outcome else { continue }
                Self.logger.error("Push rejected change \(result.seq, privacy: .public): \(reason, privacy: .public)")
                rejected.append(result)
            }
            return .ok(rejected: rejected)
        case .upgradeRequired: return .upgradeRequired
        case .wiped: return .wiped
        case .accountMissing: return .accountMissing
        case .invalid: return .invalid
        }
    }

    /// A change's bytes as the server measures it (`payload::text`): compact
    /// JSON, plus one byte for each `:` and `,`, since jsonb text puts a space
    /// after them, plus the `, ` between changes. Counting the ones inside
    /// strings too makes this an upper bound.
    private static func payloadSize(of change: SyncChange) throws -> Int {
        let data = try SyncCoding.encoder.encode(change)
        let separators = data.reduce(0) { $0 + ($1 == UInt8(ascii: ":") || $1 == UInt8(ascii: ",") ? 1 : 0) }
        return data.count + separators + 2
    }
}

// MARK: - Merging fields (4.4)

extension SyncChange.Fields {
    /// The union of both patches; `later`'s values win.
    func merged(with later: Self) -> Self {
        switch (self, later) {
        case let (.session(old), .session(new)): .session(old.merged(with: new))
        case let (.hand(old), .hand(new)): .hand(old.merged(with: new))
        case let (.settings(old), .settings(new)): .settings(old.merged(with: new))
        // Unreachable: one row is in one table.
        default: later
        }
    }
}

extension SyncSessionFields {
    func merged(with later: Self) -> Self {
        SyncSessionFields(
            startTime: later.startTime ?? startTime,
            endTime: later.endTime ?? endTime,
            location: later.location ?? location,
            stakes: later.stakes ?? stakes,
            notes: later.notes ?? notes,
            gameType: later.gameType ?? gameType,
            status: later.status ?? status,
            buyIn: later.buyIn ?? buyIn,
            rebuys: later.rebuys ?? rebuys,
            addOns: later.addOns ?? addOns,
            cashOut: later.cashOut ?? cashOut,
            tipRake: later.tipRake ?? tipRake,
            tiltLevel: later.tiltLevel ?? tiltLevel,
            energyLevel: later.energyLevel ?? energyLevel,
            focusLevel: later.focusLevel ?? focusLevel,
            tableConfig: later.tableConfig ?? tableConfig,
            loggingDeviceId: later.loggingDeviceId ?? loggingDeviceId
        )
    }
}

extension SyncHandFields {
    func merged(with later: Self) -> Self {
        // `handNumber` is set only by `create`, so start from the side that has it.
        var merged = later.handNumber == nil ? self : later
        merged.sessionId = later.sessionId ?? sessionId
        merged.playedAt = later.playedAt ?? playedAt
        merged.preflopAction = later.preflopAction ?? preflopAction
        merged.faced3Bet = later.faced3Bet ?? faced3Bet
        merged.threeBetResponse = later.threeBetResponse ?? threeBetResponse
        merged.postflopResult = later.postflopResult ?? postflopResult
        merged.didCBet = later.didCBet ?? didCBet
        merged.notes = later.notes ?? notes
        merged.position = later.position ?? position
        return merged
    }
}

extension SyncSettingsFields {
    func merged(with later: Self) -> Self {
        SyncSettingsFields(
            defaultGameType: later.defaultGameType ?? defaultGameType,
            defaultStakes: later.defaultStakes ?? defaultStakes,
            defaultBuyIn: later.defaultBuyIn ?? defaultBuyIn,
            currency: later.currency ?? currency
        )
    }
}
