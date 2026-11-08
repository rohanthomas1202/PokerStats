import Foundation

// MARK: - Pulled rows (design sections 4.3 and 9.5)
//
// Rows keep the values the server sent, so the app never writes a fallback
// back (9.5). The `resolved` properties are what the app would store locally:
// unknown enum values take the existing fallbacks, except session status.

/// The sync columns of a pulled row, set by the server.
struct SyncRowMeta: Decodable, Equatable, Sendable {
    let userId: UUID
    let revision: Int64
    let serverUpdatedAt: Date
    /// Set: hide the row. Cleared only by a `restore` op.
    let deletedAt: Date?
    /// Set: remove the row locally. A purged row is a stub (design 5.3).
    let purgedAt: Date?
    let updatedByDevice: UUID?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SyncMetaColumn.self)
        userId = try c.decode(UUID.self, forKey: .userId)
        revision = try c.decode(Int64.self, forKey: .revision)
        serverUpdatedAt = try c.decode(Date.self, forKey: .serverUpdatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        purgedAt = try c.decodeIfPresent(Date.self, forKey: .purgedAt)
        updatedByDevice = try c.decodeIfPresent(UUID.self, forKey: .updatedByDevice)
    }
}

/// A pulled `poker_sessions` row.
struct SyncPulledSession: Decodable, Equatable, Sendable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let location: String
    let stakes: String
    let notes: String
    let gameType: String
    let status: String
    let buyIn: Double
    let rebuys: Double
    let addOns: Double
    let cashOut: Double
    let tipRake: Double
    let tiltLevel: Int?
    let energyLevel: Int?
    let focusLevel: Int?
    let tableConfig: [String: SyncJSON]?
    let loggingDeviceId: UUID?
    let meta: SyncRowMeta

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SyncSessionColumn.self)
        id = try c.decode(UUID.self, forKey: .id)
        startTime = try c.decode(Date.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        location = try c.decode(String.self, forKey: .location)
        stakes = try c.decode(String.self, forKey: .stakes)
        notes = try c.decode(String.self, forKey: .notes)
        gameType = try c.decode(String.self, forKey: .gameType)
        status = try c.decode(String.self, forKey: .status)
        buyIn = try c.decode(Double.self, forKey: .buyIn)
        rebuys = try c.decode(Double.self, forKey: .rebuys)
        addOns = try c.decode(Double.self, forKey: .addOns)
        cashOut = try c.decode(Double.self, forKey: .cashOut)
        tipRake = try c.decode(Double.self, forKey: .tipRake)
        tiltLevel = try c.decodeIfPresent(Int.self, forKey: .tiltLevel)
        energyLevel = try c.decodeIfPresent(Int.self, forKey: .energyLevel)
        focusLevel = try c.decodeIfPresent(Int.self, forKey: .focusLevel)
        tableConfig = try c.decodeIfPresent([String: SyncJSON].self, forKey: .tableConfig)
        loggingDeviceId = try c.decodeIfPresent(UUID.self, forKey: .loggingDeviceId)
        meta = try SyncRowMeta(from: decoder)
    }

    /// An unknown status is completed (and read-only), never active: the
    /// app's `Session.status` falls back to `.active`, which would make it look
    /// like the live session (design 9.5, disagreement 1).
    var resolvedStatus: SessionStatus {
        SessionStatus(rawValue: status) ?? .completed
    }

    /// A completed session with no end time ends at its start time, so its
    /// duration is 0 and it has no hourly rate, while its net profit still
    /// counts. Without this its duration would run to now (disagreement 12).
    var resolvedEndTime: Date? {
        if let endTime { return endTime }
        return resolvedStatus == .completed ? startTime : nil
    }

    var resolvedGameType: GameType {
        GameType(rawValue: gameType) ?? .cash
    }

    /// `table_config` as the bytes `Session.tableConfigData` stores.
    var resolvedTableConfigData: Data? {
        tableConfig.flatMap { try? JSONEncoder().encode($0) }
    }
}

/// A pulled `hands` row.
struct SyncPulledHand: Decodable, Equatable, Sendable {
    let id: UUID
    let sessionId: UUID
    let handNumber: Int
    let playedAt: Date
    let preflopAction: String
    let faced3Bet: Bool
    let threeBetResponse: String?
    let postflopResult: String?
    let didCBet: Bool?
    let notes: String
    let position: String
    let meta: SyncRowMeta

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SyncHandColumn.self)
        id = try c.decode(UUID.self, forKey: .id)
        sessionId = try c.decode(UUID.self, forKey: .sessionId)
        handNumber = try c.decode(Int.self, forKey: .handNumber)
        playedAt = try c.decode(Date.self, forKey: .playedAt)
        preflopAction = try c.decode(String.self, forKey: .preflopAction)
        faced3Bet = try c.decode(Bool.self, forKey: .faced3Bet)
        threeBetResponse = try c.decodeIfPresent(String.self, forKey: .threeBetResponse)
        postflopResult = try c.decodeIfPresent(String.self, forKey: .postflopResult)
        didCBet = try c.decodeIfPresent(Bool.self, forKey: .didCBet)
        notes = try c.decode(String.self, forKey: .notes)
        position = try c.decode(String.self, forKey: .position)
        meta = try SyncRowMeta(from: decoder)
    }

    var resolvedPreflopAction: PreflopAction {
        PreflopAction(rawValue: preflopAction) ?? .fold
    }

    /// One rule for a 3-bet on a hand that didn't raise preflop: a 3-bet is
    /// faced only after a preflop raise (as the phone logger asks it), so on a
    /// fold or call `faced_3bet` is false and `three_bet_response` is dropped.
    /// Enforced here at import, not by per-stat filters (Kate's Low 1 on PR #291).
    var resolvedFaced3Bet: Bool {
        faced3Bet && resolvedPreflopAction == .raise
    }

    /// Nil unless the hand faced a 3-bet (see `resolvedFaced3Bet`).
    var resolvedThreeBetResponse: ThreeBetResponse? {
        guard resolvedFaced3Bet else { return nil }
        return threeBetResponse.flatMap(ThreeBetResponse.init(rawValue:))
    }

    var resolvedPostflopResult: PostflopResult? {
        postflopResult.flatMap(PostflopResult.init(rawValue:))
    }

    var resolvedPosition: SeatPosition {
        SeatPosition(rawValue: position) ?? .unknown
    }
}

/// A pulled `user_settings` row. Keyed by `user_id` (in `meta`); no `id`.
struct SyncPulledSettings: Decodable, Equatable, Sendable {
    let defaultGameType: String
    let defaultStakes: String
    let defaultBuyIn: Double
    let currency: String
    let meta: SyncRowMeta

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SyncSettingsColumn.self)
        defaultGameType = try c.decode(String.self, forKey: .defaultGameType)
        defaultStakes = try c.decode(String.self, forKey: .defaultStakes)
        defaultBuyIn = try c.decode(Double.self, forKey: .defaultBuyIn)
        currency = try c.decode(String.self, forKey: .currency)
        meta = try SyncRowMeta(from: decoder)
    }

    var resolvedDefaultGameType: GameType {
        GameType(rawValue: defaultGameType) ?? .cash
    }
}

/// The `sync_state` row read in pull step 1. No row means `account_missing`,
/// not an empty server (design 4.3).
struct SyncStateRow: Decodable, Equatable, Sendable {
    let userId: UUID
    let revision: Int64
    let wipeEpoch: Int
    let wipedAt: Date?
    let firstSyncCompletedAt: Date?
    let backupsRetireAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case revision
        case wipeEpoch = "wipe_epoch"
        case wipedAt = "wiped_at"
        case firstSyncCompletedAt = "first_sync_completed_at"
        case backupsRetireAt = "backups_retire_at"
    }
}
