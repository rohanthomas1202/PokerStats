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
}
