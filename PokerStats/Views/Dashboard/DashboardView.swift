import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTab: Int
    @State private var viewModel = DashboardViewModel()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 20) {
                    // Active session banner
                    if let activeSession = viewModel.activeSession {
                        activeSessionBanner(activeSession)
                    }

                    // Financial summary
                    financialSummary

                    // Playing stats gauges
                    playingStats

                    // Recent sessions
                    recentSessions
                }
                .padding()
            }
            .navigationTitle("PokerStats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: "settings") {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(session: session)
            }
            .navigationDestination(for: String.self) { route in
                if route == "settings" {
                    SettingsView()
                }
            }
            .onAppear {
                viewModel.loadData(from: modelContext)
            }
        }
    }

    // MARK: - Active Session Banner

    @ViewBuilder
    private func activeSessionBanner(_ session: Session) -> some View {
        Button {
            selectedTab = 1
        } label: {
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .fill(.green.opacity(0.4))
                            .frame(width: 20, height: 20)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Session Active")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(session.stakes) \(session.gameType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(DurationFormatter.formatTimer(session.duration))
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.medium)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Financial Summary

    private var financialSummary: some View {
        VStack(spacing: 12) {
            // Total P/L
            Text(ComputedStats.formatCurrency(viewModel.lifetimeStats.totalProfit))
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(viewModel.lifetimeStats.totalProfit >= 0 ? .green : .red)

            Text("Total Profit/Loss")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Sub-metrics
            HStack(spacing: 0) {
                StatCardView(
                    title: "Hourly Rate",
                    value: ComputedStats.formatHourlyRate(viewModel.lifetimeStats.hourlyRate)
                )
                StatCardView(
                    title: "Hours",
                    value: String(format: "%.0f", viewModel.lifetimeStats.totalHoursPlayed)
                )
                StatCardView(
                    title: "Sessions",
                    value: "\(viewModel.lifetimeStats.sessionsPlayed)"
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Playing Stats

    private var playingStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playing Tendencies")
                .font(.headline)

            HStack(spacing: 16) {
                StatGaugeView(title: "VPIP", value: viewModel.lifetimeStats.vpip)
                StatGaugeView(title: "PFR", value: viewModel.lifetimeStats.pfr)
                StatGaugeView(title: "C-Bet", value: viewModel.lifetimeStats.cBetPercent)
                StatGaugeView(title: "WTSD", value: viewModel.lifetimeStats.wtsdPercent)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                StatCardView(
                    title: "Hands",
                    value: "\(viewModel.lifetimeStats.totalHands)"
                )
                StatCardView(
                    title: "Folded",
                    value: ComputedStats.formatPercent(
                        viewModel.lifetimeStats.totalHands > 0
                        ? Double(viewModel.lifetimeStats.handsFolded) / Double(viewModel.lifetimeStats.totalHands)
                        : nil
                    )
                )
                StatCardView(
                    title: "W$SD",
                    value: ComputedStats.formatPercent(viewModel.lifetimeStats.wsdPercent)
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Sessions

    @ViewBuilder
    private var recentSessions: some View {
        if viewModel.recentSessions.isEmpty && viewModel.activeSession == nil {
            EmptyStateView(
                icon: "suit.spade.fill",
                title: "No Sessions Yet",
                message: "Start your first poker session to begin tracking your play.",
                actionTitle: "Start First Session"
            ) {
                selectedTab = 1
            }
        } else if !viewModel.recentSessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Sessions")
                        .font(.headline)
                    Spacer()
                    Button("See All") {
                        selectedTab = 2
                    }
                    .font(.subheadline)
                }

                ForEach(viewModel.recentSessions) { session in
                    Button {
                        navigationPath.append(session)
                    } label: {
                        SessionRowView(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
