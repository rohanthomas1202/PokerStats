import SwiftUI

// MARK: - Color Palette

extension Color {
    /// Pure black background
    static let pokerBackground = Color(red: 0.06, green: 0.06, blue: 0.08)
    /// Dark card surface
    static let pokerCard = Color(red: 0.12, green: 0.13, blue: 0.15)
    /// Subtle card border
    static let pokerCardBorder = Color.white.opacity(0.08)
    /// Profit green
    static let pokerProfit = Color(red: 0.2, green: 0.84, blue: 0.47)
    /// Loss red
    static let pokerLoss = Color(red: 1.0, green: 0.35, blue: 0.37)
    /// Primary text
    static let pokerTextPrimary = Color.white
    /// Secondary text
    static let pokerTextSecondary = Color.white.opacity(0.55)
    /// Tertiary text
    static let pokerTextTertiary = Color.white.opacity(0.35)
    /// Accent (used for buttons, highlights)
    static let pokerAccent = Color(red: 0.35, green: 0.55, blue: 1.0)
}

// MARK: - Spacing Tokens

enum PokerSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Card View Modifier

struct PokerCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(Color.pokerCard, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.pokerCardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func pokerCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(PokerCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Result Colors

extension Color {
    /// Color for a signed amount as `CurrencyFormatter.formatSigned` shows it:
    /// profit green, loss red, and secondary text for an amount that rounds to $0.
    static func pokerResult(_ amount: Double, fractionDigits: Int = 0) -> Color {
        pokerResult(CurrencyFormatter.result(amount, fractionDigits: fractionDigits))
    }

    /// Color for a profit, loss or break-even result, such as
    /// `CurrencyFormatter.percentResult` for a percent.
    static func pokerResult(_ result: CurrencyFormatter.Result) -> Color {
        switch result {
        case .profit: return .pokerProfit
        case .loss: return .pokerLoss
        case .breakEven: return .pokerTextSecondary
        }
    }
}
