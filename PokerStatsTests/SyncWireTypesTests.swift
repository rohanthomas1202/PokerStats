import Foundation
import Testing
@testable import PokerStats

/// The 1.1 sync column map and wire types (#236), checked against design
/// sections 4.1, 9.4 and 9.5 and the contract in shared/fixtures/sync (#233).
/// The fixtures are copied into the test bundle: columns.json at its root and
/// the examples folder as `examples/<schema>/valid|invalid/`.
@Suite("Sync wire types")
struct SyncWireTypesTests {

    // MARK: - Switch

    @Test func syncFeature_isOff() {
        #expect(SyncFeature.isEnabled == false)
    }

    /// No app code outside Services/Sync and Services/Export names a sync type,
    /// so nothing in 1.0 calls into it while the switch is off.
    @Test func appCode_doesNotUseSyncTypes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let syncFolder = root.appendingPathComponent("PokerStats/Services/Sync").standardizedFileURL.path
        let exportFolder = root.appendingPathComponent("PokerStats/Services/Export").standardizedFileURL.path
        var checked = 0
        for folder in ["PokerStats", "PokerStatsWidgets"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift", !url.standardizedFileURL.path.hasPrefix(syncFolder + "/"),
                      !url.standardizedFileURL.path.hasPrefix(exportFolder + "/") else { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                #expect(source.range(of: #"\bSync[A-Z]"#, options: .regularExpression) == nil, "\(url.lastPathComponent) uses a sync type")
                checked += 1
            }
        }
        #expect(checked > 50)
    }

    // MARK: - Column map (9.4)

    @Test func columnMap_matchesColumnsJSON() throws {
        let tables = try #require(try SyncFixtures.object("columns", subdirectory: nil)["tables"] as? [String: Any])
        func check<Column: SyncColumn>(_ column: Column.Type, _ table: SyncTable) throws {
            let entry = try #require(tables[table.rawValue] as? [String: Any])
            let swift = try #require(entry["swift"] as? [String: Any])
            #expect(Column.swiftToColumn == swift["map"] as? [String: String], "\(table.rawValue) map")
            #expect(Column.clientColumns.map(\.rawValue) == entry["client_columns"] as? [String], "\(table.rawValue) client columns")
            #expect(Column.createOnly.map(\.rawValue) == entry["create_only"] as? [String], "\(table.rawValue) create only")
        }
        try check(SyncSessionColumn.self, .pokerSessions)
        try check(SyncHandColumn.self, .hands)
        try check(SyncSettingsColumn.self, .userSettings)
        #expect(Set(tables.keys) == Set(SyncTable.allCases.map(\.rawValue)))
    }

    /// The columns `convertToSnakeCase` gets wrong, and the renamed ones.
    @Test func columnMap_namesTheIrregularColumns() {
        let hands = SyncHandColumn.swiftToColumn
        #expect(hands["faced3Bet"] == "faced_3bet")
        #expect(hands["didCBet"] == "did_cbet")
        #expect(hands["session?.id"] == "session_id")
        #expect(hands["timestamp"] == "played_at")
        #expect(SyncSessionColumn.swiftToColumn["statusRaw"] == "status")
        #expect(SyncSessionColumn.swiftToColumn["tableConfigData"] == "table_config")
    }

    // MARK: - Encoding (4.1, 9.4)

    @Test func handUpsert_encodesToDesignExample() throws {
        let handId = try #require(UUID(uuidString: "0b9d4e6f-7a21-4c3b-8e5d-1f2a3b4c5d6e"))
        let sessionId = try #require(UUID(uuidString: "A3E1F7C2-5B84-4D6A-9C1E-2F7B0D9E8A41"))
        let request = SyncPushRequest(
            protocolVersion: SyncPushRequest.currentProtocol,
            deviceId: try #require(UUID(uuidString: "6f1c2a9e-3b7d-4c51-9e2a-0d4b8f7a1c3e")),
            appVersion: "1.1 (2026102601)",
            epoch: 0,
            changes: [
                .upsert(seq: 41, id: handId, fields: .hand(.create(
                    sessionId: sessionId,
                    handNumber: 17,
                    playedAt: Date(timeIntervalSince1970: 1_792_289_469),
                    preflopAction: .fold,
                    faced3Bet: false,
                    position: .btn
                ))),
                .upsert(seq: 42, id: sessionId, fields: .session(SyncSessionFields(notes: "tight table"))),
                .delete(seq: 43, table: .hands, id: handId),
            ],
            firstSyncDone: false
        )
        let encoded = try SyncCoding.encoder.encode(request)
        let expected = try SyncFixtures.data("design-4.1-example", subdirectory: "examples/push-request/valid")
        #expect(try SyncFixtures.canonical(encoded) == SyncFixtures.canonical(expected))

        // UTC with fractional seconds; the example's "02:11:09Z" is the same instant.
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains(#""played_at":"2026-10-18T02:11:09.000Z""#))
    }

    @Test func handNumber_isSentOnlyOnCreate() throws {
        let create = SyncHandFields.create(
            sessionId: UUID(), handNumber: 3, playedAt: .now, preflopAction: .call, faced3Bet: false, position: .co
        )
        let patch = SyncHandFields(didCBet: .some(nil), notes: "villain overbet river")
        #expect(try Self.keys(create).contains("hand_number"))
        #expect(try Self.keys(patch) == ["notes", "did_cbet"])
        #expect(patch.handNumber == nil)
    }

    @Test func nullableColumn_sendsNullOnlyWhenSet() throws {
        let fields = SyncSessionFields(endTime: .some(nil), cashOut: 412.5)
        let object = try Self.object(fields)
        #expect(Set(object.keys) == ["end_time", "cash_out"])
        #expect(object["end_time"] is NSNull)
    }

    @Test(arguments: [
        (0.005, 0.01), (-0.005, -0.01), (1.005, 1.01), (0.07, 0.07), (-12.345, -12.35), (412.5, 412.5),
        (200, 200), (0, 0), (Double("1e20")!, 999_999_999_999.99), (-1e20, -999_999_999_999.99),
        (.infinity, 999_999_999_999.99), (.nan, 0),
    ] as [(Double, Double)])
    func money_roundsToCentsAndClamps(_ value: Double, _ expected: Double) {
        #expect(SyncCoding.cents(value) == expected)
    }

    @Test func money_isRoundedWhenEncoded() throws {
        let session = try Self.object(SyncSessionFields(buyIn: 0.005, rebuys: -0.005, cashOut: Double("1e20")))
        #expect(session["buy_in"] as? Double == 0.01)
        #expect(session["rebuys"] as? Double == -0.01)
        #expect(session["cash_out"] as? Double == 999_999_999_999.99)
        let settings = try Self.object(SyncSettingsFields(defaultBuyIn: 199.999))
        #expect(settings["default_buy_in"] as? Double == 200)
    }

    @Test func dates_roundTripAsUTCWithFractions() throws {
        let date = Date(timeIntervalSince1970: 1_792_289_469.25)
        #expect(SyncCoding.string(from: date) == "2026-10-18T02:11:09.250Z")
        let fields = SyncSessionFields(startTime: date, endTime: .some(date.addingTimeInterval(3600)))
        let decoded = try SyncCoding.decoder.decode(SyncSessionFields.self, from: SyncCoding.encoder.encode(fields))
        #expect(decoded == fields)
        // Offsets are honored, and a timestamp without one is rejected.
        #expect(SyncCoding.date(from: "2026-10-18T07:41:09.25+05:30") == date)
        #expect(SyncCoding.date(from: "2026-10-18T02:11:10.481223+00:00") != nil)
        #expect(SyncCoding.date(from: "2026-10-18T02:11:09") == nil)
    }

    @Test func tableConfig_isSentAsAJSONObject() throws {
        let session = Session()
        session.tableConfig = TableConfig(
            seats: [TableSeat(index: 0, playerName: "", isOccupied: true), TableSeat(index: 1, playerName: "Ann", isOccupied: true)],
            heroSeatIndex: 0,
            buttonSeatIndex: -1
        )
        let object = try Self.object(try SyncSessionFields(creating: session))
        let config = try #require(object["table_config"] as? [String: Any])
        #expect(config["heroSeatIndex"] as? Int == 0)
        #expect(config["buttonSeatIndex"] as? Int == -1)
        #expect((config["seats"] as? [Any])?.count == 2)
        #expect(object["logging_device_id"] == nil)
    }

    @Test func tableConfig_objectBytesDecodeToThatObject() throws {
        let session = Session()
        session.tableConfigData = Data(#"{"seats":9,"heroSeat":3}"#.utf8)
        let fields = try SyncSessionFields(creating: session)
        #expect(fields.tableConfig == .some(["seats": .number(9), "heroSeat": .number(3)]))
    }

    @Test func tableConfig_missingIsSentAsNull() throws {
        let session = Session()
        #expect(session.tableConfigData == nil)
        let fields = try SyncSessionFields(creating: session)
        #expect(fields.tableConfig == .some(nil))
    }

    /// Bytes that are not a JSON object throw instead of sending null.
    @Test(arguments: [#"{not-json"#, #"[1,2]"#, #""seats""#, "null"])
    func tableConfig_nonObjectBytesThrow(_ bytes: String) {
        let session = Session()
        session.tableConfigData = Data(bytes.utf8)
        #expect(throws: (any Error).self) { try SyncSessionFields(creating: session) }
    }

    @Test @MainActor func createFromModels_sendsEveryClientColumn() throws {
        let container = try TestHelpers.createContainer()
        let session = Session(buyIn: 200, cashOut: 412.5)
        container.mainContext.insert(session)
        let hand = Hand(handNumber: 4, preflopAction: .raise, faced3Bet: true, threeBetResponse: .called, position: .btn)
        container.mainContext.insert(hand)
        hand.session = session
        let sessionKeys = try Self.keys(try SyncSessionFields(creating: session))
        #expect(sessionKeys == Set(SyncSessionColumn.clientColumns.map(\.rawValue)).subtracting(["logging_device_id"]))
        let handFields = try #require(SyncHandFields(creating: hand))
        #expect(try Self.keys(handFields) == Set(SyncHandColumn.clientColumns.map(\.rawValue)))
        #expect(handFields.sessionId == session.id)
        #expect(SyncHandFields(creating: Hand()) == nil)
        #expect(try Self.keys(SyncSettingsFields(Settings())) == Set(SyncSettingsColumn.clientColumns.map(\.rawValue)))
    }

    // MARK: - Responses (4.1, 9.6)

    @Test func everyResponseStatusAndResult_decodes() throws {
        let cases: [(String, SyncPushResponse)] = [
            ("ok-empty", .ok(revision: 0, results: [])),
            ("ok-applied-skipped", .ok(revision: 1043, results: [
                SyncChangeResult(seq: 41, outcome: .skipped),
                SyncChangeResult(seq: 42, outcome: .applied),
                SyncChangeResult(seq: 43, outcome: .applied),
            ])),
            ("ok-purged", .ok(revision: 1044, results: [SyncChangeResult(seq: 44, outcome: .purged)])),
            ("ok-rejected-sqlstate", .ok(revision: 1045, results: [
                SyncChangeResult(seq: 45, outcome: .rejected(reason: "23503")),
                SyncChangeResult(seq: 46, outcome: .applied),
            ])),
            ("ok-rejected-unknown-table", .ok(revision: 1045, results: [
                SyncChangeResult(seq: 47, outcome: .rejected(reason: "unknown_table")),
            ])),
            ("ok-rejected-disallowed-field", .ok(revision: 1046, results: [
                SyncChangeResult(seq: 48, outcome: .rejected(reason: "disallowed_field")),
            ])),
            ("ok-unknown-key-ignored", .ok(revision: 7, results: [])),
            ("upgrade-required", .upgradeRequired),
            ("wiped", .wiped),
            ("account-missing", .accountMissing),
            ("invalid", .invalid),
        ]
        let names = Set(try SyncFixtures.names(in: "examples/push-response/valid"))
        #expect(names == Set(cases.map(\.0)), "every valid response example is checked")
        for (name, expected) in cases {
            let data = try SyncFixtures.data(name, subdirectory: "examples/push-response/valid")
            #expect(try SyncCoding.decoder.decode(SyncPushResponse.self, from: data) == expected, "\(name)")
        }
    }

    // MARK: - Reading (9.5)

    @Test func unknownStatus_decodesAsCompleted() throws {
        #expect(try Self.pulledSession(status: "paused", endTime: "2026-10-18T05:00:00Z").resolvedStatus == .completed)
        #expect(try Self.pulledSession(status: "", endTime: nil).resolvedStatus == .completed)
        #expect(try Self.pulledSession(status: "active", endTime: nil).resolvedStatus == .active)
        #expect(try Self.pulledSession(status: "completed", endTime: nil).resolvedStatus == .completed)
    }

    /// Disagreement 12: completed with no end time ends at its start time.
    @Test func completedWithoutEndTime_endsAtStartTime() throws {
        let row = try Self.pulledSession(status: "completed", endTime: nil)
        #expect(row.resolvedEndTime == row.startTime)
        #expect(try Self.pulledSession(status: "unknown-future", endTime: nil).resolvedEndTime == row.startTime)
        #expect(try Self.pulledSession(status: "active", endTime: nil).resolvedEndTime == nil)
        let ended = try Self.pulledSession(status: "completed", endTime: "2026-10-18T05:00:00Z")
        #expect(ended.resolvedEndTime == SyncCoding.date(from: "2026-10-18T05:00:00Z"))

        // As a session: duration 0 and no hourly rate; net profit still counts.
        let session = Session(
            startTime: row.startTime, endTime: row.resolvedEndTime, status: row.resolvedStatus,
            buyIn: row.buyIn, cashOut: row.cashOut
        )
        #expect(session.duration == 0)
        #expect(session.hourlyRate == nil)
        #expect(session.netProfit == 212.5)
    }

    @Test func unknownEnumValues_useExistingFallbacks() throws {
        let hand = try Self.pulledHand(preflop: "limp", faced3Bet: false, response: "shove", postflop: "chopped", position: "UTG+2")
        #expect(hand.resolvedPreflopAction == .fold)
        #expect(hand.resolvedThreeBetResponse == nil)
        #expect(hand.resolvedPostflopResult == nil)
        #expect(hand.resolvedPosition == .unknown)
        #expect(try Self.pulledSession(status: "completed", endTime: nil, gameType: "mixed").resolvedGameType == .cash)
        // The row keeps the server's values, so a fallback is never written back.
        #expect(hand.preflopAction == "limp")
    }

    /// Kate's Low 1 on PR #291: a 3-bet is faced only after a preflop raise.
    @Test func faced3Bet_onANonRaise_isNormalized() throws {
        for preflop in ["fold", "call"] {
            let hand = try Self.pulledHand(preflop: preflop, faced3Bet: true, response: "folded", postflop: nil, position: "BTN")
            #expect(hand.resolvedFaced3Bet == false, "\(preflop)")
            #expect(hand.resolvedThreeBetResponse == nil, "\(preflop)")
        }
        let raise = try Self.pulledHand(preflop: "raise", faced3Bet: true, response: "folded", postflop: nil, position: "BTN")
        #expect(raise.resolvedFaced3Bet)
        #expect(raise.resolvedThreeBetResponse == .folded)
        let noThreeBet = try Self.pulledHand(preflop: "raise", faced3Bet: false, response: "called", postflop: nil, position: "BTN")
        #expect(noThreeBet.resolvedThreeBetResponse == nil)
    }

    // MARK: - Contract fixtures (#233)

    /// Every valid push request decodes and encodes back to the same JSON
    /// (UUID case and timestamp format aside).
    @Test(arguments: (try? SyncFixtures.names(in: "examples/push-request/valid")) ?? [])
    func validPushRequest_roundTrips(_ name: String) throws {
        let data = try SyncFixtures.data(name, subdirectory: "examples/push-request/valid")
        let request = try SyncCoding.decoder.decode(SyncPushRequest.self, from: data)
        #expect(try SyncFixtures.canonical(SyncCoding.encoder.encode(request)) == SyncFixtures.canonical(data))
    }

    @Test func validPushRequests_areAllPresent() throws {
        #expect(try SyncFixtures.names(in: "examples/push-request/valid").sorted() == [
            "changes-500", "create-session-and-hand", "delete-and-restore", "design-4.1-example",
            "first-sync-done-empty", "patch-fields",
        ])
    }

    @Test func validPulls_decode() throws {
        let sessions = try Self.decode([SyncPulledSession].self, "page", "pull-poker-sessions")
        #expect(sessions.count == 1)
        #expect(sessions.first?.tableConfig == ["seats": .number(9), "heroSeat": .number(3)])
        #expect(sessions.first?.resolvedStatus == .active)
        #expect(sessions.first?.meta.revision == 1042)
        #expect(try Self.decode([SyncPulledSession].self, "empty-page", "pull-poker-sessions").isEmpty)

        let hands = try Self.decode([SyncPulledHand].self, "page-with-purged-stub", "pull-hands")
        #expect(hands.map(\.handNumber) == [17, 0])
        #expect(hands.first?.resolvedPostflopResult == .wonBeforeShowdown)
        #expect(hands.first?.resolvedPosition == .btn)
        #expect(hands.last?.meta.purgedAt != nil)
        #expect(hands.last?.resolvedPosition == .unknown)
        #expect(try Self.decode([SyncPulledHand].self, "unknown-column-ignored", "pull-hands").count == 1)

        let settings = try Self.decode([SyncPulledSettings].self, "page", "pull-user-settings")
        #expect(settings.first?.resolvedDefaultGameType == .cash)
        #expect(settings.first?.defaultBuyIn == 200)

        let state = try Self.decode([SyncStateRow].self, "one-row", "pull-sync-state")
        #expect(state.first?.revision == 1043)
        #expect(state.first?.wipeEpoch == 0)
        #expect(try Self.decode([SyncStateRow].self, "account-missing", "pull-sync-state").isEmpty)
    }

    /// Invalid examples the wire types reject on their own. Limits and
    /// patterns the schema checks (lengths, ranges, seq, protocol) are left to
    /// the contract and the server.
    @Test(arguments: [
        "push-request/invalid/delete-with-fields",
        "push-request/invalid/device-id-not-uuid",
        "push-request/invalid/epoch-is-string",
        "push-request/invalid/faced-3bet-not-boolean",
        "push-request/invalid/missing-device-id",
        "push-request/invalid/missing-first-sync-done",
        "push-request/invalid/op-unknown",
        "push-request/invalid/played-at-no-offset",
        "push-request/invalid/table-config-as-string",
        "push-request/invalid/table-unknown",
        "push-request/invalid/upsert-without-fields",
        "push-response/invalid/missing-status",
        "push-response/invalid/ok-missing-revision",
        "push-response/invalid/ok-results-not-array",
        "push-response/invalid/rejected-without-reason",
        "push-response/invalid/result-unknown",
        "push-response/invalid/status-unknown",
        "pull-hands/invalid/row-missing-revision",
        "pull-hands/invalid/row-revision-is-string",
        "pull-poker-sessions/invalid/row-table-config-as-string",
        "pull-user-settings/invalid/row-default-buy-in-null",
        "pull-sync-state/invalid/missing-wipe-epoch",
    ])
    func invalidExample_failsToDecode(_ path: String) throws {
        let parts = path.split(separator: "/").map(String.init)
        let data = try SyncFixtures.data(parts[2], subdirectory: "examples/\(parts[0])/\(parts[1])")
        let decoder = SyncCoding.decoder
        #expect(throws: (any Error).self, "\(path)") {
            switch parts[0] {
            case "push-request": _ = try decoder.decode(SyncPushRequest.self, from: data)
            case "push-response": _ = try decoder.decode(SyncPushResponse.self, from: data)
            case "pull-hands": _ = try decoder.decode([SyncPulledHand].self, from: data)
            case "pull-poker-sessions": _ = try decoder.decode([SyncPulledSession].self, from: data)
            case "pull-user-settings": _ = try decoder.decode([SyncPulledSettings].self, from: data)
            default: _ = try decoder.decode([SyncStateRow].self, from: data)
            }
        }
    }

    // MARK: - Helpers

    private static func object(_ value: some Encodable) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: SyncCoding.encoder.encode(value)) as? [String: Any])
    }

    private static func keys(_ value: some Encodable) throws -> Set<String> {
        Set(try object(value).keys)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ name: String, _ schema: String) throws -> T {
        try SyncCoding.decoder.decode(T.self, from: SyncFixtures.data(name, subdirectory: "examples/\(schema)/valid"))
    }

    private static func pulledSession(status: String, endTime: String?, gameType: String = "cash") throws -> SyncPulledSession {
        let row: [String: Any] = [
            "id": UUID().uuidString, "start_time": "2026-10-18T01:00:00.000Z", "end_time": endTime.map { $0 as Any } ?? NSNull(),
            "location": "", "stakes": "1/2", "notes": "", "game_type": gameType, "status": status,
            "buy_in": 200, "rebuys": 0, "add_ons": 0, "cash_out": 412.5, "tip_rake": 0,
            "tilt_level": NSNull(), "energy_level": NSNull(), "focus_level": NSNull(),
            "table_config": NSNull(), "logging_device_id": NSNull(),
        ].merging(metaColumns) { $1 }
        return try SyncCoding.decoder.decode(SyncPulledSession.self, from: JSONSerialization.data(withJSONObject: row))
    }

    private static func pulledHand(preflop: String, faced3Bet: Bool, response: String?, postflop: String?, position: String) throws -> SyncPulledHand {
        let row: [String: Any] = [
            "id": UUID().uuidString, "session_id": UUID().uuidString, "hand_number": 1,
            "played_at": "2026-10-18T02:11:09.250Z", "preflop_action": preflop, "faced_3bet": faced3Bet,
            "three_bet_response": response.map { $0 as Any } ?? NSNull(),
            "postflop_result": postflop.map { $0 as Any } ?? NSNull(),
            "did_cbet": NSNull(), "notes": "", "position": position,
        ].merging(metaColumns) { $1 }
        return try SyncCoding.decoder.decode(SyncPulledHand.self, from: JSONSerialization.data(withJSONObject: row))
    }

    private static var metaColumns: [String: Any] { [
        "user_id": "5d4c3b2a-1f0e-4d9c-8b7a-6f5e4d3c2b1a", "revision": 1,
        "server_updated_at": "2026-10-18T02:11:10.481223+00:00",
        "deleted_at": NSNull(), "purged_at": NSNull(), "updated_by_device": NSNull(),
    ] }
}

/// Loads the sync contract fixtures from the test bundle.
enum SyncFixtures {
    struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    private final class BundleToken {}

    static var bundle: Bundle { Bundle(for: BundleToken.self) }

    static func data(_ name: String, subdirectory: String?) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            throw Missing(description: "\(subdirectory.map { "\($0)/" } ?? "")\(name).json is not in the test bundle")
        }
        return try Data(contentsOf: url)
    }

    static func object(_ name: String, subdirectory: String?) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data(name, subdirectory: subdirectory)) as? [String: Any] else {
            throw Missing(description: "\(name).json is not an object")
        }
        return object
    }

    /// Fixture names (without .json) in a folder, sorted.
    static func names(in subdirectory: String) throws -> [String] {
        let names = (bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        guard !names.isEmpty else { throw Missing(description: "\(subdirectory) is not in the test bundle") }
        return names
    }

    /// The JSON with UUIDs uppercased and timestamps as instants, so two
    /// encodings of the same values compare equal.
    static func canonical(_ data: Data) throws -> SyncJSON {
        func normalize(_ json: SyncJSON) -> SyncJSON {
            switch json {
            case .string(let text):
                if let uuid = UUID(uuidString: text) { return .string(uuid.uuidString) }
                if let date = SyncCoding.date(from: text) { return .number(date.timeIntervalSince1970) }
                return json
            case .array(let values): return .array(values.map(normalize))
            case .object(let values): return .object(values.mapValues(normalize))
            default: return json
            }
        }
        return normalize(try JSONDecoder().decode(SyncJSON.self, from: data))
    }
}
