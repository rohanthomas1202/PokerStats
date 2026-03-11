import SwiftData
import SwiftUI
import WidgetKit

struct PokerStatsLifetimeWidget: Widget {
    let kind: String = "PokerStatsLifetimeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LifetimeProvider()) { entry in
            LifetimeWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Poker P&L")
        .description("Your lifetime poker profit/loss at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Entry

struct LifetimeEntry: TimelineEntry, Sendable {
    let date: Date
    let totalProfit: Double
    let sessionsPlayed: Int
    let hourlyRate: Double?
    let currentStreak: Int // consecutive winning sessions
}

// MARK: - Timeline Provider

struct LifetimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> LifetimeEntry {
        LifetimeEntry(date: .now, totalProfit: 1250, sessionsPlayed: 42, hourlyRate: 18.5, currentStreak: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (LifetimeEntry) -> Void) {
        Task { @MainActor in
            let entry = computeEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<LifetimeEntry>) -> Void) {
        Task { @MainActor in
            let entry = computeEntry()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    @MainActor
    private func computeEntry() -> LifetimeEntry {
        guard let container = try? AppGroupContainer.createSharedModelContainer() else {
            return LifetimeEntry(date: .now, totalProfit: 0, sessionsPlayed: 0, hourlyRate: nil, currentStreak: 0)
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\Session.startTime, order: .reverse)]
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        let completed = sessions.filter { $0.status == .completed }

        let totalProfit = completed.reduce(0.0) { $0 + $1.netProfit }
        let totalHours = completed.reduce(0.0) { $0 + $1.durationHours }
        let hourlyRate = totalHours > 0.01 ? totalProfit / totalHours : nil

        // Calculate current winning streak
        var streak = 0
        for session in completed {
            if session.netProfit > 0 {
                streak += 1
            } else {
                break
            }
        }

        return LifetimeEntry(
            date: .now,
            totalProfit: totalProfit,
            sessionsPlayed: completed.count,
            hourlyRate: hourlyRate,
            currentStreak: streak
        )
    }
}

// MARK: - Widget Views

struct LifetimeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LifetimeEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "suit.spade.fill")
                    .foregroundStyle(.green)
                Text("PokerStats")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Text(formatCurrency(entry.totalProfit))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(entry.totalProfit >= 0 ? .green : .red)
                .minimumScaleFactor(0.6)

            Text("\(entry.sessionsPlayed) sessions")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    }

    private var mediumView: some View {
        HStack {
            // Left side: P&L
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "suit.spade.fill")
                        .foregroundStyle(.green)
                    Text("PokerStats")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Text(formatCurrency(entry.totalProfit))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(entry.totalProfit >= 0 ? .green : .red)
                    .minimumScaleFactor(0.6)

                Text("Lifetime P&L")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Right side: stats
            VStack(alignment: .trailing, spacing: 12) {
                Spacer()

                statRow(label: "Sessions", value: "\(entry.sessionsPlayed)")

                if let hourly = entry.hourlyRate {
                    statRow(label: "$/hr", value: formatCurrency(hourly))
                }

                if entry.currentStreak > 0 {
                    statRow(label: "Streak", value: "\(entry.currentStreak)W")
                }
            }
        }
        .padding(4)
    }

    private func statRow(label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        let prefix = value < 0 ? "-" : "+"
        if absValue >= 1000 {
            return "\(prefix)$\(Int(absValue).formatted())"
        }
        return "\(prefix)$\(Int(absValue))"
    }
}
