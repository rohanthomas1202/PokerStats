import Foundation

/// The tables a push may change (docs/design/1.1-sync.md section 4.1).
enum SyncTable: String, Codable, CaseIterable, Sendable {
    case pokerSessions = "poker_sessions"
    case hands
    case userSettings = "user_settings"
}

// MARK: - Column map (design section 9.4)

/// One table's columns. Each case's raw value is the column and `swiftName`
/// is the model property it maps to, as listed in design section 9.4 and
/// shared/fixtures/sync/columns.json. The sync wire types code their keys with
/// these enums only; nothing here uses `convertToSnakeCase`, which would turn
/// `faced3Bet` into `faced3_bet` and `didCBet` into `did_c_bet`.
protocol SyncColumn: CodingKey, CaseIterable, Hashable, Sendable, RawRepresentable where RawValue == String {
    var swiftName: String { get }
    /// Columns sent only when the row is created.
    static var createOnly: [Self] { get }
}

extension SyncColumn {
    static var createOnly: [Self] { [] }

    /// The keys a push's `fields` may contain. `id` travels as the change's
    /// `id`, and `deleted_at` is set only by the `delete` and `restore` ops.
    static var clientColumns: [Self] {
        allCases.filter { $0.rawValue != "id" && $0.rawValue != "deleted_at" }
    }

    /// Swift property name to column name.
    static var swiftToColumn: [String: String] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.swiftName, $0.rawValue) })
    }
}

/// `Session` and `poker_sessions`.
enum SyncSessionColumn: String, SyncColumn {
    case id
    case startTime = "start_time"
    case endTime = "end_time"
    case location
    case stakes
    case notes
    case gameType = "game_type"
    case status
    case buyIn = "buy_in"
    case rebuys
    case addOns = "add_ons"
    case cashOut = "cash_out"
    case tipRake = "tip_rake"
    case tiltLevel = "tilt_level"
    case energyLevel = "energy_level"
    case focusLevel = "focus_level"
    case tableConfig = "table_config"
    case loggingDeviceId = "logging_device_id"
    case deletedAt = "deleted_at"

    var swiftName: String {
        switch self {
        case .id: "id"
        case .startTime: "startTime"
        case .endTime: "endTime"
        case .location: "location"
        case .stakes: "stakes"
        case .notes: "notes"
        case .gameType: "gameType"
        case .status: "statusRaw"
        case .buyIn: "buyIn"
        case .rebuys: "rebuys"
        case .addOns: "addOns"
        case .cashOut: "cashOut"
        case .tipRake: "tipRake"
        case .tiltLevel: "tiltLevel"
        case .energyLevel: "energyLevel"
        case .focusLevel: "focusLevel"
        case .tableConfig: "tableConfigData"
        case .loggingDeviceId: "loggingDeviceId"
        case .deletedAt: "deletedAt"
        }
    }
}

/// `Hand` and `hands`.
enum SyncHandColumn: String, SyncColumn {
    case id
    case sessionId = "session_id"
    case handNumber = "hand_number"
    case playedAt = "played_at"
    case deletedAt = "deleted_at"
    case preflopAction = "preflop_action"
    case faced3Bet = "faced_3bet"
    case threeBetResponse = "three_bet_response"
    case postflopResult = "postflop_result"
    case didCBet = "did_cbet"
    case notes
    case position

    var swiftName: String {
        switch self {
        case .id: "id"
        case .sessionId: "session?.id"
        case .handNumber: "handNumber"
        case .playedAt: "timestamp"
        case .deletedAt: "deletedAt"
        case .preflopAction: "preflopAction"
        case .faced3Bet: "faced3Bet"
        case .threeBetResponse: "threeBetResponse"
        case .postflopResult: "postflopResult"
        case .didCBet: "didCBet"
        case .notes: "notes"
        case .position: "position"
        }
    }

    /// `hand_number` is write-once: set on insert, never patched (9.4).
    static var createOnly: [SyncHandColumn] { [.handNumber] }
}

/// `Settings` and `user_settings`. The local `Settings.id` is not synced
/// (design 2.6); a settings change carries the account's user ID as its `id`.
enum SyncSettingsColumn: String, SyncColumn {
    case defaultGameType = "default_game_type"
    case defaultStakes = "default_stakes"
    case defaultBuyIn = "default_buy_in"
    case currency

    var swiftName: String {
        switch self {
        case .defaultGameType: "defaultGameType"
        case .defaultStakes: "defaultStakes"
        case .defaultBuyIn: "defaultBuyIn"
        case .currency: "currency"
        }
    }
}

/// Sync columns every pulled row has (design section 2). Set by the server,
/// never sent in `fields`.
enum SyncMetaColumn: String, CodingKey, CaseIterable, Sendable {
    case userId = "user_id"
    case revision
    case serverUpdatedAt = "server_updated_at"
    case deletedAt = "deleted_at"
    case purgedAt = "purged_at"
    case updatedByDevice = "updated_by_device"
}
