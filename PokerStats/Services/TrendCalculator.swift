import Foundation

/// Pure static functions for computing trend chart data.
enum TrendCalculator {

    // MARK: - Data Types

    struct BankrollDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let cumulativeProfit: Double
        let sessionIndex: Int
    }

    struct RollingStatPoint: Identifiable {
        let id = UUID()
        let handIndex: Int
        let vpip: Double
        let pfr: Double
    }

    struct DayOfWeekProfit: Identifiable {
        let id = UUID()
        let dayName: String
        let dayNumber: Int // 1=Sun...7=Sat
        let totalProfit: Double
        let sessionCount: Int
    }

    struct PLBucket: Identifiable {
        let id = UUID()
        let rangeLabel: String
        let lowerBound: Double
        let count: Int
    }

    // MARK: - Cumulative Bankroll

    /// Returns cumulative profit over completed sessions, sorted by start time.
    static func cumulativeBankroll(sessions: [Session]) -> [BankrollDataPoint] {
        let completed = sessions
            .filter { $0.status == .completed }
            .sorted { $0.startTime < $1.startTime }

        guard !completed.isEmpty else { return [] }

        var cumulative = 0.0
        var points: [BankrollDataPoint] = []

        // Starting point at zero
        if let first = completed.first {
            points.append(BankrollDataPoint(date: first.startTime, cumulativeProfit: 0, sessionIndex: 0))
        }

        for (i, session) in completed.enumerated() {
            cumulative += session.netProfit
            let date = session.endTime ?? session.startTime
            points.append(BankrollDataPoint(date: date, cumulativeProfit: cumulative, sessionIndex: i + 1))
        }

        return points
    }

    // MARK: - Rolling VPIP/PFR

    /// Returns rolling VPIP and PFR averages over a sliding window of hands.
    static func rollingVPIPPFR(hands: [Hand], windowSize: Int = 20) -> [RollingStatPoint] {
        let sorted = hands.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= windowSize else { return [] }

        var points: [RollingStatPoint] = []

        for i in (windowSize - 1)..<sorted.count {
            let window = Array(sorted[(i - windowSize + 1)...i])
            let vpip = Double(window.filter(\.voluntarilyPutMoneyIn).count) / Double(windowSize)
            let pfr = Double(window.filter(\.raisedPreflop).count) / Double(windowSize)
            points.append(RollingStatPoint(handIndex: i + 1, vpip: vpip, pfr: pfr))
        }

        return points
    }

    // MARK: - Profit by Day of Week

    /// Returns total profit grouped by day of week. Always returns 7 entries.
    static func profitByDayOfWeek(sessions: [Session]) -> [DayOfWeekProfit] {
        let completed = sessions.filter { $0.status == .completed }

        let calendar = Calendar.current
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        var profitByDay: [Int: Double] = [:]
        var countByDay: [Int: Int] = [:]

        for session in completed {
            let weekday = calendar.component(.weekday, from: session.startTime) // 1=Sun...7=Sat
            profitByDay[weekday, default: 0] += session.netProfit
            countByDay[weekday, default: 0] += 1
        }

        return (1...7).map { day in
            DayOfWeekProfit(
                dayName: dayNames[day - 1],
                dayNumber: day,
                totalProfit: profitByDay[day] ?? 0,
                sessionCount: countByDay[day] ?? 0
            )
        }
    }

    // MARK: - P&L Distribution Histogram

    /// Returns buckets of session P&L values for histogram display.
    static func sessionPLDistribution(sessions: [Session], bucketWidth: Double = 100) -> [PLBucket] {
        let completed = sessions.filter { $0.status == .completed }
        guard !completed.isEmpty else { return [] }

        let profits = completed.map(\.netProfit)
        let minProfit = (profits.min() ?? 0)
        let maxProfit = (profits.max() ?? 0)

        // Determine bucket boundaries
        let lowerBound = floor(minProfit / bucketWidth) * bucketWidth
        let upperBound = ceil(maxProfit / bucketWidth) * bucketWidth

        guard upperBound > lowerBound else {
            return [PLBucket(rangeLabel: "$0", lowerBound: 0, count: completed.count)]
        }

        var buckets: [PLBucket] = []
        var current = lowerBound

        while current < upperBound {
            let next = current + bucketWidth
            let count = profits.filter { $0 >= current && $0 < next }.count
            let label: String
            if current >= 0 {
                label = "+$\(Int(current))"
            } else {
                label = "-$\(Int(abs(current)))"
            }
            buckets.append(PLBucket(rangeLabel: label, lowerBound: current, count: count))
            current = next
        }

        return buckets
    }
}
