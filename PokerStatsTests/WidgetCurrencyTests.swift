import Foundation
import Testing
@testable import PokerStats

/// The lifetime widget's money strings (#249). They round half to even like the
/// app, and a value that rounds to zero has no sign. Expects an en_US simulator,
/// as shared/fixtures/stats/display.json does.
@Suite("Widget currency")
struct WidgetCurrencyTests {

    @Test func zero_hasNoSign() {
        #expect(CurrencyFormatter.formatSigned(0) == "$0")
        #expect(CurrencyFormatter.formatSigned(-0.0) == "$0")
    }

    @Test func lossUnderOneDollar_matchesApp_neverMinusZero() {
        // Half to even: 0.5 rounds to 0, as CurrencyFormatter.format does.
        #expect(CurrencyFormatter.format(0.5) == "$0")
        #expect(CurrencyFormatter.formatSigned(-0.5) == "$0")
        #expect(CurrencyFormatter.formatSigned(-0.4) == "$0")
        #expect(CurrencyFormatter.formatSigned(-0.6) == "-$1")
    }

    @Test func totals_roundHalfToEven() {
        #expect(CurrencyFormatter.formatSigned(1999.99) == "+$2,000")
        #expect(CurrencyFormatter.formatSigned(999.9) == "+$1,000")
        #expect(CurrencyFormatter.formatSigned(-280) == "-$280")
        #expect(CurrencyFormatter.formatSigned(2.5) == "+$2")
        #expect(CurrencyFormatter.formatSigned(3.5) == "+$4")
    }

    @Test func hourly_showsCents() {
        #expect(CurrencyFormatter.formatSigned(18.5, fractionDigits: 2) == "+$18.50")
        #expect(CurrencyFormatter.formatSigned(1234.56, fractionDigits: 2) == "+$1,234.56")
        #expect(CurrencyFormatter.formatSigned(-35, fractionDigits: 2) == "-$35.00")
        #expect(CurrencyFormatter.formatSigned(-0.004, fractionDigits: 2) == "$0.00")
    }
}
