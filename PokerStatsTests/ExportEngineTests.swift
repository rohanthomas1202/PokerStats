import Foundation
import SwiftData
import Testing
@testable import PokerStats

@Suite("Export engine")
@MainActor
struct ExportEngineTests {
    @Test func goldenFiles_matchExactlyAndIgnoreFetchOrder() throws {
        let fixture = try ExportFixture()
        let files = try fixture.export()
        #expect(files.sessionsCSV == (try Self.data("sessions.csv")))
        #expect(files.handsCSV == (try Self.data("hands.csv")))
        #expect(files.json == (try Self.data("pokerstats-export.json")))
        #expect(files == (try ExportEngine.makeFiles(
            sessions: Array(fixture.sessions.reversed()), hands: Array(fixture.hands.reversed()), settings: fixture.settings
        )))
        let json = try Self.document(files.json)
        #expect(Set(json.keys) == ["format_version", "sessions", "hands"])
        #expect(json["format_version"] as? Int == 1)
        let sessions = try #require(json["sessions"] as? [[String: Any]])
        let hands = try #require(json["hands"] as? [[String: Any]])
        #expect(sessions.count == 3)
        #expect(hands.count == 3)
        for row in sessions { #expect(Set(row.keys) == Set(ExportEngine.sessionColumns)) }
        for row in hands { #expect(Set(row.keys) == Set(ExportEngine.handColumns)) }
        #expect(sessions[0]["table_config"] is [String: Any])
        #expect(sessions[1]["table_config"] is NSNull)
        #expect(sessions[2]["end_time"] is NSNull)
        #expect(sessions.allSatisfy { $0["currency"] as? String == "CAD" })
    }

    /// Same definitions and calculator path as StatFixtureTests: only completed
    /// sessions count toward money stats; every live hand counts, even active ones.
    /// tip_rake is exported but is NOT subtracted from net profit.
    @Test func csvAndJSON_countsAndMoneyMatchDashboard() throws {
        let fixture = try ExportFixture()
        let files = try fixture.export()
        let dashboard = DashboardViewModel()
        dashboard.loadData(from: fixture.container.mainContext)
        let stats = dashboard.lifetimeStats
        #expect(stats.sessionsPlayed == 2)
        #expect(stats.totalHands == 3)
        #expect(abs(stats.totalProfit - 32.18) < 1e-9)

        let json = try Self.document(files.json)
        let jsonSessions = try #require(json["sessions"] as? [[String: Any]])
        let jsonHands = try #require(json["hands"] as? [[String: Any]])
        let csvSessions = try Self.csv(files.sessionsCSV)
        let csvHands = try Self.csv(files.handsCSV)
        #expect(jsonSessions.count == fixture.sessions.count)
        #expect(csvSessions.count == fixture.sessions.count)
        #expect(jsonHands.count == stats.totalHands)
        #expect(csvHands.count == stats.totalHands)

        // Check every money column in both formats against the original models,
        // not just a grand total that could hide offsetting row errors.
        for session in fixture.sessions {
            let jsonRow = try #require(jsonSessions.first { $0["id"] as? String == session.id.uuidString })
            let csvRow = try #require(csvSessions.first { $0["id"] == session.id.uuidString })
            let amounts = ["buy_in": session.buyIn, "rebuys": session.rebuys, "add_ons": session.addOns,
                           "cash_out": session.cashOut, "tip_rake": session.tipRake]
            for (column, amount) in amounts {
                #expect(try #require(jsonRow[column] as? Double) == amount)
                #expect(try #require(csvRow[column].flatMap(Double.init)) == amount)
            }
            let invested = try Self.number(jsonRow, "buy_in") + Self.number(jsonRow, "rebuys") + Self.number(jsonRow, "add_ons")
            #expect(abs(invested - session.totalInvested) < 1e-9)
            #expect(abs((try Self.number(jsonRow, "cash_out")) - invested - session.netProfit) < 1e-9)
        }
        let completedJSON = jsonSessions.filter { $0["status"] as? String == "completed" }
        let completedCSV = csvSessions.filter { $0["status"] == "completed" }
        #expect(completedJSON.count == stats.sessionsPlayed)
        #expect(completedCSV.count == stats.sessionsPlayed)
        let jsonProfit = try completedJSON.reduce(0.0) { total, row in
            try total + Self.number(row, "cash_out") - (Self.number(row, "buy_in") + Self.number(row, "rebuys") + Self.number(row, "add_ons"))
        }
        let csvProfit = try completedCSV.reduce(0.0) { total, row in
            let amounts = try ["cash_out", "buy_in", "rebuys", "add_ons"].map { try #require(row[$0].flatMap(Double.init)) }
            return total + amounts[0] - (amounts[1] + amounts[2] + amounts[3])
        }
        #expect(abs(jsonProfit - stats.totalProfit) < 1e-9)
        #expect(abs(csvProfit - stats.totalProfit) < 1e-9)
    }

    @Test func quoting_preservesNotesAndTableConfig() throws {
        let fixture = try ExportFixture()
        let files = try fixture.export()
        let sessionRows = try Self.csv(files.sessionsCSV)
        let handRows = try Self.csv(files.handsCSV)
        #expect(sessionRows[0]["notes"] == fixture.sessions[0].notes)
        #expect(handRows[0]["notes"] == fixture.hands[0].notes)
        #expect(String(decoding: files.sessionsCSV, as: UTF8.self).contains("\"He said \"\"call\"\", then left.\nBon jeu — 東京\""))
        let configText = try #require(sessionRows[0]["table_config"])
        #expect(try JSONDecoder().decode(TableConfig.self, from: Data(configText.utf8)) == fixture.sessions[0].tableConfig)

        // CR as well as LF must trigger quoting, including a CR-only value.
        for notes in ["carriage\rreturn", "two\r\nlines", "two\nlines"] {
            fixture.sessions[0].notes = notes
            let changed = try fixture.export()
            #expect(String(decoding: changed.sessionsCSV, as: UTF8.self).contains("\"" + notes + "\""))
            #expect(try Self.csv(changed.sessionsCSV)[0]["notes"] == notes)
        }
    }

    @Test func emptyAccount_isHeaderOnlyAndValidJSON() throws {
        let files = try ExportEngine.makeFiles(sessions: [], hands: [], settings: Settings())
        for (actual, name) in [(files.sessionsCSV, "sessions.csv"), (files.handsCSV, "hands.csv")] {
            let header = try #require(String(decoding: try Self.data(name), as: UTF8.self).split(separator: "\n").first)
            #expect(actual == Data((String(header) + "\n").utf8))
            #expect(try Self.csv(actual).isEmpty)
        }
        #expect(String(decoding: files.json, as: UTF8.self) == "{\"format_version\":1,\"hands\":[],\"sessions\":[]}\n")
        let json = try Self.document(files.json)
        #expect((json["sessions"] as? [Any])?.isEmpty == true)
        #expect((json["hands"] as? [Any])?.isEmpty == true)
    }

    @Test func moneyAndDates_followSyncCoding() throws {
        let session = Session(startTime: try #require(SyncCoding.date(from: "2026-10-18T07:41:09.250+05:30")),
                              buyIn: 1.005, rebuys: 0.07, addOns: -12.345, cashOut: 1e20)
        let files = try ExportEngine.makeFiles(sessions: [session], hands: [], settings: Settings(currency: "EUR"))
        let rows = try Self.csv(files.sessionsCSV)
        #expect(rows[0]["start_time"] == "2026-10-18T02:11:09.250Z")
        #expect(rows[0]["buy_in"] == "1.01")
        #expect(rows[0]["rebuys"] == "0.07")
        #expect(rows[0]["add_ons"] == "-12.35")
        #expect(rows[0]["cash_out"] == "999999999999.99")
        #expect(rows[0]["currency"] == "EUR")
        let json = try Self.document(files.json)
        let row = try #require((json["sessions"] as? [[String: Any]])?.first)
        #expect(row["start_time"] as? String == SyncCoding.string(from: session.startTime))
        #expect(row["buy_in"] as? Double == SyncCoding.cents(session.buyIn))
        #expect(row["cash_out"] as? Double == SyncCoding.cents(session.cashOut))
    }

    @Test func invalidRows_throwRatherThanLoseData() throws {
        let orphan = Hand()
        #expect(throws: ExportEngine.Failure.handWithoutSession(orphan.id)) {
            try ExportEngine.makeFiles(sessions: [], hands: [orphan], settings: Settings())
        }
        let session = Session()
        session.tableConfigData = Data("not JSON".utf8)
        #expect(throws: (any Error).self) {
            try ExportEngine.makeFiles(sessions: [session], hands: [], settings: Settings())
        }
        #expect(session.tableConfigData == Data("not JSON".utf8))
    }

    @Test func appCode_doesNotUseExportTypes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let excluded = ["Export", "Sync"].map { root.appendingPathComponent("PokerStats/Services/\($0)/").standardizedFileURL.path + "/" }
        var checked = 0
        for folder in ["PokerStats", "PokerStatsWidgets"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift", !excluded.contains(where: { url.standardizedFileURL.path.hasPrefix($0) }) else { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                #expect(source.range(of: #"\bExport(?:Engine|Files)\b"#, options: .regularExpression) == nil, "\(url.lastPathComponent) uses export")
                checked += 1
            }
        }
        #expect(checked > 50)
    }

    private static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: ExportBundle.self).url(forResource: name, withExtension: nil, subdirectory: "export"))
        return try Data(contentsOf: url)
    }

    private static func document(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func number(_ row: [String: Any], _ column: String) throws -> Double {
        try #require(row[column] as? Double)
    }

    /// Independent reader: handles embedded newlines and doubled quotes, so
    /// count checks cannot accidentally count the lines inside a notes cell.
    private static func csv(_ data: Data) throws -> [[String: String]] {
        var records: [[String]] = [], record: [String] = []
        var cell = "", quoted = false
        let text = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        var i = 0
        while i < text.count {
            let c = text[i]
            if c == "\"" {
                if quoted && i + 1 < text.count && text[i + 1] == "\"" { cell.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted {
                record.append(cell); cell = ""
            } else if c == "\n" && !quoted {
                record.append(cell); records.append(record); record = []; cell = ""
            } else { cell.unicodeScalars.append(c) }
            i += 1
        }
        #expect(!quoted)
        #expect(record.isEmpty && cell.isEmpty, "CSV must end in LF")
        let header = try #require(records.first)
        return try records.dropFirst().map { values in
            #expect(values.count == header.count)
            guard values.count == header.count else { throw ExportFixture.Invalid.row }
            return Dictionary(uniqueKeysWithValues: zip(header, values))
        }
    }
}

private final class ExportBundle {}

@MainActor
private struct ExportFixture {
    enum Invalid: Error { case row }
    struct Input: Decodable {
        let currency: String
        let sessions: [SessionInput]
        let hands: [HandInput]
    }
    struct SessionInput: Decodable {
        let id: UUID
        let fields: SyncSessionFields
        private enum CodingKeys: String, CodingKey { case id }
        init(from decoder: any Decoder) throws {
            id = try decoder.container(keyedBy: CodingKeys.self).decode(UUID.self, forKey: .id)
            fields = try SyncSessionFields(from: decoder)
        }
    }
    struct HandInput: Decodable {
        let id: UUID
        let fields: SyncHandFields
        private enum CodingKeys: String, CodingKey { case id }
        init(from decoder: any Decoder) throws {
            id = try decoder.container(keyedBy: CodingKeys.self).decode(UUID.self, forKey: .id)
            fields = try SyncHandFields(from: decoder)
        }
    }
    let container: ModelContainer
    let sessions: [Session]
    let hands: [Hand]
    let settings: Settings

    init() throws {
        let url = try #require(Bundle(for: ExportBundle.self).url(forResource: "dataset", withExtension: "json", subdirectory: "export"))
        let input = try SyncCoding.decoder.decode(Input.self, from: Data(contentsOf: url))
        let container = try TestHelpers.createContainer()
        let context = container.mainContext
        var sessions: [Session] = []
        for row in input.sessions {
            let f = row.fields
            let session = try Session(
                id: row.id, startTime: #require(f.startTime), endTime: f.endTime ?? nil,
                location: #require(f.location), gameType: #require(f.gameType), stakes: #require(f.stakes),
                notes: #require(f.notes), status: #require(f.status), buyIn: #require(f.buyIn),
                rebuys: #require(f.rebuys), addOns: #require(f.addOns), cashOut: #require(f.cashOut), tipRake: #require(f.tipRake)
            )
            session.tiltLevel = f.tiltLevel ?? nil
            session.energyLevel = f.energyLevel ?? nil
            session.focusLevel = f.focusLevel ?? nil
            session.tableConfigData = try (f.tableConfig ?? nil).map { try JSONEncoder().encode($0) }
            context.insert(session)
            sessions.append(session)
        }
        var hands: [Hand] = []
        for row in input.hands {
            let f = row.fields
            let hand = try Hand(
                id: row.id, handNumber: #require(f.handNumber), timestamp: #require(f.playedAt),
                preflopAction: #require(f.preflopAction), faced3Bet: #require(f.faced3Bet),
                threeBetResponse: f.threeBetResponse ?? nil, postflopResult: f.postflopResult ?? nil,
                didCBet: f.didCBet ?? nil, notes: #require(f.notes), position: #require(f.position)
            )
            context.insert(hand)
            hand.session = try #require(sessions.first { $0.id == f.sessionId })
            hands.append(hand)
        }
        try context.save()
        self.container = container
        self.sessions = sessions
        self.hands = hands
        self.settings = Settings(currency: input.currency)
    }

    func export() throws -> ExportFiles {
        try ExportEngine.makeFiles(sessions: sessions, hands: hands, settings: settings)
    }
}
