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

    /// A loss that rounds to zero shows as "$0" and is break even, not a loss.
    @Test func result_followsTheRoundedValue() {
        #expect(CurrencyFormatter.result(0) == .breakEven)
        #expect(CurrencyFormatter.result(-0.4) == .breakEven)
        #expect(CurrencyFormatter.result(-0.5) == .breakEven)
        #expect(CurrencyFormatter.result(-0.6) == .loss)
        #expect(CurrencyFormatter.result(250) == .profit)
        #expect(CurrencyFormatter.result(-0.004, fractionDigits: 2) == .breakEven)
        #expect(CurrencyFormatter.result(-0.25, fractionDigits: 2) == .loss)
        #expect(CurrencyFormatter.formatSigned(-0.25, fractionDigits: 2) == "-$0.25")
    }
}
