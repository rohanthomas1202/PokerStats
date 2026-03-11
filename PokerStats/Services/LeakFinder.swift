import Foundation

/// Optimal range for a poker stat, with acceptable and ideal boundaries.
struct StatRange {
    let ideal: ClosedRange<Double>
    let acceptable: ClosedRange<Double>
}

/// Reference profile for a specific game format with optimal stat ranges.
enum ReferenceProfile: String, CaseIterable, Identifiable {
    case fullRingCash = "Full Ring (9-max)"
    case sixMaxCash = "6-Max"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var ranges: [StatKey: StatRange] {
        switch self {
        case .fullRingCash:
            return [
                .vpip: StatRange(ideal: 0.15...0.22, acceptable: 0.12...0.28),
                .pfr: StatRange(ideal: 0.12...0.18, acceptable: 0.10...0.22),
                .cBet: StatRange(ideal: 0.60...0.75, acceptable: 0.50...0.80),
                .foldTo3Bet: StatRange(ideal: 0.45...0.55, acceptable: 0.35...0.65),
                .wtsd: StatRange(ideal: 0.25...0.32, acceptable: 0.20...0.38),
                .wsd: StatRange(ideal: 0.50...0.58, acceptable: 0.45...0.62),
            ]
        case .sixMaxCash:
            return [
                .vpip: StatRange(ideal: 0.22...0.30, acceptable: 0.18...0.35),
                .pfr: StatRange(ideal: 0.18...0.25, acceptable: 0.14...0.28),
                .cBet: StatRange(ideal: 0.55...0.70, acceptable: 0.45...0.78),
                .foldTo3Bet: StatRange(ideal: 0.40...0.55, acceptable: 0.30...0.65),
                .wtsd: StatRange(ideal: 0.26...0.34, acceptable: 0.22...0.40),
                .wsd: StatRange(ideal: 0.50...0.60, acceptable: 0.45...0.65),
            ]
        }
    }
}

/// Keys for the stats we analyze.
enum StatKey: String, CaseIterable, Identifiable {
    case vpip
    case pfr
    case cBet
    case foldTo3Bet
    case wtsd
    case wsd

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vpip: "VPIP"
        case .pfr: "PFR"
        case .cBet: "C-Bet %"
        case .foldTo3Bet: "Fold to 3-Bet %"
        case .wtsd: "WTSD %"
        case .wsd: "W$SD %"
        }
    }

    var icon: String {
        switch self {
        case .vpip: "hand.raised"
        case .pfr: "arrow.up.circle"
        case .cBet: "arrow.right.circle"
        case .foldTo3Bet: "shield.slash"
        case .wtsd: "eye"
        case .wsd: "trophy"
        }
    }
}

/// Health rating for a single stat.
enum LeakRating: String, Comparable {
    case healthy
    case borderline
    case leak

    var sortOrder: Int {
        switch self {
        case .leak: 0
        case .borderline: 1
        case .healthy: 2
        }
    }

    static func < (lhs: LeakRating, rhs: LeakRating) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// A single insight about a stat — its value, rating, and actionable advice.
struct LeakInsight: Identifiable {
    let id = UUID()
    let statKey: StatKey
    let value: Double
    let rating: LeakRating
    let message: String
    let suggestion: String
}

/// Overall health summary.
enum OverallRating: String {
    case solid = "Solid"
    case needsWork = "Needs Work"
    case leaking = "Leaking"
}

/// Pure-function leak analysis. No side effects, no persistence.
enum LeakFinder {

    static let minimumHands = 20

    /// Analyze stats against a reference profile. Returns insights sorted by severity (leaks first).
    static func analyze(stats: ComputedStats, profile: ReferenceProfile) -> [LeakInsight] {
        var insights: [LeakInsight] = []

        for statKey in StatKey.allCases {
            guard let range = profile.ranges[statKey],
                  let value = statValue(for: statKey, from: stats) else { continue }

            let rating = rate(value: value, range: range)
            let message = describeIssue(statKey: statKey, value: value, range: range, rating: rating)
            let suggestion = suggestFix(statKey: statKey, value: value, range: range, rating: rating)

            insights.append(LeakInsight(
                statKey: statKey,
                value: value,
                rating: rating,
                message: message,
                suggestion: suggestion
            ))
        }

        return insights.sorted { $0.rating < $1.rating }
    }

    /// Compute overall rating from insights.
    static func overallRating(from insights: [LeakInsight]) -> OverallRating {
        let leakCount = insights.filter { $0.rating == .leak }.count
        let borderlineCount = insights.filter { $0.rating == .borderline }.count

        if leakCount >= 2 { return .leaking }
        if leakCount >= 1 || borderlineCount >= 2 { return .needsWork }
        return .solid
    }

    // MARK: - Private Helpers

    private static func statValue(for key: StatKey, from stats: ComputedStats) -> Double? {
        switch key {
        case .vpip: stats.vpip
        case .pfr: stats.pfr
        case .cBet: stats.cBetPercent
        case .foldTo3Bet: stats.foldTo3BetPercent
        case .wtsd: stats.wtsdPercent
        case .wsd: stats.wsdPercent
        }
    }

    private static func rate(value: Double, range: StatRange) -> LeakRating {
        if range.ideal.contains(value) { return .healthy }
        if range.acceptable.contains(value) { return .borderline }
        return .leak
    }

    private static func describeIssue(statKey: StatKey, value: Double, range: StatRange, rating: LeakRating) -> String {
        let pct = String(format: "%.0f%%", value * 100)
        let idealLow = String(format: "%.0f%%", range.ideal.lowerBound * 100)
        let idealHigh = String(format: "%.0f%%", range.ideal.upperBound * 100)

        switch rating {
        case .healthy:
            return "\(statKey.displayName) at \(pct) is right in the sweet spot (\(idealLow)–\(idealHigh))."
        case .borderline:
            let direction = value < range.ideal.lowerBound ? "slightly low" : "slightly high"
            return "\(statKey.displayName) at \(pct) is \(direction). Ideal is \(idealLow)–\(idealHigh)."
        case .leak:
            let direction = value < range.acceptable.lowerBound ? "too low" : "too high"
            return "\(statKey.displayName) at \(pct) is \(direction). Ideal is \(idealLow)–\(idealHigh)."
        }
    }

    private static func suggestFix(statKey: StatKey, value: Double, range: StatRange, rating: LeakRating) -> String {
        guard rating != .healthy else { return "Keep it up! Your \(statKey.displayName) is well-calibrated." }

        let tooLow = value < range.ideal.lowerBound

        switch statKey {
        case .vpip:
            return tooLow
                ? "You're playing too tight. Open up with suited connectors and broadways from late position."
                : "You're entering too many pots. Tighten up from early and middle position — fold marginal hands."
        case .pfr:
            return tooLow
                ? "You're limping or calling too much preflop. Raise more with your strong hands to build pots and gain initiative."
                : "You're raising too aggressively preflop. Be more selective with your opening range, especially from early position."
        case .cBet:
            return tooLow
                ? "You're missing value by not following through on the flop. C-bet more on dry boards where your range has an advantage."
                : "You're c-betting too often. Check back on wet boards or when you completely miss — your opponents will start exploiting you."
        case .foldTo3Bet:
            return tooLow
                ? "You're calling 3-bets too wide. Tighten your continuing range and fold weaker suited hands facing aggression."
                : "You're folding to 3-bets too often. Defend more by 4-betting bluffs or flatting with suited hands in position."
        case .wtsd:
            return tooLow
                ? "You're giving up too often postflop. Call down lighter when you have decent showdown value."
                : "You're going to showdown too often — you may be calling too loosely. Fold more on the river when facing big bets."
        case .wsd:
            return tooLow
                ? "You're losing too often at showdown. This may mean you're calling too light on the river — tighten your calling range."
                : "Great showdown win rate. Make sure you're not folding too many marginal winners before showdown."
        }
    }
}
