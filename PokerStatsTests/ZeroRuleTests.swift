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

    /// Values one Double step either side of a rounding tie, where the rounded
    /// value and NumberFormatter are most likely to disagree (#309).
    @Test func boundaryAdjacentValues() {
        let wholeDollars: [(Double, String)] = [
            (0.5.nextUp, "+$1"), (0.5.nextDown, "$0"),
            ((-0.5).nextUp, "$0"), ((-0.5).nextDown, "-$1"),
            (-0.49999999999999994, "$0"), (0.5000000000000001, "+$1"),
            (1.5.nextDown, "+$1"), (1.5, "+$2"), (2.5.nextUp, "+$3"),
        ]
        let cents: [(Double, String)] = [
            (0.005.nextUp, "+$0.01"), (0.005.nextDown, "$0.00"),
            ((-0.005).nextUp, "$0.00"), ((-0.005).nextDown, "-$0.01"),
            (0.0050000000000001, "+$0.01"), (-0.0050000000000001, "-$0.01"),
            (0.015, "+$0.02"), (0.025, "+$0.02"),
        ]
        for (digits, cases) in [(0, wholeDollars), (2, cents)] {
            for (amount, expected) in cases {
                let shown = CurrencyFormatter.formatSigned(amount, fractionDigits: digits)
                #expect(shown == expected, "\(amount) at \(digits)")
                let result: CurrencyFormatter.Result = expected.hasPrefix("+") ? .profit : expected.hasPrefix("-") ? .loss : .breakEven
                #expect(CurrencyFormatter.result(amount, fractionDigits: digits) == result, "\(amount) at \(digits)")
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

    /// The Lifetime widget's total color goes through the shared palette: system
    /// green and red, and the widget's own secondary white at 0.6 for $0 (#309).
    @Test func widgetColors() {
        let widget = ResultPalette.widget
        #expect(widget.color(for: CurrencyFormatter.result(-0.4)) == Color.white.opacity(0.6))
        #expect(widget.color(for: CurrencyFormatter.result(0)) == Color.white.opacity(0.6))
        #expect(widget.color(for: CurrencyFormatter.result(250)) == Color.green)
        #expect(widget.color(for: CurrencyFormatter.result(-0.6)) == Color.red)
        #expect(ResultPalette.app.color(for: .breakEven) == Color.pokerTextSecondary)
        #expect(ResultPalette.app.color(for: .profit) == Color.pokerProfit)
        #expect(ResultPalette.app.color(for: .loss) == Color.pokerLoss)
    }

    /// The Dashboard total as DashboardView builds it, with a "+" on a profit
    /// like the Lifetime widget (#299).
    @Test func dashboardTotal_text() {
        #expect(DashboardView.totalProfitText(1_234) == "+$1,234")
        #expect(DashboardView.totalProfitText(1_234_567.5) == "+$1,234,568")
        #expect(DashboardView.totalProfitText(-567) == "-$567")
        #expect(DashboardView.totalProfitText(-0.004) == "$0")
        #expect(DashboardView.totalProfitText(0.5) == "$0")
        #expect(DashboardView.totalProfitText(-280) == "-$280")
    }

    /// The Calm vs Tilted rates as the Mental Insights card builds them (#308).
    @Test func mentalRates_text() {
        #expect(DashboardView.mentalRateText(12.5) == "+$12.50/hr")
        #expect(DashboardView.mentalRateText(1_234.56) == "+$1,234.56/hr")
        #expect(DashboardView.mentalRateText(-3) == "-$3.00/hr")
        #expect(DashboardView.mentalRateText(-0.004) == "$0.00/hr")
        #expect(DashboardView.mentalRateText(0) == "$0.00/hr")
    }

    /// Each Calm or Tilted rate block is one VoiceOver element that says the
    /// unit once (#313).
    @Test func mentalRates_accessibilityLabel() {
        #expect(DashboardView.mentalRateAccessibilityLabel("Calm", 12.5) == "Calm, +$12.50 per hour")
        #expect(DashboardView.mentalRateAccessibilityLabel("Tilted", -3) == "Tilted, -$3.00 per hour")
        #expect(DashboardView.mentalRateAccessibilityLabel("Calm", -0.004) == "Calm, $0.00 per hour")
    }

    /// The Session ROI row as SessionDetailView builds it (#308).
    @Test func sessionROI_display() {
        let profit = SessionDetailView.roiDisplay(netProfit: 50, totalInvested: 200)
        #expect(profit.text == "+25.0%")
        #expect(profit.result == .profit)
        let loss = SessionDetailView.roiDisplay(netProfit: -300, totalInvested: 200)
        #expect(loss.text == "-150.0%")
        #expect(loss.result == .loss)
        let even = SessionDetailView.roiDisplay(netProfit: -0.01, totalInvested: 100)
        #expect(even.text == "0.0%")
        #expect(even.result == .breakEven)
        #expect(SessionDetailView.roiDisplay(netProfit: 12.5, totalInvested: 200).text == "+6.2%")
    }

    /// The Session ROI row is one VoiceOver element: the title, then the visible
    /// value, or "Not available" for an ROI that can't be calculated (#313, #322).
    @Test func sessionROI_accessibilityLabel() {
        let profit = SessionDetailView.roiDisplay(netProfit: 50, totalInvested: 200)
        #expect(profit.text == "+25.0%")
        #expect(profit.accessibilityLabel == "Session ROI, +25.0%")
        let loss = SessionDetailView.roiDisplay(netProfit: -300, totalInvested: 200)
        #expect(loss.text == "-150.0%")
        #expect(loss.result == .loss)
        #expect(loss.accessibilityLabel == "Session ROI, -150.0%")
        let zero = SessionDetailView.roiDisplay(netProfit: 0, totalInvested: 100)
        #expect(zero.text == "0.0%")
        #expect(zero.result == .breakEven)
        #expect(zero.accessibilityLabel == "Session ROI, 0.0%")
        for netProfit in [Double.infinity, -.infinity, .nan] {
            let notAvailable = SessionDetailView.roiDisplay(netProfit: netProfit, totalInvested: 100)
            #expect(notAvailable.text == "--", "\(netProfit)")
            #expect(notAvailable.result == .breakEven, "\(netProfit)")
            #expect(notAvailable.accessibilityLabel == "Session ROI, Not available", "\(netProfit)")
        }
    }

    // MARK: - Hourly rates and ROI (#308)

    /// Calm vs Tilted hourly rates show cents, so a rate under half a cent
    /// shows as "$0.00/hr" in the secondary color.
    @Test func hourlyRate_roundingToZero_isBreakEven() {
        for rate in [0, -0.0, 0.004, -0.004, -0.005, 0.005] {
            #expect(CurrencyFormatter.formatSigned(rate, fractionDigits: 2) + "/hr" == "$0.00/hr", "\(rate)")
            #expect(Color.pokerResult(rate, fractionDigits: 2) == .pokerTextSecondary, "\(rate)")
        }
        #expect(CurrencyFormatter.formatSigned(-0.01, fractionDigits: 2) + "/hr" == "-$0.01/hr")
        #expect(Color.pokerResult(-0.01, fractionDigits: 2) == .pokerLoss)
        #expect(CurrencyFormatter.formatSigned(12.5, fractionDigits: 2) + "/hr" == "+$12.50/hr")
        #expect(Color.pokerResult(12.5, fractionDigits: 2) == .pokerProfit)
    }

    /// Session ROI shows one decimal, so an ROI that rounds to 0.0 shows as
    /// "0.0%" with no sign, in the secondary color.
    @Test func roi_roundingToZero_isBreakEven() {
        for roi in [0, -0.0, 0.04, -0.04, 0.049, -0.049] {
            #expect(CurrencyFormatter.formatSignedPercent(roi) == "0.0%", "\(roi)")
            #expect(CurrencyFormatter.percentResult(roi) == .breakEven, "\(roi)")
            #expect(Color.pokerResult(CurrencyFormatter.percentResult(roi)) == .pokerTextSecondary, "\(roi)")
        }
        #expect(CurrencyFormatter.formatSignedPercent(-0.06) == "-0.1%")
        #expect(CurrencyFormatter.percentResult(-0.06) == .loss)
        #expect(CurrencyFormatter.formatSignedPercent(12.34) == "+12.3%")
        #expect(Color.pokerResult(CurrencyFormatter.percentResult(12.34)) == .pokerProfit)
        #expect(CurrencyFormatter.formatSignedPercent(-50) == "-50.0%")
        #expect(Color.pokerResult(CurrencyFormatter.percentResult(-50)) == .pokerLoss)
    }

    /// Exact strings, including ties and values just off a tie.
    @Test func roi_expectedStrings() {
        let cases: [(Double, String)] = [
            (0.05, "+0.1%"), (-0.05, "-0.1%"), (0.25, "+0.2%"), (0.35, "+0.3%"),
            (6.25, "+6.2%"), (6.25.nextUp, "+6.3%"), (-0.049, "0.0%"),
            (12.34, "+12.3%"), (1_234.56, "+1234.6%"), (-100, "-100.0%"),
        ]
        for (roi, expected) in cases {
            #expect(CurrencyFormatter.formatSignedPercent(roi) == expected, "\(roi)")
        }
    }

    /// A non-finite percent shows as "--" and is break even, so the text and
    /// the color agree (#309).
    @Test func roi_nonFinite_isPlaceholder() {
        for roi in [Double.nan, .infinity, -.infinity] {
            #expect(CurrencyFormatter.formatSignedPercent(roi) == "--", "\(roi)")
            #expect(CurrencyFormatter.percentResult(roi) == .breakEven, "\(roi)")
        }
    }

    /// The ROI sign and its result agree across ties.
    @Test func roi_resultMatchesFormattedString() {
        for i in -2_000...2_000 {
            let roi = Double(i) / 1_000
            let shown = CurrencyFormatter.formatSignedPercent(roi)
            switch CurrencyFormatter.percentResult(roi) {
            case .loss: #expect(shown.hasPrefix("-"), "\(roi): \(shown)")
            case .profit: #expect(shown.hasPrefix("+"), "\(roi): \(shown)")
            case .breakEven: #expect(shown == "0.0%", "\(roi): \(shown)")
            }
        }
    }
}
