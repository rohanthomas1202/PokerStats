import Foundation
import Testing
@testable import PokerStats

@Suite("TrendCalculator Tests")
struct TrendCalculatorTests {

    // MARK: - Cumulative Bankroll

    @Test func cumulativeBankroll_noSessions_returnsEmpty() {
        let result = TrendCalculator.cumulativeBankroll(sessions: [])
        #expect(result.isEmpty)
    }

    @Test func cumulativeBankroll_threeSessions_correctTotals() {
        let s1 = TestHelpers.completedSession(buyIn: 200, cashOut: 350) // +150
        let s2 = TestHelpers.completedSession(buyIn: 200, cashOut: 100) // -100
        let s3 = TestHelpers.completedSession(buyIn: 200, cashOut: 400) // +200

        // Ensure ordering by adjusting start times
        s1.startTime = Date(timeIntervalSince1970: 1000)
        s1.endTime = Date(timeIntervalSince1970: 2000)
        s2.startTime = Date(timeIntervalSince1970: 3000)
        s2.endTime = Date(timeIntervalSince1970: 4000)
        s3.startTime = Date(timeIntervalSince1970: 5000)
        s3.endTime = Date(timeIntervalSince1970: 6000)

        let result = TrendCalculator.cumulativeBankroll(sessions: [s3, s1, s2]) // unsorted input
        // Should have 4 points: start(0), after s1(+150), after s2(+50), after s3(+250)
        #expect(result.count == 4)
        #expect(result[0].cumulativeProfit == 0)
        #expect(abs(result[1].cumulativeProfit - 150) < 0.01)
        #expect(abs(result[2].cumulativeProfit - 50) < 0.01)
        #expect(abs(result[3].cumulativeProfit - 250) < 0.01)
    }

    @Test func cumulativeBankroll_excludesActiveSessions() {
        let active = Session(status: .active, buyIn: 200)
        let completed = TestHelpers.completedSession(buyIn: 200, cashOut: 300)

        let result = TrendCalculator.cumulativeBankroll(sessions: [active, completed])
        // Only completed sessions should be included
        #expect(result.count == 2) // start point + 1 completed
    }

    // MARK: - Rolling VPIP/PFR

    @Test func rollingVPIPPFR_fewerThanWindow_returnsEmpty() {
        let hands = [TestHelpers.foldHand()]
        let result = TrendCalculator.rollingVPIPPFR(hands: hands, windowSize: 20)
        #expect(result.isEmpty)
    }

    @Test func rollingVPIPPFR_exactWindow_returnsOnePoint() {
        var hands: [Hand] = []
        for i in 1...20 {
            let hand = i <= 5
                ? Hand(handNumber: i, timestamp: Date(timeIntervalSince1970: Double(i) * 100), preflopAction: .raise, postflopResult: .wonPreflop)
                : TestHelpers.foldHand(number: i)
            hand.timestamp = Date(timeIntervalSince1970: Double(i) * 100)
            hands.append(hand)
        }
        let result = TrendCalculator.rollingVPIPPFR(hands: hands, windowSize: 20)
        #expect(result.count == 1)
        #expect(abs(result[0].vpip - 0.25) < 0.01) // 5 out of 20
        #expect(abs(result[0].pfr - 0.25) < 0.01)  // 5 out of 20
    }

    // MARK: - Profit by Day of Week

    @Test func profitByDayOfWeek_returnsSevenEntries() {
        let result = TrendCalculator.profitByDayOfWeek(sessions: [])
        #expect(result.count == 7)
    }

    @Test func profitByDayOfWeek_withSessions_correctProfits() {
        let session = TestHelpers.completedSession(buyIn: 200, cashOut: 500) // +300
        let result = TrendCalculator.profitByDayOfWeek(sessions: [session])
        // One day should have profit, rest should be 0
        let nonZero = result.filter { $0.totalProfit != 0 }
        #expect(nonZero.count == 1)
        #expect(abs(nonZero[0].totalProfit - 300) < 0.01)
    }

    // MARK: - P&L Distribution

    @Test func plDistribution_noSessions_returnsEmpty() {
        let result = TrendCalculator.sessionPLDistribution(sessions: [])
        #expect(result.isEmpty)
    }

    @Test func plDistribution_withSessions_createsBuckets() {
        let s1 = TestHelpers.completedSession(buyIn: 200, cashOut: 350) // +150
        let s2 = TestHelpers.completedSession(buyIn: 200, cashOut: 100) // -100
        let s3 = TestHelpers.completedSession(buyIn: 200, cashOut: 250) // +50

        let result = TrendCalculator.sessionPLDistribution(sessions: [s1, s2, s3], bucketWidth: 100)
        // Should cover -100 to +200 range
        #expect(!result.isEmpty)
        let totalCount = result.reduce(0) { $0 + $1.count }
        #expect(totalCount == 3) // all 3 sessions accounted for
    }

    private func buckets(_ result: [TrendCalculator.PLBucket]) -> [(String, Double, Int)] {
        result.map { ($0.rangeLabel, $0.lowerBound, $0.count) }
    }

    @Test func plDistribution_maxOnTopEdge_isCounted() {
        // pl-distribution-boundary fixture: -50 and +100.
        let s1 = TestHelpers.completedSession(buyIn: 100, cashOut: 50)  // -50
        let s2 = TestHelpers.completedSession(buyIn: 100, cashOut: 200) // +100
        let result = buckets(TrendCalculator.sessionPLDistribution(sessions: [s1, s2]))
        #expect(result.map { $0.0 } == ["-$100", "+$0", "+$100"])
        #expect(result.map { $0.1 } == [-100, 0, 100])
        #expect(result.map { $0.2 } == [1, 0, 1])
    }

    @Test func plDistribution_narrowRange_usesRealBucket() {
        let s1 = TestHelpers.completedSession(buyIn: 100, cashOut: 330) // +230
        let s2 = TestHelpers.completedSession(buyIn: 100, cashOut: 370) // +270
        let result = buckets(TrendCalculator.sessionPLDistribution(sessions: [s1, s2]))
        #expect(result.map { $0.0 } == ["+$200"])
        #expect(result.map { $0.1 } == [200])
        #expect(result.map { $0.2 } == [2])
    }

    @Test func plDistribution_narrowNegativeRange_usesRealBucket() {
        let s1 = TestHelpers.completedSession(buyIn: 300, cashOut: 140) // -160
        let s2 = TestHelpers.completedSession(buyIn: 300, cashOut: 180) // -120
        let result = buckets(TrendCalculator.sessionPLDistribution(sessions: [s1, s2]))
        #expect(result.map { $0.0 } == ["-$200"])
        #expect(result.map { $0.1 } == [-200])
        #expect(result.map { $0.2 } == [2])
    }

    @Test func plDistribution_singlePlus100_isOwnBucket() {
        // single-session fixture: one +100 session.
        let s = TestHelpers.completedSession(buyIn: 100, cashOut: 200)
        let result = buckets(TrendCalculator.sessionPLDistribution(sessions: [s]))
        #expect(result.map { $0.0 } == ["+$100"])
        #expect(result.map { $0.1 } == [100])
        #expect(result.map { $0.2 } == [1])
    }

    @Test func plDistribution_singleZero_isZeroBucket() {
        let s = TestHelpers.completedSession(buyIn: 100, cashOut: 100)
        let result = buckets(TrendCalculator.sessionPLDistribution(sessions: [s]))
        #expect(result.map { $0.0 } == ["+$0"])
        #expect(result.map { $0.1 } == [0])
        #expect(result.map { $0.2 } == [1])
    }

    // MARK: - P&L Distribution labels (#288)

    @Test func plDistribution_bucketsCarryUpperBound() {
        let s1 = TestHelpers.completedSession(buyIn: 100, cashOut: 50)  // -50
        let s2 = TestHelpers.completedSession(buyIn: 100, cashOut: 200) // +100
        let result = TrendCalculator.sessionPLDistribution(sessions: [s1, s2])
        #expect(result.map(\.upperBound) == [0, 100, 200])
    }

    @Test func plDistribution_subtitle_namesBucketWidth() {
        let s = TestHelpers.completedSession(buyIn: 100, cashOut: 200)
        let result = TrendCalculator.sessionPLDistribution(sessions: [s])
        #expect(TrendCalculator.plDistributionSubtitle(result) == "Sessions per $100 range, labeled by the low end")
        #expect(TrendCalculator.plDistributionSubtitle([]) == nil)
    }

    @Test func plDistribution_accessibilityLabels_stateRangeAndCount() {
        let s1 = TestHelpers.completedSession(buyIn: 100, cashOut: 50)  // -50
        let s2 = TestHelpers.completedSession(buyIn: 100, cashOut: 200) // +100
        let result = TrendCalculator.sessionPLDistribution(sessions: [s1, s2])
        #expect(result.map(\.accessibilityLabel) == [
            "-$100 to under $0, 1 session",
            "+$0 to under +$100, 0 sessions",
            "+$100 to under +$200, 1 session",
        ])
    }

    @Test func plDistribution_accessibilityLabels_pluralAndNegative() {
        let gains = [
            TestHelpers.completedSession(buyIn: 100, cashOut: 330), // +230
            TestHelpers.completedSession(buyIn: 100, cashOut: 370), // +270
        ]
        #expect(TrendCalculator.sessionPLDistribution(sessions: gains).map(\.accessibilityLabel)
            == ["+$200 to under +$300, 2 sessions"])
        let losses = [
            TestHelpers.completedSession(buyIn: 300, cashOut: 140), // -160
            TestHelpers.completedSession(buyIn: 300, cashOut: 180), // -120
        ]
        #expect(TrendCalculator.sessionPLDistribution(sessions: losses).map(\.accessibilityLabel)
            == ["-$200 to under -$100, 2 sessions"])
    }

    @Test func plDistribution_wideRange_isCappedAt20Buckets() {
        let s1 = TestHelpers.completedSession(buyIn: 5000, cashOut: 0)   // -5000
        let s2 = TestHelpers.completedSession(buyIn: 100, cashOut: 20100) // +20000
        let result = TrendCalculator.sessionPLDistribution(sessions: [s1, s2])
        #expect(result.count == 14)
        #expect(result.count <= TrendCalculator.maxPLBuckets)
        #expect(result.first?.rangeLabel == "-$6,000")
        #expect(result.last?.rangeLabel == "+$20,000")
        #expect(result.map(\.count).reduce(0, +) == 2)
        #expect(result.allSatisfy { $0.upperBound - $0.lowerBound == 2000 })
        #expect(TrendCalculator.plDistributionSubtitle(result) == "Sessions per $2,000 range, labeled by the low end")
        #expect(result.last?.accessibilityLabel == "+$20,000 to under +$22,000, 1 session")
    }

    @Test func plDistribution_labels_doNotTrapOnNonFiniteOrHugeValues() {
        #expect(TrendCalculator.signedDollarLabel(1e300).hasPrefix("+$1,000,000"))
        #expect(TrendCalculator.signedDollarLabel(-1e300).hasPrefix("-$1,000,000"))
        #expect(TrendCalculator.signedDollarLabel(.infinity) == "+$∞")
        #expect(TrendCalculator.signedDollarLabel(-.infinity) == "-$∞")
        #expect(TrendCalculator.signedDollarLabel(.nan) == "$0")

        // +1e19 is past Int.max, where the old Int(value) labels trapped.
        let even = TestHelpers.completedSession(buyIn: 100, cashOut: 100)
        let huge = TestHelpers.completedSession(buyIn: 0, cashOut: 1e19)
        let result = TrendCalculator.sessionPLDistribution(sessions: [even, huge])
        #expect(result.map(\.count).reduce(0, +) == 2)
        #expect(result.last?.rangeLabel.hasPrefix("+$10,000,000,000") == true)
        #expect(TrendCalculator.plDistributionSubtitle(result)?.hasPrefix("Sessions per $1,000,000,000") == true)
        _ = result.map(\.accessibilityLabel)
    }

    @Test func plDistribution_loneHugeSession_getsOneBar() {
        // At 1e300 the $100 width is below the Double spacing, so lower + width == lower.
        let huge = TestHelpers.completedSession(buyIn: 0, cashOut: 1e300)
        let result = TrendCalculator.sessionPLDistribution(sessions: [huge])
        #expect(result.count == 1)
        #expect(result.map(\.count) == [1])
    }

    @Test func plDistribution_closeHugeSessions_finishAndCountBoth() {
        // A narrow range at a huge magnitude used to loop forever.
        let a = TestHelpers.completedSession(buyIn: 0, cashOut: 1e19)
        let b = TestHelpers.completedSession(buyIn: 0, cashOut: 1e19 + 4096)
        let result = TrendCalculator.sessionPLDistribution(sessions: [a, b])
        #expect(!result.isEmpty)
        #expect(result.count <= TrendCalculator.maxPLBuckets)
        #expect(result.map(\.count).reduce(0, +) == 2)
    }

    @Test func plDistribution_skipsNonFiniteProfits() {
        let ok = TestHelpers.completedSession(buyIn: 100, cashOut: 200) // +100
        let corrupt = TestHelpers.completedSession(buyIn: 100, cashOut: .infinity)
        let result = TrendCalculator.sessionPLDistribution(sessions: [ok, corrupt])
        #expect(result.map(\.rangeLabel) == ["+$100"])
        #expect(result.map(\.count) == [1])
        #expect(TrendCalculator.sessionPLDistribution(sessions: [corrupt]).isEmpty)
    }

    @Test func plBucketWidth_staysAt100UpTo20Buckets() {
        #expect(TrendCalculator.plBucketWidth(min: 0, max: 1999) == 100)   // 20 buckets
        #expect(TrendCalculator.plBucketWidth(min: 0, max: 2000) == 200)   // 21 at $100
        #expect(TrendCalculator.plBucketWidth(min: -5000, max: 20000) == 2000)
        #expect(TrendCalculator.plBucketWidth(min: -1_000_000, max: 1_000_000) == 200_000)
        #expect(TrendCalculator.plBucketWidth(min: 50, max: 50) == 100)
    }

    @Test func plDistribution_onlyActiveSessions_returnsEmpty() {
        let s = Session(status: .active, buyIn: 200)
        #expect(TrendCalculator.sessionPLDistribution(sessions: [s]).isEmpty)
    }
}
