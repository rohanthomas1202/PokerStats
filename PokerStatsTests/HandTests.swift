import Foundation
import Testing
@testable import PokerStats

@Suite("Hand Computed Properties Tests")
struct HandTests {

    // MARK: - voluntarilyPutMoneyIn

    @Test func vpip_fold_isFalse() {
        let hand = Hand(preflopAction: .fold)
        #expect(hand.voluntarilyPutMoneyIn == false)
    }

    @Test func vpip_call_isTrue() {
        let hand = Hand(preflopAction: .call, postflopResult: .wonBeforeShowdown)
        #expect(hand.voluntarilyPutMoneyIn == true)
    }

    @Test func vpip_raise_isTrue() {
        let hand = Hand(preflopAction: .raise, postflopResult: .wonPreflop)
        #expect(hand.voluntarilyPutMoneyIn == true)
    }

    // MARK: - raisedPreflop

    @Test func pfr_fold_isFalse() {
        #expect(Hand(preflopAction: .fold).raisedPreflop == false)
    }

    @Test func pfr_call_isFalse() {
        #expect(Hand(preflopAction: .call).raisedPreflop == false)
    }

    @Test func pfr_raise_isTrue() {
        #expect(Hand(preflopAction: .raise).raisedPreflop == true)
    }

    // MARK: - foldedPreflop

    @Test func foldedPreflop_fold_isTrue() {
        #expect(Hand(preflopAction: .fold).foldedPreflop == true)
    }

    @Test func foldedPreflop_call_isFalse() {
        #expect(Hand(preflopAction: .call, postflopResult: .wonBeforeShowdown).foldedPreflop == false)
    }

    @Test func foldedPreflop_raiseFaced3BetFolded_isTrue() {
        let hand = Hand(preflopAction: .raise, faced3Bet: true, threeBetResponse: .folded)
        #expect(hand.foldedPreflop == true)
    }

    @Test func foldedPreflop_raiseFaced3BetCalled_isFalse() {
        let hand = Hand(preflopAction: .raise, faced3Bet: true, threeBetResponse: .called, postflopResult: .wonAtShowdown)
        #expect(hand.foldedPreflop == false)
    }

    // MARK: - sawFlop

    @Test func sawFlop_fold_isFalse() {
        #expect(Hand(preflopAction: .fold).sawFlop == false)
    }

    @Test func sawFlop_wonPreflop_isFalse() {
        #expect(Hand(preflopAction: .raise, postflopResult: .wonPreflop).sawFlop == false)
    }

    @Test func sawFlop_wonBeforeShowdown_isTrue() {
        #expect(Hand(preflopAction: .call, postflopResult: .wonBeforeShowdown).sawFlop == true)
    }

    @Test func sawFlop_wonAtShowdown_isTrue() {
        #expect(Hand(preflopAction: .call, postflopResult: .wonAtShowdown).sawFlop == true)
    }

    // MARK: - wentToShowdown

    @Test func showdown_wonAtShowdown_isTrue() {
        #expect(Hand(preflopAction: .call, postflopResult: .wonAtShowdown).wentToShowdown == true)
    }

    @Test func showdown_lostAtShowdown_isTrue() {
        #expect(Hand(preflopAction: .call, postflopResult: .lostAtShowdown).wentToShowdown == true)
    }

    @Test func showdown_wonBeforeShowdown_isFalse() {
        #expect(Hand(preflopAction: .call, postflopResult: .wonBeforeShowdown).wentToShowdown == false)
    }

    // MARK: - hadCBetOpportunity

    @Test func cBetOpp_raiseAndSawFlop_isTrue() {
        let hand = Hand(preflopAction: .raise, postflopResult: .wonBeforeShowdown)
        #expect(hand.hadCBetOpportunity == true)
    }

    @Test func cBetOpp_callAndSawFlop_isFalse() {
        let hand = Hand(preflopAction: .call, postflopResult: .wonBeforeShowdown)
        #expect(hand.hadCBetOpportunity == false)
    }

    @Test func cBetOpp_raiseWonPreflop_isFalse() {
        let hand = Hand(preflopAction: .raise, postflopResult: .wonPreflop)
        #expect(hand.hadCBetOpportunity == false)
    }

    // MARK: - actionSummary

    @Test func actionSummary_fold() {
        let hand = Hand(preflopAction: .fold)
        #expect(hand.actionSummary == "Folded preflop")
    }

    @Test func actionSummary_raiseWonPreflop() {
        let hand = Hand(preflopAction: .raise, postflopResult: .wonPreflop)
        #expect(hand.actionSummary == "Raised, Won PF")
    }

    @Test func actionSummary_callWonAtShowdown() {
        let hand = Hand(preflopAction: .call, postflopResult: .wonAtShowdown)
        #expect(hand.actionSummary == "Called, Won SD")
    }

    @Test func actionSummary_raiseFaced3BetFolded() {
        let hand = Hand(preflopAction: .raise, faced3Bet: true, threeBetResponse: .folded)
        #expect(hand.actionSummary.contains("faced 3-bet"))
        #expect(hand.actionSummary.contains("folded"))
    }
}
