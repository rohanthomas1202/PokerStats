import SwiftUI

/// The one mapping from a profit, loss or break-even result to a color, shared
/// by the app and the Lifetime widget so the two cannot drift apart (#309).
struct ResultPalette {
    let profit: Color
    let loss: Color
    let breakEven: Color

    func color(for result: CurrencyFormatter.Result) -> Color {
        switch result {
        case .profit: return profit
        case .loss: return loss
        case .breakEven: return breakEven
        }
    }

    /// The Lifetime widget. It uses the system green and red, and white at 0.6
    /// for break even, which is the widget's own secondary text color (its
    /// captions and labels use 0.6 on the black container background). The app's
    /// `pokerTextSecondary` is 0.55; the widget keeps 0.6 so its $0 total matches
    /// the rest of the widget.
    static let widget = ResultPalette(profit: .green, loss: .red, breakEven: .white.opacity(0.6))
}
