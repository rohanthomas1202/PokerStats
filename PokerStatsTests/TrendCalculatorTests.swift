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
}
