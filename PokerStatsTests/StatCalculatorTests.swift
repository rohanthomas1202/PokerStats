import Foundation
import Testing
@testable import PokerStats

@Suite("StatCalculator Tests")
struct StatCalculatorTests {

    // MARK: - VPIP Tests

    @Test func vpip_zeroHands_returnsNil() {
        let result = StatCalculator.vpip(hands: [])
        #expect(result == nil)
    }

    @Test func vpip_oneHandFold_returnsZero() {
        let hands = [TestHelpers.foldHand()]
        let result = StatCalculator.vpip(hands: hands)!
        #expect(abs(result - 0.0) < 0.001)
    }

    @Test func vpip_oneHandCall_returns100() {
        let hands = [Hand(preflopAction: .call, postflopResult: .wonBeforeShowdown)]
        let result = StatCalculator.vpip(hands: hands)!
        #expect(abs(result - 1.0) < 0.001)
    }

    @Test func vpip_tenHands3VPIP_returns30() {
        var hands: [Hand] = []
        for i in 1...7 { hands.append(TestHelpers.foldHand(number: i)) }
        hands.append(Hand(handNumber: 8, preflopAction: .call, postflopResult: .wonBeforeShowdown))
        hands.append(Hand(handNumber: 9, preflopAction: .call, postflopResult: .lostAtShowdown))
        hands.append(Hand(handNumber: 10, preflopAction: .raise, postflopResult: .wonAtShowdown))
        let result = StatCalculator.vpip(hands: hands)!
        #expect(abs(result - 0.3) < 0.001)
    }

    // MARK: - PFR Tests

    @Test func pfr_zeroHands_returnsNil() {
        let result = StatCalculator.pfr(hands: [])
        #expect(result == nil)
    }

    @Test func pfr_tenHands4PFR_returns40() {
        var hands: [Hand] = []
        for i in 1...6 { hands.append(TestHelpers.foldHand(number: i)) }
        for i in 7...10 { hands.append(Hand(handNumber: i, preflopAction: .raise, postflopResult: .wonPreflop)) }
        let result = StatCalculator.pfr(hands: hands)!
        #expect(abs(result - 0.4) < 0.001)
    }

    // MARK: - Fold to 3-Bet Tests

    @Test func foldTo3Bet_zeroFaced_returnsNil() {
        let hands = [TestHelpers.foldHand(), Hand(preflopAction: .raise, postflopResult: .wonPreflop)]
        let result = StatCalculator.foldTo3BetPercent(hands: hands)
        #expect(result == nil)
    }

    @Test func foldTo3Bet_4faced2folded_returns50() {
        let hands = [
            TestHelpers.raiseFaced3BetHand(number: 1, response: .folded),
            TestHelpers.raiseFaced3BetHand(number: 2, response: .folded),
            TestHelpers.raiseFaced3BetHand(number: 3, response: .called, result: .wonAtShowdown),
            TestHelpers.raiseFaced3BetHand(number: 4, response: .fourBetPlus, result: .wonBeforeShowdown),
        ]
        let result = StatCalculator.foldTo3BetPercent(hands: hands)!
        #expect(abs(result - 0.5) < 0.001)
    }

    // MARK: - C-Bet Tests

    @Test func cBet_zeroOpportunities_returnsNil() {
        let hands = [TestHelpers.foldHand()]
        let result = StatCalculator.cBetPercent(hands: hands)
        #expect(result == nil)
    }

    @Test func cBet_3opps2bets_returns67() {
        let hands = [
            TestHelpers.raiseWithCBetHand(number: 1, cBet: true, result: .wonBeforeShowdown),
            TestHelpers.raiseWithCBetHand(number: 2, cBet: true, result: .lostAtShowdown),
            TestHelpers.raiseWithCBetHand(number: 3, cBet: false, result: .lostBeforeShowdown),
        ]
        let result = StatCalculator.cBetPercent(hands: hands)!
        #expect(abs(result - 2.0/3.0) < 0.001)
    }

    // MARK: - WTSD Tests

    @Test func wtsd_zeroFlops_returnsNil() {
        let hands = [TestHelpers.foldHand()]
        let result = StatCalculator.wtsdPercent(hands: hands)
        #expect(result == nil)
    }

    @Test func wtsd_4flops2showdowns_returns50() {
        let hands = [
            Hand(handNumber: 1, preflopAction: .call, postflopResult: .wonAtShowdown),
            Hand(handNumber: 2, preflopAction: .call, postflopResult: .lostAtShowdown),
            Hand(handNumber: 3, preflopAction: .call, postflopResult: .wonBeforeShowdown),
            Hand(handNumber: 4, preflopAction: .call, postflopResult: .lostBeforeShowdown),
        ]
        let result = StatCalculator.wtsdPercent(hands: hands)!
        #expect(abs(result - 0.5) < 0.001)
    }

    // MARK: - W$SD Tests

    @Test func wsd_zeroShowdowns_returnsNil() {
        let hands = [Hand(preflopAction: .call, postflopResult: .wonBeforeShowdown)]
        let result = StatCalculator.wsdPercent(hands: hands)
        #expect(result == nil)
    }

    @Test func wsd_4showdowns3won_returns75() {
        let hands = [
            Hand(handNumber: 1, preflopAction: .call, postflopResult: .wonAtShowdown),
            Hand(handNumber: 2, preflopAction: .call, postflopResult: .wonAtShowdown),
            Hand(handNumber: 3, preflopAction: .call, postflopResult: .wonAtShowdown),
            Hand(handNumber: 4, preflopAction: .call, postflopResult: .lostAtShowdown),
        ]
        let result = StatCalculator.wsdPercent(hands: hands)!
        #expect(abs(result - 0.75) < 0.001)
    }

    // MARK: - Hands Folded Tests

    @Test func handsFolded_mixedHands() {
        let hands = [
            TestHelpers.foldHand(number: 1),
            TestHelpers.foldHand(number: 2),
            Hand(handNumber: 3, preflopAction: .call, postflopResult: .wonBeforeShowdown),
            TestHelpers.raiseFaced3BetHand(number: 4, response: .folded), // This is also a fold
        ]
        let result = StatCalculator.handsFolded(hands: hands)
        #expect(result == 3)
    }

    // MARK: - Worked Example A: Tight-Aggressive (10 hands)

    @Test func workedExampleA_tightAggressive() {
        let hands = [
            // Hand 1: Fold
            TestHelpers.foldHand(number: 1),
            // Hand 2: Raise, no 3-bet, c-bet, won before SD
            TestHelpers.raiseWithCBetHand(number: 2, cBet: true, result: .wonBeforeShowdown),
            // Hand 3: Fold
            TestHelpers.foldHand(number: 3),
            // Hand 4: Raise, no 3-bet, no c-bet, won at SD
            TestHelpers.raiseWithCBetHand(number: 4, cBet: false, result: .wonAtShowdown),
            // Hand 5: Fold
            TestHelpers.foldHand(number: 5),
            // Hand 6: Call, lost at SD
            TestHelpers.callShowdownHand(number: 6, won: false),
            // Hand 7: Fold
            TestHelpers.foldHand(number: 7),
            // Hand 8: Raise, faced 3-bet, called, won at SD, c-bet
            Hand(handNumber: 8, preflopAction: .raise, faced3Bet: true,
                 threeBetResponse: .called, postflopResult: .wonAtShowdown, didCBet: true),
            // Hand 9: Fold
            TestHelpers.foldHand(number: 9),
            // Hand 10: Raise, faced 3-bet, folded
            TestHelpers.raiseFaced3BetHand(number: 10, response: .folded),
        ]

        // VPIP: 5/10 = 50% (hands 2,4,6,8,10)
        let vpip = StatCalculator.vpip(hands: hands)!
        #expect(abs(vpip - 0.5) < 0.001)

        // PFR: 4/10 = 40% (hands 2,4,8,10)
        let pfr = StatCalculator.pfr(hands: hands)!
        #expect(abs(pfr - 0.4) < 0.001)

        // Fold to 3-bet: 1/2 = 50% (hands 8 and 10 faced 3-bet; 10 folded)
        let fold3b = StatCalculator.foldTo3BetPercent(hands: hands)!
        #expect(abs(fold3b - 0.5) < 0.001)

        // C-Bet: 2/3 = 66.7% (hands 2,4,8 had opportunity; 2 and 8 c-bet)
        let cbet = StatCalculator.cBetPercent(hands: hands)!
        #expect(abs(cbet - 2.0/3.0) < 0.001)

        // WTSD: 3/4 = 75% (hands 2,4,6,8 saw flop; 4,6,8 went to SD)
        let wtsd = StatCalculator.wtsdPercent(hands: hands)!
        #expect(abs(wtsd - 0.75) < 0.001)

        // W$SD: 2/3 = 66.7% (hands 4,6,8 went to SD; 4 and 8 won)
        let wsd = StatCalculator.wsdPercent(hands: hands)!
        #expect(abs(wsd - 2.0/3.0) < 0.001)

        // Hands folded: 6 (hands 1,3,5,7,9,10)
        let folded = StatCalculator.handsFolded(hands: hands)
        #expect(folded == 6)
    }

    // MARK: - Worked Example B: Loose-Passive (5 hands)

    @Test func workedExampleB_loosePassive() {
        let hands = [
            // Hand 1: Call, lost at SD
            TestHelpers.callShowdownHand(number: 1, won: false),
            // Hand 2: Call, lost at SD
            TestHelpers.callShowdownHand(number: 2, won: false),
            // Hand 3: Call, lost before SD
            Hand(handNumber: 3, preflopAction: .call, postflopResult: .lostBeforeShowdown),
            // Hand 4: Raise, no c-bet, won at SD
            TestHelpers.raiseWithCBetHand(number: 4, cBet: false, result: .wonAtShowdown),
            // Hand 5: Fold
            TestHelpers.foldHand(number: 5),
        ]

        // VPIP: 4/5 = 80%
        let vpip = StatCalculator.vpip(hands: hands)!
        #expect(abs(vpip - 0.8) < 0.001)

        // PFR: 1/5 = 20%
        let pfr = StatCalculator.pfr(hands: hands)!
        #expect(abs(pfr - 0.2) < 0.001)

        // Fold to 3-bet: nil (no 3-bet situations)
        #expect(StatCalculator.foldTo3BetPercent(hands: hands) == nil)

        // C-Bet: 0/1 = 0%
        let cbet = StatCalculator.cBetPercent(hands: hands)!
        #expect(abs(cbet - 0.0) < 0.001)

        // WTSD: 3/4 = 75% (hands 1,2,3,4 saw flop; 1,2,4 went to SD)
        let wtsd = StatCalculator.wtsdPercent(hands: hands)!
        #expect(abs(wtsd - 0.75) < 0.001)

        // W$SD: 1/3 = 33.3% (hands 1,2,4 went to SD; 4 won)
        let wsd = StatCalculator.wsdPercent(hands: hands)!
        #expect(abs(wsd - 1.0/3.0) < 0.001)

        // Hands folded: 1
        #expect(StatCalculator.handsFolded(hands: hands) == 1)
    }

    // MARK: - Worked Example C: Single Folded Hand

    @Test func workedExampleC_singleFoldedHand() {
        let hands = [TestHelpers.foldHand()]

        // VPIP: 0/1 = 0%
        #expect(abs(StatCalculator.vpip(hands: hands)! - 0.0) < 0.001)
        // PFR: 0/1 = 0%
        #expect(abs(StatCalculator.pfr(hands: hands)! - 0.0) < 0.001)
        // All other stats: nil (no opportunities)
        #expect(StatCalculator.foldTo3BetPercent(hands: hands) == nil)
        #expect(StatCalculator.cBetPercent(hands: hands) == nil)
        #expect(StatCalculator.wtsdPercent(hands: hands) == nil)
        #expect(StatCalculator.wsdPercent(hands: hands) == nil)
        // Hands folded: 1
        #expect(StatCalculator.handsFolded(hands: hands) == 1)
    }

    // MARK: - Money Stats Tests

    @Test func moneyStats_standardWin() {
        let session = TestHelpers.completedSession(buyIn: 200, cashOut: 450)
        let stats = StatCalculator.computeSessionStats(session: session)
        #expect(abs(stats.totalProfit - 250.0) < 0.01)
    }

    @Test func moneyStats_rebuyLoss() {
        let session = TestHelpers.completedSession(buyIn: 200, cashOut: 100, rebuys: 200)
        let stats = StatCalculator.computeSessionStats(session: session)
        #expect(abs(stats.totalProfit - (-300.0)) < 0.01)
    }

    @Test func moneyStats_zeroBuyIn() {
        let session = TestHelpers.completedSession(buyIn: 0, cashOut: 50)
        #expect(session.roi == nil)
    }

    @Test func moneyStats_noCashOut() {
        let session = TestHelpers.completedSession(buyIn: 200, cashOut: 0)
        let stats = StatCalculator.computeSessionStats(session: session)
        #expect(abs(stats.totalProfit - (-200.0)) < 0.01)
    }

    // MARK: - computeAll Aggregation Tests

    @Test func computeAll_multipleSessions_aggregates() {
        let s1 = TestHelpers.completedSession(buyIn: 200, cashOut: 300, hours: 2)
        let s2 = TestHelpers.completedSession(buyIn: 200, cashOut: 100, hours: 3)

        let hands: [Hand] = [
            TestHelpers.foldHand(number: 1),
            Hand(handNumber: 2, preflopAction: .call, postflopResult: .wonBeforeShowdown),
        ]

        let stats = StatCalculator.computeAll(hands: hands, sessions: [s1, s2])

        // Total profit: +100 + (-100) = 0
        #expect(abs(stats.totalProfit - 0.0) < 0.01)
        // Sessions: 2
        #expect(stats.sessionsPlayed == 2)
        // Avg profit: 0
        #expect(abs(stats.averageProfitPerSession! - 0.0) < 0.01)
        // Total hands: 2
        #expect(stats.totalHands == 2)
    }
}
