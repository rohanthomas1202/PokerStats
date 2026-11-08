import Foundation

// MARK: - Request (design section 4.1)

/// The body of `rpc/sync_push`.
struct SyncPushRequest: Codable, Equatable, Sendable {
    static let currentProtocol = 1

    var protocolVersion: Int
    var deviceId: UUID
    var appVersion: String
    var epoch: Int
    var changes: [SyncChange]
    /// Required; `false` unless this push finishes the first sync.
    var firstSyncDone: Bool

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case deviceId = "device_id"
        case appVersion = "app_version"
        case epoch
        case changes
        case firstSyncDone = "first_sync_done"
    }
}

/// One queued change. Build it with `upsert`, `delete` or `restore`, so the
/// table always matches the fields and only an upsert carries fields.
/// `user_settings` is upsert only, and its `id` is the signed-in user's ID,
/// never `Settings.id` (shared/fixtures/sync/README.md decision 4).
struct SyncChange: Equatable, Sendable {
    enum Op: String, Codable, Sendable {
        case upsert
        case delete
        case restore
    }

    enum Fields: Equatable, Sendable {
        case session(SyncSessionFields)
        case hand(SyncHandFields)
        case settings(SyncSettingsFields)

        var table: SyncTable {
            switch self {
            case .session: .pokerSessions
            case .hand: .hands
            case .settings: .userSettings
            }
        }
    }

    /// Strictly increasing per device, starting at 1 (contract decision 1).
    let seq: Int64
    let op: Op
    let table: SyncTable
    let id: UUID
    let fields: Fields?

    private init(seq: Int64, op: Op, table: SyncTable, id: UUID, fields: Fields?) {
        self.seq = seq
        self.op = op
        self.table = table
        self.id = id
        self.fields = fields
    }

    static func upsert(seq: Int64, id: UUID, fields: Fields) -> SyncChange {
        SyncChange(seq: seq, op: .upsert, table: fields.table, id: id, fields: fields)
    }

    static func delete(seq: Int64, table: SyncTable, id: UUID) -> SyncChange {
        SyncChange(seq: seq, op: .delete, table: table, id: id, fields: nil)
    }

    static func restore(seq: Int64, table: SyncTable, id: UUID) -> SyncChange {
        SyncChange(seq: seq, op: .restore, table: table, id: id, fields: nil)
    }
}

extension SyncChange: Codable {
    private enum CodingKeys: String, CodingKey {
        case seq, op, table, id, fields
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int64.self, forKey: .seq)
        op = try container.decode(Op.self, forKey: .op)
        table = try container.decode(SyncTable.self, forKey: .table)
        id = try container.decode(UUID.self, forKey: .id)
        guard op == .upsert else {
            guard !container.contains(.fields) else {
                throw DecodingError.dataCorruptedError(forKey: .fields, in: container, debugDescription: "Only an upsert carries fields")
            }
            fields = nil
            return
        }
        switch table {
        case .pokerSessions: fields = .session(try container.decode(SyncSessionFields.self, forKey: .fields))
        case .hands: fields = .hand(try container.decode(SyncHandFields.self, forKey: .fields))
        case .userSettings: fields = .settings(try container.decode(SyncSettingsFields.self, forKey: .fields))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode(op, forKey: .op)
        try container.encode(table, forKey: .table)
        try container.encode(id, forKey: .id)
        switch fields {
        case .session(let value): try container.encode(value, forKey: .fields)
        case .hand(let value): try container.encode(value, forKey: .fields)
        case .settings(let value): try container.encode(value, forKey: .fields)
        case nil: break
        }
    }
}

// MARK: - Fields

/// A `poker_sessions` patch: only non-nil properties are sent. For a nullable
/// column, `.some(nil)` sends null. Money is rounded to cents and clamped to
/// `numeric(14,2)` when encoded; `table_config` is a JSON object.
struct SyncSessionFields: Equatable, Sendable {
    var startTime: Date?
    var endTime: Date??
    var location: String?
    var stakes: String?
    var notes: String?
    var gameType: GameType?
    var status: SessionStatus?
    var buyIn: Double?
    var rebuys: Double?
    var addOns: Double?
    var cashOut: Double?
    var tipRake: Double?
    var tiltLevel: Int??
    var energyLevel: Int??
    var focusLevel: Int??
    var tableConfig: [String: SyncJSON]??
    var loggingDeviceId: UUID??
}

extension SyncSessionFields: Codable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SyncSessionColumn.self)
        self.init(
            startTime: try c.decodeIfPresent(Date.self, forKey: .startTime),
            endTime: try c.decodePatch(Date.self, forKey: .endTime),
            location: try c.decodeIfPresent(String.self, forKey: .location),
            stakes: try c.decodeIfPresent(String.self, forKey: .stakes),
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            gameType: try c.decodeIfPresent(GameType.self, forKey: .gameType),
            status: try c.decodeIfPresent(SessionStatus.self, forKey: .status),
            buyIn: try c.decodeIfPresent(Double.self, forKey: .buyIn),
            rebuys: try c.decodeIfPresent(Double.self, forKey: .rebuys),
            addOns: try c.decodeIfPresent(Double.self, forKey: .addOns),
            cashOut: try c.decodeIfPresent(Double.self, forKey: .cashOut),
            tipRake: try c.decodeIfPresent(Double.self, forKey: .tipRake),
            tiltLevel: try c.decodePatch(Int.self, forKey: .tiltLevel),
            energyLevel: try c.decodePatch(Int.self, forKey: .energyLevel),
            focusLevel: try c.decodePatch(Int.self, forKey: .focusLevel),
            tableConfig: try c.decodePatch([String: SyncJSON].self, forKey: .tableConfig),
            loggingDeviceId: try c.decodePatch(UUID.self, forKey: .loggingDeviceId)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: SyncSessionColumn.self)
        try c.encodeIfPresent(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(stakes, forKey: .stakes)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(gameType, forKey: .gameType)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(buyIn.map(SyncCoding.cents), forKey: .buyIn)
        try c.encodeIfPresent(rebuys.map(SyncCoding.cents), forKey: .rebuys)
        try c.encodeIfPresent(addOns.map(SyncCoding.cents), forKey: .addOns)
        try c.encodeIfPresent(cashOut.map(SyncCoding.cents), forKey: .cashOut)
        try c.encodeIfPresent(tipRake.map(SyncCoding.cents), forKey: .tipRake)
        try c.encodeIfPresent(tiltLevel, forKey: .tiltLevel)
        try c.encodeIfPresent(energyLevel, forKey: .energyLevel)
        try c.encodeIfPresent(focusLevel, forKey: .focusLevel)
        try c.encodeIfPresent(tableConfig, forKey: .tableConfig)
        try c.encodeIfPresent(loggingDeviceId, forKey: .loggingDeviceId)
    }
}

/// A `hands` patch or create. `hand_number` is sent only on create (9.4), so
/// only `create` sets it; the patch initializer has no `handNumber`.
struct SyncHandFields: Equatable, Sendable {
    var sessionId: UUID?
    private(set) var handNumber: Int?
    var playedAt: Date?
    var preflopAction: PreflopAction?
    var faced3Bet: Bool?
    var threeBetResponse: ThreeBetResponse??
    var postflopResult: PostflopResult??
    var didCBet: Bool??
    var notes: String?
    var position: SeatPosition?

    /// A patch of the given columns.
    init(
        sessionId: UUID? = nil,
        playedAt: Date? = nil,
        preflopAction: PreflopAction? = nil,
        faced3Bet: Bool? = nil,
        threeBetResponse: ThreeBetResponse?? = nil,
        postflopResult: PostflopResult?? = nil,
        didCBet: Bool?? = nil,
        notes: String? = nil,
        position: SeatPosition? = nil
    ) {
        self.sessionId = sessionId
        self.playedAt = playedAt
        self.preflopAction = preflopAction
        self.faced3Bet = faced3Bet
        self.threeBetResponse = threeBetResponse
        self.postflopResult = postflopResult
        self.didCBet = didCBet
        self.notes = notes
        self.position = position
    }

    /// A create: `hand_number` plus every not-null column without a default
    /// (contract decision 3). Omitted nullable columns and `notes` take the
    /// server's defaults.
    static func create(
        sessionId: UUID,
        handNumber: Int,
        playedAt: Date,
        preflopAction: PreflopAction,
        faced3Bet: Bool,
        position: SeatPosition,
        threeBetResponse: ThreeBetResponse?? = nil,
        postflopResult: PostflopResult?? = nil,
        didCBet: Bool?? = nil,
        notes: String? = nil
    ) -> SyncHandFields {
        var fields = SyncHandFields(
            sessionId: sessionId,
            playedAt: playedAt,
            preflopAction: preflopAction,
            faced3Bet: faced3Bet,
            threeBetResponse: threeBetResponse,
            postflopResult: postflopResult,
            didCBet: didCBet,
            notes: notes,
            position: position
        )
        fields.handNumber = handNumber
        return fields
    }
}

extension SyncHandFields: Codable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SyncHandColumn.self)
        self.init(
            sessionId: try c.decodeIfPresent(UUID.self, forKey: .sessionId),
            playedAt: try c.decodeIfPresent(Date.self, forKey: .playedAt),
            preflopAction: try c.decodeIfPresent(PreflopAction.self, forKey: .preflopAction),
            faced3Bet: try c.decodeIfPresent(Bool.self, forKey: .faced3Bet),
            threeBetResponse: try c.decodePatch(ThreeBetResponse.self, forKey: .threeBetResponse),
            postflopResult: try c.decodePatch(PostflopResult.self, forKey: .postflopResult),
            didCBet: try c.decodePatch(Bool.self, forKey: .didCBet),
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            position: try c.decodeIfPresent(SeatPosition.self, forKey: .position)
        )
        handNumber = try c.decodeIfPresent(Int.self, forKey: .handNumber)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: SyncHandColumn.self)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(handNumber, forKey: .handNumber)
        try c.encodeIfPresent(playedAt, forKey: .playedAt)
        try c.encodeIfPresent(preflopAction, forKey: .preflopAction)
        try c.encodeIfPresent(faced3Bet, forKey: .faced3Bet)
        try c.encodeIfPresent(threeBetResponse, forKey: .threeBetResponse)
        try c.encodeIfPresent(postflopResult, forKey: .postflopResult)
        try c.encodeIfPresent(didCBet, forKey: .didCBet)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(position, forKey: .position)
    }
}

/// A `user_settings` patch. `default_buy_in` is money.
struct SyncSettingsFields: Equatable, Sendable {
    var defaultGameType: GameType?
    var defaultStakes: String?
    var defaultBuyIn: Double?
    var currency: String?
}

extension SyncSettingsFields: Codable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SyncSettingsColumn.self)
        self.init(
            defaultGameType: try c.decodeIfPresent(GameType.self, forKey: .defaultGameType),
            defaultStakes: try c.decodeIfPresent(String.self, forKey: .defaultStakes),
            defaultBuyIn: try c.decodeIfPresent(Double.self, forKey: .defaultBuyIn),
            currency: try c.decodeIfPresent(String.self, forKey: .currency)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: SyncSettingsColumn.self)
        try c.encodeIfPresent(defaultGameType, forKey: .defaultGameType)
        try c.encodeIfPresent(defaultStakes, forKey: .defaultStakes)
        try c.encodeIfPresent(defaultBuyIn.map(SyncCoding.cents), forKey: .defaultBuyIn)
        try c.encodeIfPresent(currency, forKey: .currency)
    }
}

// MARK: - Response (design sections 4.1 and 9.6)

/// The `sync_push` return value. Keys the client doesn't know are ignored.
enum SyncPushResponse: Decodable, Equatable, Sendable {
    /// The batch ran; `revision` is the account's `sync_state.revision`.
    case ok(revision: Int64, results: [SyncChangeResult])
    /// Stop pushing and keep the queue; ask the user to update.
    case upgradeRequired
    /// Drop the queue and local synced data, adopt the new epoch, pull.
    case wiped
    /// Final: the account was deleted. Never retried.
    case accountMissing
    /// The server couldn't read the envelope or it broke a batch limit.
    case invalid

    private enum CodingKeys: String, CodingKey {
        case status, revision, results
    }

    private enum Status: String, Decodable {
        case ok
        case upgradeRequired = "upgrade_required"
        case wiped
        case accountMissing = "account_missing"
        case invalid
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Status.self, forKey: .status) {
        case .ok:
            self = .ok(
                revision: try container.decode(Int64.self, forKey: .revision),
                results: try container.decode([SyncChangeResult].self, forKey: .results)
            )
        case .upgradeRequired: self = .upgradeRequired
        case .wiped: self = .wiped
        case .accountMissing: self = .accountMissing
        case .invalid: self = .invalid
        }
    }
}

/// What happened to one change in an `ok` push.
struct SyncChangeResult: Decodable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case applied
        /// `seq` at or below `last_applied_seq`: already applied.
        case skipped
        /// The row (or a hand's session) is purged; the op was ignored.
        case purged
        /// Drop the change and log the reason: a SQLSTATE such as `23503`,
        /// or a server code such as `unknown_table` or `disallowed_field`.
        case rejected(reason: String)
    }

    let seq: Int64
    let outcome: Outcome

    private enum CodingKeys: String, CodingKey {
        case seq, result, reason
    }

    private enum Result: String, Decodable {
        case applied, skipped, purged, rejected
    }

    init(seq: Int64, outcome: Outcome) {
        self.seq = seq
        self.outcome = outcome
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int64.self, forKey: .seq)
        switch try container.decode(Result.self, forKey: .result) {
        case .applied: outcome = .applied
        case .skipped: outcome = .skipped
        case .purged: outcome = .purged
        case .rejected: outcome = .rejected(reason: try container.decode(String.self, forKey: .reason))
        }
    }
}
