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

    @Test func plDistribution_onlyActiveSessions_returnsEmpty() {
        let s = Session(status: .active, buyIn: 200)
        #expect(TrendCalculator.sessionPLDistribution(sessions: [s]).isEmpty)
    }
}
