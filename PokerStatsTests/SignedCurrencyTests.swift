import Foundation
import Testing
@testable import PokerStats

/// Signed money on the session screens and the widget (#296, #295). A value that
/// rounds to zero shows as "$0" with no sign and is not colored as a loss.
/// Expects an en_US simulator, as shared/fixtures/stats/display.json does.
@Suite("Signed currency")
struct SignedCurrencyTests {

    @Test func zero_hasNoSign() {
        #expect(CurrencyFormatter.formatSigned(0) == "$0")
    }

    @Test func lossUnderOneDollar_neverMinusZero() {
        #expect(CurrencyFormatter.formatSigned(-0.4) == "$0")
        #expect(CurrencyFormatter.formatSigned(-0.5) == "$0")
        #expect(CurrencyFormatter.formatSigned(-0.6) == "-$1")
    }

    @Test func signedValues() {
        #expect(CurrencyFormatter.formatSigned(250) == "+$250")
        #expect(CurrencyFormatter.formatSigned(0.4) == "$0")
        #expect(CurrencyFormatter.formatSigned(-100) == "-$100")
    }

    @Test func isLoss_followsTheRoundedValue() {
        #expect(!CurrencyFormatter.isLoss(0))
        #expect(!CurrencyFormatter.isLoss(-0.4))
        #expect(!CurrencyFormatter.isLoss(-0.5))
        #expect(CurrencyFormatter.isLoss(-0.6))
        #expect(!CurrencyFormatter.isLoss(250))
        #expect(!CurrencyFormatter.isLoss(-0.004, fractionDigits: 2))
        #expect(CurrencyFormatter.isLoss(-0.25, fractionDigits: 2))
    }
}
