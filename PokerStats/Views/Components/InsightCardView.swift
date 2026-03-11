import SwiftUI

struct InsightCardView: View {
    let insight: LeakInsight
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 10) {
                // Colored severity bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(ratingColor)
                    .frame(width: 4, height: 40)

                // Icon + stat name
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: insight.statKey.icon)
                            .font(.caption)
                            .foregroundStyle(ratingColor)
                        Text(insight.statKey.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    Text(String(format: "%.1f%%", insight.value * 100))
                        .font(.caption)
                        .foregroundStyle(Color.pokerTextSecondary)
                }

                Spacer()

                // Rating badge
                Text(ratingLabel)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ratingColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(ratingColor)

                // Expand chevron
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.pokerTextTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }

            // Message
            Text(insight.message)
                .font(.caption)
                .foregroundStyle(Color.pokerTextSecondary)

            // Expandable suggestion
            if isExpanded {
                Text(insight.suggestion)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.pokerCard, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .pokerCard()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var ratingColor: Color {
        switch insight.rating {
        case .healthy: .pokerProfit
        case .borderline: .yellow
        case .leak: .pokerLoss
        }
    }

    private var ratingLabel: String {
        switch insight.rating {
        case .healthy: "Healthy"
        case .borderline: "Borderline"
        case .leak: "Leak"
        }
    }
}
