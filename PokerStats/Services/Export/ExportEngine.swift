import Foundation

/// In-memory UTF-8 files. The caller decides whether and where to save or share them.
struct ExportFiles: Equatable, Sendable {
    let sessionsCSV: Data
    let handsCSV: Data
    let json: Data
}

/// Local rows only; no fetches, writes, network, or UI. Not called by the 1.0 app.
enum ExportEngine {
    enum Failure: Error, Equatable {
        case handWithoutSession(UUID)
    }

    static let sessionColumns = SyncSessionColumn.allCases
        .filter { $0 != .loggingDeviceId && $0 != .deletedAt }
        .map(\.rawValue) + [SyncSettingsColumn.currency.rawValue]
    static let handColumns = SyncHandColumn.allCases
        .filter { $0 != .deletedAt }.map(\.rawValue)

    /// Stable UUID order, independent of fetch order. Nullable values are JSON
    /// null and empty CSV cells. Invalid table_config bytes throw, never disappear.
    /// A hand without a session also throws rather than silently losing a row.
    static func makeFiles(sessions: [Session], hands: [Hand], settings: Settings) throws -> ExportFiles {
        let sessionRows = try sessions.sorted { $0.id.uuidString < $1.id.uuidString }.map { session in
            var row = try object(try SyncSessionFields(creating: session))
            row[SyncSessionColumn.id.rawValue] = .string(session.id.uuidString)
            row[SyncSettingsColumn.currency.rawValue] = .string(settings.currency)
            return row
        }
        let handRows = try hands.sorted { $0.id.uuidString < $1.id.uuidString }.map { hand in
            guard let fields = SyncHandFields(creating: hand) else {
                throw Failure.handWithoutSession(hand.id)
            }
            var row = try object(fields)
            row[SyncHandColumn.id.rawValue] = .string(hand.id.uuidString)
            return row
        }
        let document = SyncJSON.object([
            "format_version": .number(1),
            "sessions": .array(sessionRows.map { .object($0) }),
            "hands": .array(handRows.map { .object($0) }),
        ])
        var json = try encode(document)
        json.append(0x0A)
        return try ExportFiles(
            sessionsCSV: csv(columns: sessionColumns, rows: sessionRows),
            handsCSV: csv(columns: handColumns, rows: handRows),
            json: json
        )
    }

    /// The sync model mapping and encoder own column names, date strings, nulls,
    /// and cents rounding. Both export formats consume the same encoded rows.
    private static func object(_ fields: some Encodable) throws -> [String: SyncJSON] {
        try JSONDecoder().decode([String: SyncJSON].self, from: SyncCoding.encoder.encode(fields))
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func csv(columns: [String], rows: [[String: SyncJSON]]) throws -> Data {
        var lines = [columns.joined(separator: ",")]
        for row in rows {
            let cells = try columns.map { column in
                quote(try cell(row[column] ?? .null))
            }
            lines.append(cells.joined(separator: ","))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func cell(_ value: SyncJSON) throws -> String {
        switch value {
        case .null: return ""
        case .string(let text):
            // Only text cells can be formulas; preserve numeric and nested JSON cells.
            if let first = text.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) {
                return "'" + text
            }
            return text
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let number):
            // Plain decimal, not printf/NumberFormatter or scientific notation.
            return NSDecimalNumber(string: String(number), locale: Locale(identifier: "en_US_POSIX")).stringValue
        case .object, .array:
            return String(decoding: try encode(value), as: UTF8.self)
        }
    }

    /// RFC 4180 field escaping, with LF record separators for portable fixtures.
    private static func quote(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
