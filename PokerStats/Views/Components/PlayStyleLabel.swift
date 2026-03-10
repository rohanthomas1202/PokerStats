import SwiftUI

// MARK: - Play Style

enum PlayStyle: String, CaseIterable {
    case nit = "Nit"
    case rock = "Rock"
    case tag = "TAG"
    case lag = "LAG"
    case fish = "Fish"
    case maniac = "Maniac"
    case passive = "Passive"

    var color: Color {
        switch self {
        case .nit: .blue
        case .rock: .cyan
        case .tag: .pokerProfit
        case .lag: .orange
        case .fish: .yellow
        case .maniac: .pokerLoss
        case .passive: .purple
        }
    }

    var emoji: String {
        switch self {
        case .nit: "🪨"
        case .rock: "🗿"
        case .tag: "🎯"
        case .lag: "🔥"
        case .fish: "🐟"
        case .maniac: "💥"
        case .passive: "🐢"
        }
    }

    /// Classify play style from VPIP and PFR (both 0.0–1.0).
    /// Returns nil if either stat is nil.
    static func classify(vpip: Double?, pfr: Double?) -> PlayStyle? {
        guard let vpip, let pfr else { return nil }

        let aggressionRatio = vpip > 0 ? pfr / vpip : 0

        // Extremely tight
        if vpip < 0.12 {
            return .nit
        }

        // Tight
        if vpip < 0.18 {
            return aggressionRatio > 0.6 ? .rock : .passive
        }

        // Normal-ish VPIP (18-30%)
        if vpip <= 0.30 {
            return aggressionRatio > 0.6 ? .tag : .passive
        }

        // Loose (30-45%)
        if vpip <= 0.45 {
            return aggressionRatio > 0.5 ? .lag : .fish
        }

        // Very loose (>45%)
        return pfr > 0.30 ? .maniac : .fish
    }
}

// MARK: - Play Style Badge View

struct PlayStyleLabelView: View {
    let style: PlayStyle?

    var body: some View {
        if let style {
            HStack(spacing: 4) {
                Text(style.emoji)
                    .font(.caption2)
                Text(style.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(style.color.opacity(0.2), in: Capsule())
            .foregroundStyle(style.color)
        } else {
            Text("--")
                .font(.caption)
                .foregroundStyle(Color.pokerTextTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.pokerCard, in: Capsule())
        }
    }
}
