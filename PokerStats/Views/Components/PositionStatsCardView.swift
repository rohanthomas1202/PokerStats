import SwiftUI

/// Compact card showing stats for a single table position.
struct PositionStatsCardView: View {
    let stats: PositionStats

    var body: some View {
        VStack(spacing: 8) {
            Text(stats.position.displayName)
                .font(.headline)
                .fontWeight(.bold)

            Text("\(stats.handCount) hands")
                .font(.caption2)
                .foregroundStyle(Color.pokerTextSecondary)

            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(ComputedStats.formatPercent(stats.vpip))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("VPIP")
                        .font(.caption2)
                        .foregroundStyle(Color.pokerTextSecondary)
                }

                VStack(spacing: 2) {
                    Text(ComputedStats.formatPercent(stats.pfr))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("PFR")
                        .font(.caption2)
                        .foregroundStyle(Color.pokerTextSecondary)
                }
            }
        }
        .frame(width: 120)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .pokerCard()
    }
}
