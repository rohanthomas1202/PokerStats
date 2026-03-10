import SwiftUI

struct MentalMetricSlider: View {
    let metricType: MentalMetricType
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: metricType.icon)
                    .foregroundStyle(colorForValue)
                Text(metricType.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(labelForValue)
                    .font(.caption)
                    .foregroundStyle(Color.pokerTextSecondary)
            }

            HStack(spacing: 8) {
                Text(metricType.lowLabel)
                    .font(.caption2)
                    .foregroundStyle(Color.pokerTextSecondary)
                    .frame(width: 60, alignment: .trailing)

                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                value = level
                            }
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                        } label: {
                            Circle()
                                .fill(level <= value ? colorForLevel(level) : Color.pokerCard)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Text("\(level)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(level <= value ? .white : Color.pokerTextSecondary)
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(level == value ? colorForLevel(level) : .clear, lineWidth: 2)
                                        .frame(width: 42, height: 42)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(metricType.highLabel)
                    .font(.caption2)
                    .foregroundStyle(Color.pokerTextSecondary)
                    .frame(width: 60, alignment: .leading)
            }
        }
    }

    private var colorForValue: Color {
        colorForLevel(value)
    }

    private var labelForValue: String {
        switch value {
        case 1: metricType.lowLabel
        case 5: metricType.highLabel
        case 3: "Neutral"
        case 2: metricType.higherIsBetter ? "Low" : "Mild"
        case 4: metricType.higherIsBetter ? "High" : "High"
        default: ""
        }
    }

    private func colorForLevel(_ level: Int) -> Color {
        if metricType.higherIsBetter {
            // Green at high, red at low (energy/focus)
            switch level {
            case 1: return .red
            case 2: return .orange
            case 3: return .yellow
            case 4: return .mint
            case 5: return .green
            default: return .gray
            }
        } else {
            // Green at low, red at high (tilt)
            switch level {
            case 1: return .green
            case 2: return .mint
            case 3: return .yellow
            case 4: return .orange
            case 5: return .red
            default: return .gray
            }
        }
    }
}
