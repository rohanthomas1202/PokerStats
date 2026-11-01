import Foundation

enum CurrencyFormatter {
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private static let preciseFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    /// Format as whole-dollar currency: "$1,234" or "-$567"
    static func format(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    /// Format with cents: "$1,234.56"
    static func formatPrecise(_ amount: Double) -> String {
        preciseFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// How a signed amount reads once it is rounded for display.
    enum Result: Equatable {
        case profit
        case loss
        /// The amount rounds to zero, so it shows as "$0" with no sign.
        case breakEven
    }

    /// Signed money, rounded half to even like `format` and `formatPrecise`:
    /// "+$250", "-$100", "+$18.50" with `fractionDigits: 2`.
    /// A value that rounds to zero shows as "$0" (or "$0.00"), never "+$0" or "-$0".
    ///
    /// `fractionDigits` is 0 for whole dollars or 2 for cents. Any value above 0
    /// shows cents, because only those two formatters exist.
    static func formatSigned(_ amount: Double, fractionDigits: Int = 0) -> String {
        let magnitude = fractionDigits > 0 ? formatPrecise(abs(amount)) : format(abs(amount))
        switch result(amount, fractionDigits: fractionDigits) {
        case .breakEven: return magnitude
        case .loss: return "-\(magnitude)"
        case .profit: return "+\(magnitude)"
        }
    }

    /// Whether `formatSigned` shows this amount as a loss. A loss that rounds to
    /// zero is not one: it shows as "$0" and reads as break even.
    static func isLoss(_ amount: Double, fractionDigits: Int = 0) -> Bool {
        result(amount, fractionDigits: fractionDigits) == .loss
    }

    /// Profit, loss or break even, from the value `formatSigned` shows. It rounds
    /// the number itself (half to even, like the formatters) instead of reading
    /// the formatted string, so it does not depend on the locale's minus sign.
    static func result(_ amount: Double, fractionDigits: Int = 0) -> Result {
        guard amount.isFinite else {
            return amount.isNaN ? .breakEven : (amount < 0 ? .loss : .profit)
        }
        let rounded = roundedForDisplay(amount, fractionDigits: fractionDigits)
        if rounded == 0 { return .breakEven }
        return rounded < 0 ? .loss : .profit
    }

    /// `amount` rounded half to even to the digits `formatSigned` shows. Rounds
    /// the shortest decimal form of the Double ("2.675", not 2.67499...), which is
    /// what NumberFormatter rounds, so ties land the same way.
    private static func roundedForDisplay(_ amount: Double, fractionDigits: Int) -> Decimal {
        var value = Decimal(string: "\(amount)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(amount)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, fractionDigits > 0 ? 2 : 0, .bankers)
        return rounded
    }

    // MARK: - Signed percent

    /// Signed percent with one decimal, as the session ROI shows it: "+12.5%",
    /// "-3.0%". A value that rounds to 0.0 shows as "0.0%", never "+0.0%" or "-0.0%".
    static func formatSignedPercent(_ percent: Double) -> String {
        guard percent.isFinite else { return String(format: "%+.1f%%", percent) }
        let magnitude = String(format: "%.1f%%", abs(percent))
        switch percentResult(percent) {
        case .breakEven: return magnitude
        case .loss: return "-\(magnitude)"
        case .profit: return "+\(magnitude)"
        }
    }

    /// Profit, loss or break even for a percent shown with one decimal. Reads the
    /// same "%.1f" rounding `formatSignedPercent` shows, so the two always agree.
    static func percentResult(_ percent: Double) -> Result {
        guard percent.isFinite else {
            return percent.isNaN ? .breakEven : (percent < 0 ? .loss : .profit)
        }
        if String(format: "%.1f", abs(percent)) == "0.0" { return .breakEven }
        return percent < 0 ? .loss : .profit
    }
}
