import Foundation

/// Encoding and decoding rules for the sync wire types (design section 9.4).
///
/// Dates are ISO 8601 in UTC with fractional seconds (`2026-10-18T02:11:09.250Z`).
/// Decoding accepts any explicit offset (PostgREST returns `+00:00`) with or
/// without fractions, and rejects a timestamp with no offset. The supabase-swift
/// PostgREST strategies are not used here: their encoder writes no offset,
/// which the contract rejects, and their decoder ignores the offset.
enum SyncCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SyncCoding.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = SyncCoding.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 timestamp with an offset: \(text)")
            }
            return date
        }
        return decoder
    }()

    private static let withFractions = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractions = Date.ISO8601FormatStyle()

    static func string(from date: Date) -> String {
        withFractions.format(date)
    }

    static func date(from text: String) -> Date? {
        (try? withFractions.parse(text)) ?? (try? withoutFractions.parse(text))
    }

    // MARK: - Money

    /// The `numeric(14,2)` range: 12 integer digits and 2 decimals.
    static let maxMoney = 999_999_999_999.99

    /// Clamps to the `numeric(14,2)` range, then rounds half away from zero to
    /// cents. Rounds the value's shortest decimal form, so 1.005 becomes 1.01
    /// as written, not 1.00 as its binary value would. NaN becomes 0.
    static func cents(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        let clamped = min(max(value, -maxMoney), maxMoney)
        guard var exact = Decimal(string: String(clamped)) else { return clamped }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 2, .plain)
        // Through the decimal string, so 0.07 stays 0.07 rather than the
        // 0.06999999999999999 that Decimal's doubleValue gives.
        return Double(rounded.description) ?? clamped
    }
}

/// Any JSON value. `table_config` travels as a JSON object (design 9.4), and
/// the server keeps whatever object the client sent, so it is not tied to the
/// current `TableConfig` shape.
enum SyncJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SyncJSON])
    case object([String: SyncJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SyncJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SyncJSON].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers as integers, so `TableConfig`'s Int fields decode.
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Patch keys

extension KeyedDecodingContainer {
    /// A nullable column in a patch: `nil` if the key is absent, `.some(nil)`
    /// if it is sent as null.
    func decodePatch<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T?? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return .some(nil) }
        return .some(try decode(T.self, forKey: key))
    }
}
