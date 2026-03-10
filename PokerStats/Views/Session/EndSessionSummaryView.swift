import SwiftUI

struct EndSessionSummaryView: View {
    let session: Session
    let onDone: () -> Void

    private var stats: ComputedStats {
        StatCalculator.computeSessionStats(session: session)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Headline result
                VStack(spacing: 8) {
                    Text(session.netProfit >= 0 ? "Profit" : "Loss")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(CurrencyFormatter.formatSigned(session.netProfit))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(session.netProfit >= 0 ? Color.pokerProfit : Color.pokerLoss)

                    Text("\(DateFormatting.formatFull(session.startTime)) - \(DurationFormatter.format(session.duration))")
                        .font(.caption)
                        .foregroundStyle(Color.pokerTextSecondary)
                }
                .padding(.top)

                // Financial breakdown
                VStack(spacing: 12) {
                    Text("Financial Summary")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    financialRow("Buy-In", CurrencyFormatter.format(session.buyIn))
                    if session.rebuys > 0 {
                        financialRow("Rebuys", CurrencyFormatter.format(session.rebuys))
                    }
                    if session.addOns > 0 {
                        financialRow("Add-Ons", CurrencyFormatter.format(session.addOns))
                    }
                    financialRow("Total Invested", CurrencyFormatter.format(session.totalInvested))
                    financialRow("Cash Out", CurrencyFormatter.format(session.cashOut))
                    Divider()
                    financialRow("Net P/L", CurrencyFormatter.formatSigned(session.netProfit),
                                 valueColor: session.netProfit >= 0 ? .pokerProfit : .pokerLoss)

                    if let hourlyRate = session.hourlyRate {
                        financialRow("Hourly Rate", ComputedStats.formatHourlyRate(hourlyRate))
                    }
                }
                .padding()
                .pokerCard()

                // Session stats
                if stats.totalHands > 0 {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Session Stats")
                                .font(.headline)
                            PlayStyleLabelView(
                                style: PlayStyle.classify(vpip: stats.vpip, pfr: stats.pfr)
                            )
                            Spacer()
                        }

                        // 2-column stat grid with range bars
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            StatCardView(
                                title: "VPIP",
                                value: ComputedStats.formatPercent(stats.vpip),
                                statDef: .vpip,
                                rangeValue: stats.vpip,
                                rangeGoodRange: StatDefinition.vpip.goodRange
                            )
                            StatCardView(
                                title: "PFR",
                                value: ComputedStats.formatPercent(stats.pfr),
                                statDef: .pfr,
                                rangeValue: stats.pfr,
                                rangeGoodRange: StatDefinition.pfr.goodRange
                            )
                            StatCardView(
                                title: "C-Bet",
                                value: ComputedStats.formatPercent(stats.cBetPercent),
                                statDef: .cBet,
                                rangeValue: stats.cBetPercent,
                                rangeGoodRange: StatDefinition.cBet.goodRange
                            )
                            StatCardView(
                                title: "WTSD",
                                value: ComputedStats.formatPercent(stats.wtsdPercent),
                                statDef: .wtsd,
                                rangeValue: stats.wtsdPercent,
                                rangeGoodRange: StatDefinition.wtsd.goodRange
                            )
                        }

                        HStack(spacing: 8) {
                            StatCardView(title: "Hands", value: "\(stats.totalHands)")
                            StatCardView(
                                title: "W$SD",
                                value: ComputedStats.formatPercent(stats.wsdPercent),
                                statDef: .wsd
                            )
                        }
                    }
                    .padding()
                    .pokerCard()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.raised.slash")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No hands logged")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Try logging hands next session for detailed stats")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }

                // Done button
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pokerAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Session Complete")
    }

    private func financialRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(valueColor)
        }
        .font(.subheadline)
    }
}
