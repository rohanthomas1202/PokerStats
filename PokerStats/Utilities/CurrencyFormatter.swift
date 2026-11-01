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

    /// Format as signed string with color hint: "+$250" or "-$100"
    static func formatSigned(_ amount: Double) -> String {
        let formatted = format(abs(amount))
        if amount >= 0 {
            return "+\(formatted)"
        } else {
            return "-\(formatted)"
        }
    }

    /// Signed money for the home-screen widget, rounded half to even like
    /// `format` and `formatPrecise`: "+$2,000", "-$280", "+$18.50".
    /// A value that rounds to zero shows as "$0" (or "$0.00"), never "+$0" or "-$0".
    static func formatSignedRounded(_ amount: Double, fractionDigits: Int = 0) -> String {
        let magnitude = fractionDigits > 0 ? formatPrecise(abs(amount)) : format(abs(amount))
        let isZero = !magnitude.contains { ($0.wholeNumberValue ?? 0) != 0 }
        if isZero { return magnitude }
        return amount < 0 ? "-\(magnitude)" : "+\(magnitude)"
    }
}
