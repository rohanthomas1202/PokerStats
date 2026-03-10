import SwiftUI

/// Horizontal gradient bar (green→yellow→red) with a dot indicator showing where a stat falls.
/// `goodRange` defines the "healthy" zone. `isInverted` flips so higher = worse (e.g., fold-to-3-bet).
struct RangeBarView: View {
    let value: Double? // 0.0–1.0
    let goodRange: ClosedRange<Double> // e.g. 0.18...0.28 for VPIP
    var isInverted: Bool = false

    private var normalizedPosition: CGFloat {
        guard let value else { return 0 }
        return CGFloat(min(max(value, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 6

            ZStack(alignment: .leading) {
                // Background gradient bar
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: isInverted
                                ? [.red, .yellow, .green]
                                : [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: height)
                    .opacity(0.35)

                // Good range overlay
                let startX = CGFloat(goodRange.lowerBound) * width
                let rangeWidth = CGFloat(goodRange.upperBound - goodRange.lowerBound) * width
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.pokerProfit.opacity(0.3))
                    .frame(width: rangeWidth, height: height)
                    .offset(x: startX)

                // Indicator dot
                if value != nil {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 12, height: 12)
                        .shadow(color: dotColor.opacity(0.5), radius: 4)
                        .offset(x: normalizedPosition * (width - 12))
                }
            }
            .frame(height: 12)
        }
        .frame(height: 12)
    }

    private var dotColor: Color {
        guard let value else { return .gray }
        let effectiveValue = isInverted ? 1.0 - value : value
        if goodRange.contains(value) {
            return .pokerProfit
        }
        // Distance from good range determines color
        let dist: Double
        if value < goodRange.lowerBound {
            dist = isInverted ? (goodRange.lowerBound - value) : (goodRange.lowerBound - value)
        } else {
            dist = isInverted ? (value - goodRange.upperBound) : (value - goodRange.upperBound)
        }
        _ = effectiveValue // suppress warning
        if dist < 0.1 { return .yellow }
        return .pokerLoss
    }
}
