import Foundation

/// Value type holding all computed poker statistics.
/// Percentages are stored as 0.0–1.0 (multiply by 100 for display).
struct ComputedStats {
    let totalHands: Int
    let handsFolded: Int

    // Preflop stats (0.0-1.0)
    let vpip: Double?
    let pfr: Double?
    let foldTo3BetPercent: Double?

    // Postflop stats (0.0-1.0)
    let cBetPercent: Double?
    let wtsdPercent: Double?
    let wsdPercent: Double?

    // Money stats
    let totalProfit: Double
    let sessionsPlayed: Int
    let averageProfitPerSession: Double?
    let hourlyRate: Double?
    let totalHoursPlayed: Double

    static let empty = ComputedStats(
        totalHands: 0,
        handsFolded: 0,
        vpip: nil,
        pfr: nil,
        foldTo3BetPercent: nil,
        cBetPercent: nil,
        wtsdPercent: nil,
        wsdPercent: nil,
        totalProfit: 0,
        sessionsPlayed: 0,
        averageProfitPerSession: nil,
        hourlyRate: nil,
        totalHoursPlayed: 0
    )
}

// MARK: - Position Stats

struct PositionStats: Identifiable {
    let position: SeatPosition
    let handCount: Int
    let vpip: Double?
    let pfr: Double?

    var id: String { position.rawValue }
}

// MARK: - Formatting Helpers

extension ComputedStats {
    /// Format a percentage (0.0-1.0) as "25.0%". Returns "--" if nil.
    static func formatPercent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value * 100)
    }

    /// Format a currency amount as "$1,234" or "-$567".
    static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    /// Format hourly rate as "$34.50/hr". Returns "--" if nil.
    static func formatHourlyRate(_ value: Double?) -> String {
        guard let value else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
        return "\(formatted)/hr"
    }
}
