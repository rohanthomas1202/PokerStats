import Testing
@testable import PokerStats

@Suite("LeakFinder Tests")
struct LeakFinderTests {

    // MARK: - Tight Player (All Healthy for Full Ring)

    @Test("Tight-aggressive player shows all healthy for full ring")
    func tightAggressiveFullRing() {
        let stats = ComputedStats(
            totalHands: 100,
            handsFolded: 78,
            vpip: 0.20,
            pfr: 0.16,
            foldTo3BetPercent: 0.50,
            cBetPercent: 0.65,
            wtsdPercent: 0.28,
            wsdPercent: 0.55,
            totalProfit: 200,
            sessionsPlayed: 5,
            averageProfitPerSession: 40,
            hourlyRate: 20,
            totalHoursPlayed: 10
        )

        let insights = LeakFinder.analyze(stats: stats, profile: .fullRingCash)

        // All stats should be healthy
        for insight in insights {
            #expect(insight.rating == .healthy, "Expected \(insight.statKey.displayName) to be healthy, got \(insight.rating)")
        }

        #expect(LeakFinder.overallRating(from: insights) == .solid)
    }

    // MARK: - Loose Player (VPIP + PFR Leaks)

    @Test("Loose player has VPIP and PFR leaks")
    func loosePlayerLeaks() {
        let stats = ComputedStats(
            totalHands: 100,
            handsFolded: 50,
            vpip: 0.45,   // Way too high
            pfr: 0.35,    // Way too high
            foldTo3BetPercent: 0.50,
            cBetPercent: 0.65,
            wtsdPercent: 0.30,
            wsdPercent: 0.55,
            totalProfit: -500,
            sessionsPlayed: 5,
            averageProfitPerSession: -100,
            hourlyRate: -50,
            totalHoursPlayed: 10
        )

        let insights = LeakFinder.analyze(stats: stats, profile: .sixMaxCash)

        let vpipInsight = insights.first { $0.statKey == .vpip }
        #expect(vpipInsight?.rating == .leak)

        let pfrInsight = insights.first { $0.statKey == .pfr }
        #expect(pfrInsight?.rating == .leak)

        #expect(LeakFinder.overallRating(from: insights) == .leaking)
    }

    // MARK: - Nil Stats Are Skipped

    @Test("Nil stat values are skipped in analysis")
    func nilStatsSkipped() {
        let stats = ComputedStats(
            totalHands: 30,
            handsFolded: 25,
            vpip: 0.20,
            pfr: 0.15,
            foldTo3BetPercent: nil,  // Never faced 3-bet
            cBetPercent: nil,        // No c-bet opportunities
            wtsdPercent: nil,        // Never saw flop
            wsdPercent: nil,         // Never went to showdown
            totalProfit: 50,
            sessionsPlayed: 2,
            averageProfitPerSession: 25,
            hourlyRate: 12.5,
            totalHoursPlayed: 4
        )

        let insights = LeakFinder.analyze(stats: stats, profile: .fullRingCash)

        // Should only have insights for VPIP and PFR (the non-nil stats)
        #expect(insights.count == 2)
        #expect(insights.allSatisfy { $0.statKey == .vpip || $0.statKey == .pfr })
    }

    // MARK: - Boundary Values

    @Test("Stats at exact boundary of ideal range are healthy")
    func boundaryValuesHealthy() {
        let stats = ComputedStats(
            totalHands: 100,
            handsFolded: 78,
            vpip: 0.22,  // Exactly at upper end of 6-max ideal (0.22–0.30)
            pfr: 0.18,   // Exactly at lower end of 6-max ideal (0.18–0.25)
            foldTo3BetPercent: 0.40,
            cBetPercent: 0.55,
            wtsdPercent: 0.26,
            wsdPercent: 0.50,
            totalProfit: 100,
            sessionsPlayed: 5,
            averageProfitPerSession: 20,
            hourlyRate: 10,
            totalHoursPlayed: 10
        )

        let insights = LeakFinder.analyze(stats: stats, profile: .sixMaxCash)

        for insight in insights {
            #expect(insight.rating == .healthy, "\(insight.statKey.displayName) at boundary should be healthy")
        }
    }

    // MARK: - Borderline Detection

    @Test("Stats in acceptable but outside ideal range are borderline")
    func borderlineDetection() {
        let stats = ComputedStats(
            totalHands: 100,
            handsFolded: 70,
            vpip: 0.32,   // Above ideal (0.22–0.30) but within acceptable (0.18–0.35)
            pfr: 0.15,    // Below ideal (0.18–0.25) but within acceptable (0.14–0.28)
            foldTo3BetPercent: 0.50,
            cBetPercent: 0.65,
            wtsdPercent: 0.30,
            wsdPercent: 0.55,
            totalProfit: 0,
            sessionsPlayed: 5,
            averageProfitPerSession: 0,
            hourlyRate: 0,
            totalHoursPlayed: 10
        )

        let insights = LeakFinder.analyze(stats: stats, profile: .sixMaxCash)

        let vpipInsight = insights.first { $0.statKey == .vpip }
        #expect(vpipInsight?.rating == .borderline)

        let pfrInsight = insights.first { $0.statKey == .pfr }
        #expect(pfrInsight?.rating == .borderline)
    }

    // MARK: - Overall Rating Logic

    @Test("Overall rating with 1 leak and 1 borderline is needsWork")
    func overallRatingNeedsWork() {
        let insights = [
            LeakInsight(statKey: .vpip, value: 0.45, rating: .leak, message: "", suggestion: ""),
            LeakInsight(statKey: .pfr, value: 0.20, rating: .healthy, message: "", suggestion: ""),
            LeakInsight(statKey: .cBet, value: 0.50, rating: .borderline, message: "", suggestion: ""),
        ]
        #expect(LeakFinder.overallRating(from: insights) == .needsWork)
    }

    @Test("Overall rating with 2+ leaks is leaking")
    func overallRatingLeaking() {
        let insights = [
            LeakInsight(statKey: .vpip, value: 0.50, rating: .leak, message: "", suggestion: ""),
            LeakInsight(statKey: .pfr, value: 0.40, rating: .leak, message: "", suggestion: ""),
            LeakInsight(statKey: .cBet, value: 0.65, rating: .healthy, message: "", suggestion: ""),
        ]
        #expect(LeakFinder.overallRating(from: insights) == .leaking)
    }

    @Test("Overall rating with all healthy is solid")
    func overallRatingSolid() {
        let insights = [
            LeakInsight(statKey: .vpip, value: 0.25, rating: .healthy, message: "", suggestion: ""),
            LeakInsight(statKey: .pfr, value: 0.20, rating: .healthy, message: "", suggestion: ""),
        ]
        #expect(LeakFinder.overallRating(from: insights) == .solid)
    }

    // MARK: - Sorting

    @Test("Insights sorted by severity: leaks first, then borderline, then healthy")
    func insightsSortedBySeverity() {
        let stats = ComputedStats(
            totalHands: 100,
            handsFolded: 50,
            vpip: 0.50,   // Leak
            pfr: 0.20,    // Healthy for 6-max
            foldTo3BetPercent: 0.32,  // Borderline for 6-max
            cBetPercent: 0.65,
            wtsdPercent: 0.30,
            wsdPercent: 0.55,
            totalProfit: 0,
            sessionsPlayed: 5,
            averageProfitPerSession: 0,
            hourlyRate: 0,
            totalHoursPlayed: 10
        )

        let insights = LeakFinder.analyze(stats: stats, profile: .sixMaxCash)

        // Verify leaks come before borderline, borderline before healthy
        var lastRating: LeakRating? = nil
        for insight in insights {
            if let last = lastRating {
                #expect(insight.rating >= last, "Insights should be sorted: leaks first")
            }
            lastRating = insight.rating
        }
    }

    // MARK: - Profile Comparison

    @Test("Same stats can have different ratings in different profiles")
    func profileComparison() {
        // VPIP 0.14 is acceptable for full ring but borderline/leak for 6-max
        let stats = ComputedStats(
            totalHands: 100,
            handsFolded: 86,
            vpip: 0.14,
            pfr: 0.12,
            foldTo3BetPercent: 0.50,
            cBetPercent: 0.65,
            wtsdPercent: 0.28,
            wsdPercent: 0.55,
            totalProfit: 100,
            sessionsPlayed: 5,
            averageProfitPerSession: 20,
            hourlyRate: 10,
            totalHoursPlayed: 10
        )

        let fullRingInsights = LeakFinder.analyze(stats: stats, profile: .fullRingCash)
        let sixMaxInsights = LeakFinder.analyze(stats: stats, profile: .sixMaxCash)

        let frVpip = fullRingInsights.first { $0.statKey == .vpip }
        let smVpip = sixMaxInsights.first { $0.statKey == .vpip }

        // Full ring: 0.14 is within acceptable (0.12–0.28)
        #expect(frVpip?.rating == .borderline)
        // 6-max: 0.14 is outside acceptable (0.18–0.35)
        #expect(smVpip?.rating == .leak)
    }
}
