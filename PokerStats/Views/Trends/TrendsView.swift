import SwiftUI
import SwiftData
import Charts
import UIKit

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TrendsViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var plPlotWidth: Double = 0

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
                .foregroundStyle(Color.pokerResult(day.totalProfit))
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
        let axisLayout = plAxisLayout
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Session P&L Distribution")
                    .font(.headline)
                if let subtitle = TrendCalculator.plDistributionSubtitle(viewModel.plDistribution) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.pokerTextSecondary)
                }
            }

            Chart(viewModel.plDistribution) { bucket in
                BarMark(
                    x: .value("Range", bucket.rangeLabel),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(bucket.lowerBound >= 0 ? Color.pokerProfit : Color.pokerLoss)
                .cornerRadius(4)
                .accessibilityLabel(Text(bucket.accessibilityLabel))
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
                if TrendCalculator.plAxisThinsLabels(at: dynamicTypeSize) {
                    AxisMarks(values: axisLayout.indices.map { viewModel.plDistribution[$0].rangeLabel }) { value in
                        AxisValueLabel(anchor: Self.anchor(axisLayout.alignment(at: value.index, of: value.count))) {
                            if let v = value.as(String.self) {
                                Text(v)
                                    .font(.caption2)
                                    .foregroundStyle(Color.pokerTextSecondary)
                            }
                        }
                    }
                } else {
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
            }
            .chartPlotStyle { plot in
                plot.onGeometryChange(for: Double.self) { Double($0.size.width) } action: { plPlotWidth = $0 }
            }
            .frame(height: 200)
        }
        .padding()
        .pokerCard(cornerRadius: 16)
    }

    /// Which bars get an x-axis label at the current plot width, text size and Bold Text setting.
    private var plAxisLayout: TrendCalculator.PLAxisLayout {
        TrendCalculator.plAxisLayout(
            bucketCount: viewModel.plDistribution.count,
            plotWidth: plPlotWidth,
            labelWidth: TrendCalculator.plAxisLabelWidth(
                viewModel.plDistribution.map(\.rangeLabel),
                at: dynamicTypeSize,
                legibilityWeight: legibilityWeight
            )
        )
    }

    private static func anchor(_ alignment: TrendCalculator.PLAxisLayout.Alignment) -> UnitPoint? {
        switch alignment {
        case .leading: .topLeading
        case .center: nil
        case .trailing: .topTrailing
        }
    }
}

extension TrendCalculator {
    /// Whether the P&L x-axis shows only the labels that fit. At default sizes
    /// (Large and below) the axis is left to Swift Charts as before; above that,
    /// `plAxisLayout` picks labels by measured width so they don't overlap or clip.
    static func plAxisThinsLabels(at size: DynamicTypeSize) -> Bool {
        size > .large
    }

    /// Width in points, rounded up, of the widest label in caption2 at `size`,
    /// in bold when Bold Text is on, as the axis draws it. 0 with no labels.
    @MainActor
    static func plAxisLabelWidth(_ labels: [String], at size: DynamicTypeSize, legibilityWeight: LegibilityWeight?) -> Double {
        let traits = UITraitCollection { traits in
            traits.preferredContentSizeCategory = UIContentSizeCategory(size)
            traits.legibilityWeight = legibilityWeight == .bold ? .bold : .regular
        }
        let font = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits)
        let widest = labels
            .map { Double(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        return widest.rounded(.up)
    }
}
