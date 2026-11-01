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
        let upperBound: Double
        let count: Int

        /// VoiceOver text for the bar, for example "+$1,000 to under +$1,100, 3 sessions".
        var accessibilityLabel: String {
            let upper = CurrencyFormatter.formatSigned(upperBound)
            let sessions = count == 1 ? "1 session" : "\(count) sessions"
            return "\(rangeLabel) to under \(upper), \(sessions)"
        }
    }

    struct MentalCorrelationPoint: Identifiable {
        let id = UUID()
        let metricType: MentalMetricType
        let level: Int
        let averageHourlyRate: Double
        let sessionCount: Int
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

    /// Most bars the P&L histogram shows. A wider P/L range widens the buckets instead.
    static let maxPLBuckets = 20

    /// Returns buckets of session P&L values for histogram display.
    /// Buckets start at `bucketWidth` and widen through 1, 2, 5, 10, 20, 50... times it
    /// until the range fits in `maxBuckets` bars.
    static func sessionPLDistribution(
        sessions: [Session],
        bucketWidth: Double = 100,
        maxBuckets: Int = maxPLBuckets
    ) -> [PLBucket] {
        let completed = sessions.filter { $0.status == .completed }
        guard !completed.isEmpty else { return [] }

        // A non-finite profit (corrupt data) can't go in a bucket.
        let profits = completed.map(\.netProfit).filter(\.isFinite)
        guard !profits.isEmpty else { return [] }
        let minProfit = (profits.min() ?? 0)
        let maxProfit = (profits.max() ?? 0)
        let width = plBucketWidth(min: minProfit, max: maxProfit, baseWidth: bucketWidth, maxBuckets: maxBuckets)

        guard width > 0, width.isFinite else { return [] }

        // Buckets are [lower, lower + width). The last one starts at
        // floor(max / width) * width, so the maximum always lands in a bucket
        // and a single value or narrow range still gets its real bucket.
        // Each profit goes to bucket floor(profit / width) - first, found by
        // division rather than by stepping lower += width: at huge magnitudes
        // width can be below the Double spacing, where stepping drops sessions
        // or never ends. plBucketWidth keeps bucketCount at most maxBuckets.
        let first = floor(minProfit / width)
        let bucketCount = Int(floor(maxProfit / width) - first) + 1
        var counts = Array(repeating: 0, count: bucketCount)
        for profit in profits {
            let index = Swift.min(Swift.max(floor(profit / width) - first, 0), Double(bucketCount - 1))
            counts[Int(index)] += 1
        }

        return counts.indices.map { i in
            let lower = (first + Double(i)) * width
            return PLBucket(rangeLabel: signedDollarLabel(lower), lowerBound: lower, upperBound: lower + width, count: counts[i])
        }
    }

    /// Smallest of baseWidth times 1, 2, 5, 10, 20, 50... that covers min...max in at most maxBuckets buckets.
    static func plBucketWidth(min: Double, max: Double, baseWidth: Double = 100, maxBuckets: Int = maxPLBuckets) -> Double {
        guard baseWidth > 0, min.isFinite, max.isFinite else { return baseWidth }
        let multipliers: [Double] = [1, 2, 5]
        var scale: Double = 1
        while true {
            for m in multipliers {
                let width = baseWidth * m * scale
                let count = floor(max / width) - floor(min / width) + 1
                if count <= Double(Swift.max(maxBuckets, 1)) { return width }
            }
            scale *= 10
        }
    }

    /// Signed whole-dollar bar label: "+$100", "+$0" for zero, "-$2,000" below zero.
    /// Uses CurrencyFormatter rather than Int(value), which traps on a non-finite
    /// or out-of-range Double. Zero keeps its "+" because the +$0 bar starts a
    /// range that runs up into profit.
    /// A non-finite value (never a bucket bound) reads "+$∞", "-$∞", or "$0" for NaN.
    static func signedDollarLabel(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "$0" : (value < 0 ? "-$∞" : "+$∞") }
        return (value < 0 ? "-" : "+") + CurrencyFormatter.format(abs(value))
    }

    /// Chart subtitle naming the bucket width, for example "Sessions per $2,000 range, labeled by the low end".
    static func plDistributionSubtitle(_ buckets: [PLBucket]) -> String? {
        guard let first = buckets.first else { return nil }
        return "Sessions per \(CurrencyFormatter.format(first.upperBound - first.lowerBound)) range, labeled by the low end"
    }

    // MARK: - Mental Correlation

    /// Returns average hourly rate grouped by mental metric type and level.
    /// Only includes completed sessions with non-nil mental data and valid hourly rates.
    static func mentalCorrelation(sessions: [Session]) -> [MentalCorrelationPoint] {
        let completed = sessions.filter { $0.status == .completed }
        var points: [MentalCorrelationPoint] = []

        for metricType in MentalMetricType.allCases {
            var ratesByLevel: [Int: [Double]] = [:]

            for session in completed {
                let level: Int?
                switch metricType {
                case .tilt: level = session.tiltLevel
                case .energy: level = session.energyLevel
                case .focus: level = session.focusLevel
                }

                guard let lvl = level, let hourly = session.hourlyRate else { continue }
                ratesByLevel[lvl, default: []].append(hourly)
            }

            for (level, rates) in ratesByLevel {
                let avg = rates.reduce(0, +) / Double(rates.count)
                points.append(MentalCorrelationPoint(
                    metricType: metricType,
                    level: level,
                    averageHourlyRate: avg,
                    sessionCount: rates.count
                ))
            }
        }

        return points.sorted { ($0.metricType.rawValue, $0.level) < ($1.metricType.rawValue, $1.level) }
    }

    /// Calm (tilt level 1) and tilted (tilt levels 4 and 5 pooled) hourly rates.
    /// The tilted rate averages every session at level 4 or 5, so each level is
    /// weighted by its session count. Each group needs at least 2 sessions.
    static func mentalInsight(points: [MentalCorrelationPoint]) -> (calmRate: Double, tiltedRate: Double)? {
        let tiltPoints = points.filter { $0.metricType == .tilt }
        let tilted = tiltPoints.filter { $0.level >= 4 }
        let tiltedCount = tilted.reduce(0) { $0 + $1.sessionCount }
        guard let calm = tiltPoints.first(where: { $0.level == 1 }),
              calm.sessionCount >= 2, tiltedCount >= 2 else { return nil }
        let tiltedTotal = tilted.reduce(0.0) { $0 + $1.averageHourlyRate * Double($1.sessionCount) }
        return (calmRate: calm.averageHourlyRate, tiltedRate: tiltedTotal / Double(tiltedCount))
    }
}
