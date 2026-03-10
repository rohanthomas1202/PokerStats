import SwiftUI

struct StatCardView: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = .pokerTextPrimary
    var statDef: StatDefinition? = nil
    var rangeValue: Double? = nil
    var rangeGoodRange: ClosedRange<Double>? = nil
    var rangeIsInverted: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.pokerTextSecondary)
                    .lineLimit(1)

                if let statDef {
                    StatHelpButton(definition: statDef)
                }
            }

            // Split value: number vs "%" suffix
            if value.hasSuffix("%"), let numPart = value.dropLast().description as String? {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(numPart)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(valueColor)
                    Text("%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.pokerTextSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.pokerTextTertiary)
                    .lineLimit(1)
            }

            if let rangeGoodRange {
                RangeBarView(
                    value: rangeValue,
                    goodRange: rangeGoodRange,
                    isInverted: rangeIsInverted
                )
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .pokerCard()
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
                    .stroke(Color.pokerTextTertiary.opacity(0.3), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: gaugeValue)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: gaugeValue)

                Text(displayValue)
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.pokerTextPrimary)
            }
            .frame(width: 80, height: 80)

            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.pokerTextSecondary)
                .lineLimit(1)
        }
    }

    private var gaugeColor: Color {
        guard let value else { return .gray }
        if value < 0.2 { return .blue }
        if value < 0.4 { return .pokerProfit }
        if value < 0.6 { return .orange }
        return .pokerLoss
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
                .foregroundStyle(Color.pokerTextSecondary)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.pokerTextPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.pokerTextSecondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pokerAccent)
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
                .foregroundStyle(Color.pokerTextSecondary)
                .font(.title2)

            TextField(title, text: $text)
                .keyboardType(.numberPad)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color.pokerCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.pokerCardBorder, lineWidth: 1)
        )
    }
}
