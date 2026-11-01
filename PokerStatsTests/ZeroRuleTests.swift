import Foundation
import SwiftUI
import Testing
@testable import PokerStats

/// The $0 zero rule on the Dashboard total, Trends day-of-week bars and the
/// end-of-session headline (#299). An amount that rounds to $0 shows as "$0",
/// reads "Break Even" and takes the secondary text color, never profit or loss.
/// Expects an en_US simulator, as SignedCurrencyTests does.
@Suite("Zero rule")
struct ZeroRuleTests {

    @Test func roundsToZero_isBreakEven() {
        for amount in [0, -0.0, 0.004, -0.004, 0.4, -0.4, 0.5, -0.5] {
            #expect(CurrencyFormatter.result(amount) == .breakEven)
            #expect(CurrencyFormatter.formatSigned(amount) == "$0")
        }
        #expect(CurrencyFormatter.result(0.004, fractionDigits: 2) == .breakEven)
        #expect(CurrencyFormatter.result(-0.004, fractionDigits: 2) == .breakEven)
        #expect(CurrencyFormatter.result(-0.005, fractionDigits: 2) == .breakEven)
        #expect(CurrencyFormatter.result(-0.006, fractionDigits: 2) == .loss)
        #expect(CurrencyFormatter.result(0.01, fractionDigits: 2) == .profit)
    }

    @Test func profitAndLoss_followTheRoundedValue() {
        #expect(CurrencyFormatter.result(-0.6) == .loss)
        #expect(CurrencyFormatter.result(0.6) == .profit)
        #expect(CurrencyFormatter.result(-1_234.4) == .loss)
        #expect(CurrencyFormatter.result(1_234.4) == .profit)
    }

    /// The rounded value and the formatted string must agree, including ties,
    /// so the sign, the label and the color never disagree.
    @Test func result_matchesFormattedString() {
        for digits in [0, 2] {
            for i in -2_000...2_000 {
                let amount = Double(i) / 1_000
                let shown = CurrencyFormatter.formatSigned(amount, fractionDigits: digits)
                switch CurrencyFormatter.result(amount, fractionDigits: digits) {
                case .loss: #expect(shown.hasPrefix("-"), "\(amount) at \(digits): \(shown)")
                case .profit: #expect(shown.hasPrefix("+"), "\(amount) at \(digits): \(shown)")
                case .breakEven:
                    #expect(!shown.hasPrefix("-") && !shown.hasPrefix("+"), "\(amount) at \(digits): \(shown)")
                    #expect(!shown.contains { ($0.wholeNumberValue ?? 0) != 0 }, "\(amount) at \(digits): \(shown)")
                }
            }
        }
    }

    @Test func colors() {
        #expect(Color.pokerResult(-0.004) == .pokerTextSecondary)
        #expect(Color.pokerResult(0.004) == .pokerTextSecondary)
        #expect(Color.pokerResult(0) == .pokerTextSecondary)
        #expect(Color.pokerResult(-0.4) == .pokerTextSecondary)
        #expect(Color.pokerResult(-0.6) == .pokerLoss)
        #expect(Color.pokerResult(0.6) == .pokerProfit)
        #expect(Color.pokerResult(-0.004, fractionDigits: 2) == .pokerTextSecondary)
        #expect(Color.pokerResult(-0.01, fractionDigits: 2) == .pokerLoss)
    }

    @Test func endSessionHeadline() {
        #expect(EndSessionSummaryView.headline(for: 0) == "Break Even")
        #expect(EndSessionSummaryView.headline(for: -0.004) == "Break Even")
        #expect(EndSessionSummaryView.headline(for: 0.004) == "Break Even")
        #expect(EndSessionSummaryView.headline(for: -0.6) == "Loss")
        #expect(EndSessionSummaryView.headline(for: 250) == "Profit")
    }

    /// The Dashboard total now uses formatSigned, like the Lifetime widget.
    @Test func dashboardTotal_usesSignedFormat() {
        #expect(CurrencyFormatter.formatSigned(1_234) == "+$1,234")
        #expect(CurrencyFormatter.formatSigned(-567) == "-$567")
        #expect(CurrencyFormatter.formatSigned(-0.004) == "$0")
    }
}
