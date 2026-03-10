import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stat Gauge

struct StatGaugeView: View {
    let title: String
    let value: Double? // 0.0-1.0
    var referenceRange: ClosedRange<Double>? = nil

    private var displayValue: String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    private var gaugeValue: Double {
        value ?? 0
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: gaugeValue)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: gaugeValue)

                Text(displayValue)
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.bold)
            }
            .frame(width: 60, height: 60)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var gaugeColor: Color {
        guard let value else { return .gray }
        if value < 0.2 { return .blue }
        if value < 0.4 { return .green }
        if value < 0.6 { return .orange }
        return .red
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
        }
        .padding(32)
    }
}

// MARK: - Currency Input Field

struct CurrencyField: View {
    let title: String
    @Binding var text: String
    var prefix: String = "$"

    var body: some View {
        HStack {
            Text(prefix)
                .foregroundStyle(.secondary)
                .font(.title2)

            TextField(title, text: $text)
                .keyboardType(.numberPad)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
