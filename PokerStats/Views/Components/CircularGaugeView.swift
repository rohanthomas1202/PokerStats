import SwiftUI

/// Large circular gauge ring (100x100, 10pt stroke) with gradient color,
/// center text (split number/% typography), title + emoji below.
struct CircularGaugeView: View {
    let title: String
    let value: Double? // 0.0–1.0
    var emoji: String = ""
    var gradientColors: [Color] = [.pokerProfit, .pokerAccent]

    private var displayPercent: String {
        guard let value else { return "--" }
        return String(format: "%.0f", value * 100)
    }

    private var gaugeValue: Double {
        value ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.pokerTextTertiary.opacity(0.2), lineWidth: 10)

                // Value ring
                Circle()
                    .trim(from: 0, to: gaugeValue)
                    .stroke(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: gaugeValue)

                // Center text
                if value != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(displayPercent)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.pokerTextPrimary)
                        Text("%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.pokerTextSecondary)
                    }
                } else {
                    Text("--")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.pokerTextTertiary)
                }
            }
            .frame(width: 100, height: 100)

            // Title + emoji
            HStack(spacing: 4) {
                if !emoji.isEmpty {
                    Text(emoji)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.pokerTextSecondary)
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        CircularGaugeView(
            title: "Fold %",
            value: 0.72,
            emoji: "🃏",
            gradientColors: [.pokerProfit, .cyan]
        )
        CircularGaugeView(
            title: "Fold to 3B",
            value: 0.55,
            emoji: "🛡️",
            gradientColors: [.orange, .pokerLoss]
        )
        CircularGaugeView(
            title: "No Data",
            value: nil,
            emoji: "❓"
        )
    }
    .padding()
    .background(Color.pokerBackground)
    .preferredColorScheme(.dark)
}
