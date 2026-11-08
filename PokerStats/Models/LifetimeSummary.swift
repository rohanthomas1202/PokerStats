import Foundation
import SwiftData

/// The lifetime widget's numbers: total profit, sessions played, hourly rate and
/// the current winning streak. Built into the app target as well as the widget,
/// so the shared stat fixture tests (#238) run the widget's own code.
struct LifetimeSummary {
    let totalProfit: Double
    let sessionsPlayed: Int
    let hourlyRate: Double?
    /// Consecutive winning sessions, newest first.
    let currentStreak: Int

    /// Reads every session in `context`, newest first.
    static func fetch(from context: ModelContext) -> LifetimeSummary {
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

        return LifetimeSummary(
            totalProfit: totalProfit,
            sessionsPlayed: completed.count,
            hourlyRate: hourlyRate,
            currentStreak: streak
        )
    }
}
