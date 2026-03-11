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
                    // Custom header
                    HStack {
                        Text("PokerStats")
                            .font(.system(.largeTitle, design: .default))
                            .fontWeight(.bold)
                        Spacer()
                        NavigationLink(value: "settings") {
                            Image(systemName: "gearshape")
                                .font(.title2)
                                .foregroundStyle(Color.pokerTextSecondary)
                                .frame(width: 44, height: 44)
                                .background(Color.pokerCard, in: Circle())
                        }
                    }

                    // Active session banner
                    if let activeSession = viewModel.activeSession {
                        activeSessionBanner(activeSession)
                    }

                    // Play Style section
                    playStyleSection

                    // Financial summary
                    financialSummary

                    // Core stats 2-column grid
                    coreStatsGrid

                    // Secondary stats row
                    secondaryStatsRow

                    // Fold Frequency gauges
                    foldFrequencySection

                    // Mental insights
                    if viewModel.mentalInsight != nil {
                        mentalInsightsCard
                    }

                    // Leak Finder card
                    if viewModel.lifetimeStats.totalHands >= LeakFinder.minimumHands {
                        leakFinderCard
                    }

                    // Recent sessions
                    recentSessions
                }
                .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.pokerBackground)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(session: session)
            }
            .navigationDestination(for: String.self) { route in
                if route == "settings" {
                    SettingsView()
                } else if route == "leakFinder" {
                    LeakFinderView()
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
                    .fill(Color.pokerProfit)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .fill(Color.pokerProfit.opacity(0.4))
                            .frame(width: 20, height: 20)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Session Active")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(session.stakes) \(session.gameType.displayName)")
                        .font(.caption)
                        .foregroundStyle(Color.pokerTextSecondary)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(DurationFormatter.formatTimer(session.duration))
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.medium)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.pokerTextSecondary)
            }
            .padding()
            .background(Color.pokerProfit.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Play Style Section

    private var playStyleSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Playing Tendencies")
                    .font(.headline)
                PlayStyleLabelView(style: viewModel.playStyle)
                Spacer()
            }

            PlayStyleChartView(
                vpip: viewModel.lifetimeStats.vpip,
                pfr: viewModel.lifetimeStats.pfr
            )
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }

    // MARK: - Financial Summary

    private var financialSummary: some View {
        VStack(spacing: 12) {
            // Total P/L
            Text(ComputedStats.formatCurrency(viewModel.lifetimeStats.totalProfit))
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(viewModel.lifetimeStats.totalProfit >= 0 ? Color.pokerProfit : Color.pokerLoss)

            Text("Total Profit/Loss")
                .font(.caption)
                .foregroundStyle(Color.pokerTextSecondary)

            // Sub-metrics 3-col
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
        .pokerCard(cornerRadius: 16)
    }

    // MARK: - Core Stats 2-Column Grid

    private var coreStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCardView(
                title: "VPIP",
                value: ComputedStats.formatPercent(viewModel.lifetimeStats.vpip),
                statDef: .vpip,
                rangeValue: viewModel.lifetimeStats.vpip,
                rangeGoodRange: StatDefinition.vpip.goodRange
            )
            StatCardView(
                title: "PFR",
                value: ComputedStats.formatPercent(viewModel.lifetimeStats.pfr),
                statDef: .pfr,
                rangeValue: viewModel.lifetimeStats.pfr,
                rangeGoodRange: StatDefinition.pfr.goodRange
            )
            StatCardView(
                title: "C-Bet",
                value: ComputedStats.formatPercent(viewModel.lifetimeStats.cBetPercent),
                statDef: .cBet,
                rangeValue: viewModel.lifetimeStats.cBetPercent,
                rangeGoodRange: StatDefinition.cBet.goodRange
            )
            StatCardView(
                title: "WTSD",
                value: ComputedStats.formatPercent(viewModel.lifetimeStats.wtsdPercent),
                statDef: .wtsd,
                rangeValue: viewModel.lifetimeStats.wtsdPercent,
                rangeGoodRange: StatDefinition.wtsd.goodRange
            )
        }
    }

    // MARK: - Secondary Stats Row

    private var secondaryStatsRow: some View {
        HStack(spacing: 8) {
            StatCardView(
                title: "Fold to 3B",
                value: ComputedStats.formatPercent(viewModel.lifetimeStats.foldTo3BetPercent),
                statDef: .foldTo3Bet
            )
            StatCardView(
                title: "W$SD",
                value: ComputedStats.formatPercent(viewModel.lifetimeStats.wsdPercent),
                statDef: .wsd
            )
            StatCardView(
                title: "Hands",
                value: "\(viewModel.lifetimeStats.totalHands)"
            )
        }
    }

    // MARK: - Fold Frequency Section

    private var foldFrequencySection: some View {
        VStack(spacing: 12) {
            Text("Fold Frequency")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                CircularGaugeView(
                    title: "Preflop Fold",
                    value: viewModel.foldPercent,
                    emoji: "🃏",
                    gradientColors: [.pokerProfit, .cyan]
                )

                CircularGaugeView(
                    title: "Fold to 3-Bet",
                    value: viewModel.lifetimeStats.foldTo3BetPercent,
                    emoji: "🛡️",
                    gradientColors: [.orange, .pokerLoss]
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }

    // MARK: - Mental Insights Card

    @ViewBuilder
    private var mentalInsightsCard: some View {
        if let insight = viewModel.mentalInsight {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.purple)
                    Text("Mental Insights")
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.green)
                        Text("Calm")
                            .font(.caption2)
                            .foregroundStyle(Color.pokerTextSecondary)
                        Text(ComputedStats.formatHourlyRate(insight.calmRate))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(insight.calmRate >= 0 ? Color.pokerProfit : Color.pokerLoss)
                        Text("/hr")
                            .font(.caption2)
                            .foregroundStyle(Color.pokerTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .pokerCard()

                    Text("vs")
                        .font(.caption)
                        .foregroundStyle(Color.pokerTextSecondary)

                    VStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.red)
                        Text("Tilted")
                            .font(.caption2)
                            .foregroundStyle(Color.pokerTextSecondary)
                        Text(ComputedStats.formatHourlyRate(insight.tiltedRate))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(insight.tiltedRate >= 0 ? Color.pokerProfit : Color.pokerLoss)
                        Text("/hr")
                            .font(.caption2)
                            .foregroundStyle(Color.pokerTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .pokerCard()
                }
            }
            .padding()
            .pokerCard(cornerRadius: 16)
        }
    }

    // MARK: - Leak Finder Card

    private var leakFinderCard: some View {
        NavigationLink(value: "leakFinder") {
            HStack(spacing: 12) {
                Circle()
                    .fill(leakRatingColor)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "stethoscope")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Leak Finder")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(leakSummaryText)
                        .font(.caption)
                        .foregroundStyle(Color.pokerTextSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.pokerTextSecondary)
            }
            .padding()
            .pokerCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private var leakRatingColor: Color {
        switch viewModel.overallLeakRating {
        case .solid: .pokerProfit
        case .needsWork: .yellow
        case .leaking: .pokerLoss
        }
    }

    private var leakSummaryText: String {
        let leaks = viewModel.leakCount
        if leaks == 0 {
            return "Looking solid — no major leaks detected"
        } else {
            return "\(leaks) leak\(leaks == 1 ? "" : "s") found — tap to review"
        }
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
                        selectedTab = 3
                    }
                    .font(.subheadline)
                }

                ForEach(viewModel.recentSessions) { session in
                    Button {
                        navigationPath.append(session)
                    } label: {
                        SessionRowView(session: session)
                            .padding()
                            .pokerCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
