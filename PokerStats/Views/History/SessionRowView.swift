import SwiftUI

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            // Profit/Loss indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(session.netProfit >= 0 ? Color.pokerProfit : Color.pokerLoss)
                .frame(width: 4)

            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatting.formatMonthDay(session.startTime))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(DateFormatting.formatShortDay(session.startTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50, alignment: .leading)

            // Game info
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.stakes) \(session.gameType.displayName)")
                    .font(.subheadline)
                    .lineLimit(1)
                if !session.location.isEmpty {
                    Text(session.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // P/L and duration
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.formatSigned(session.netProfit))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(session.netProfit >= 0 ? Color.pokerProfit : Color.pokerLoss)

                HStack(spacing: 4) {
                    Text(DurationFormatter.format(session.duration))
                    if session.handCount > 0 {
                        Text("- \(session.handCount)h")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
