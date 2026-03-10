import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TrendsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Time filter
                    Picker("Time Period", selection: $viewModel.selectedTimeFilter) {
                        ForEach(TimeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.sessionCount < 2 {
                        EmptyStateView(
                            icon: "chart.xyaxis.line",
                            title: "Not Enough Data",
                            message: "Complete at least 2 sessions to see your trends."
                        )
                    } else {
                        // Cumulative Bankroll
                        bankrollChart

                        // VPIP/PFR Trends
                        if !viewModel.rollingStats.isEmpty {
                            vpipPfrChart
                        }

                        // Profit by Day of Week
                        dayOfWeekChart

                        // P&L Distribution
                        if !viewModel.plDistribution.isEmpty {
                            plDistributionChart
                        }
                    }
                }
                .padding()
            }
            .background(Color.pokerBackground)
            .navigationTitle("Trends")
            .onAppear {
                viewModel.loadData(from: modelContext)
            }
            .onChange(of: viewModel.selectedTimeFilter) { _, _ in
                viewModel.loadData(from: modelContext)
            }
        }
    }

    // MARK: - Bankroll Chart

    private var bankrollChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cumulative Bankroll")
                .font(.headline)

            Chart(viewModel.bankrollData) { point in
                LineMark(
                    x: .value("Session", point.sessionIndex),
                    y: .value("Profit", point.cumulativeProfit)
                )
                .foregroundStyle(Color.pokerAccent)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Session", point.sessionIndex),
                    y: .value("Profit", point.cumulativeProfit)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pokerAccent.opacity(0.3), Color.pokerAccent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.pokerTextTertiary)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("$\(Int(v))")
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("#\(v)")
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }

    // MARK: - VPIP/PFR Chart

    private var vpipPfrChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VPIP / PFR Trend")
                .font(.headline)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(Color.pokerAccent).frame(width: 8, height: 8)
                    Text("VPIP").font(.caption).foregroundStyle(Color.pokerTextSecondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("PFR").font(.caption).foregroundStyle(Color.pokerTextSecondary)
                }
            }

            Chart {
                ForEach(viewModel.rollingStats) { point in
                    LineMark(
                        x: .value("Hand", point.handIndex),
                        y: .value("VPIP", point.vpip * 100),
                        series: .value("Stat", "VPIP")
                    )
                    .foregroundStyle(Color.pokerAccent)
                    .interpolationMethod(.catmullRom)
                }

                ForEach(viewModel.rollingStats) { point in
                    LineMark(
                        x: .value("Hand", point.handIndex),
                        y: .value("PFR", point.pfr * 100),
                        series: .value("Stat", "PFR")
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.pokerTextTertiary)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%")
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("#\(v)")
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }

    // MARK: - Day of Week Chart

    private var dayOfWeekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profit by Day of Week")
                .font(.headline)

            Chart(viewModel.dayOfWeekData) { day in
                BarMark(
                    x: .value("Day", day.dayName),
                    y: .value("Profit", day.totalProfit)
                )
                .foregroundStyle(day.totalProfit >= 0 ? Color.pokerProfit : Color.pokerLoss)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.pokerTextTertiary)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("$\(Int(v))")
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(String.self) {
                            Text(v)
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }

    // MARK: - P&L Distribution Chart

    private var plDistributionChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session P&L Distribution")
                .font(.headline)

            Chart(viewModel.plDistribution) { bucket in
                BarMark(
                    x: .value("Range", bucket.rangeLabel),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(bucket.lowerBound >= 0 ? Color.pokerProfit : Color.pokerLoss)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.pokerTextTertiary)
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(String.self) {
                            Text(v)
                                .font(.caption2)
                                .foregroundStyle(Color.pokerTextSecondary)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }
}
