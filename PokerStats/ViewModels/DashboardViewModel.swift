import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class DashboardViewModel {
    var lifetimeStats: ComputedStats = .empty
    var recentSessions: [Session] = []
    var activeSession: Session?
    var mentalCorrelation: [TrendCalculator.MentalCorrelationPoint] = []
    var leakInsights: [LeakInsight] = []

    var playStyle: PlayStyle? {
        PlayStyle.classify(vpip: lifetimeStats.vpip, pfr: lifetimeStats.pfr)
    }

    var foldPercent: Double? {
        guard lifetimeStats.totalHands > 0 else { return nil }
        return Double(lifetimeStats.handsFolded) / Double(lifetimeStats.totalHands)
    }

    func loadData(from context: ModelContext) {
        // Fetch all sessions
        let allDescriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let sessions = (try? context.fetch(allDescriptor)) ?? []

        // Active session
        activeSession = sessions.first { $0.isActive }

        // Recent completed sessions (last 5)
        recentSessions = sessions
            .filter { $0.status == .completed }
            .prefix(5)
            .map { $0 }

        // All hands across all sessions
        let allHandsDescriptor = FetchDescriptor<Hand>()
        let allHands = (try? context.fetch(allHandsDescriptor)) ?? []

        // Compute lifetime stats
        lifetimeStats = StatCalculator.computeAll(
            hands: allHands,
            sessions: sessions
        )

        // Compute mental correlation
        mentalCorrelation = TrendCalculator.mentalCorrelation(sessions: sessions)

        // Compute leak insights
        if lifetimeStats.totalHands >= LeakFinder.minimumHands {
            leakInsights = LeakFinder.analyze(stats: lifetimeStats, profile: .sixMaxCash)
        } else {
            leakInsights = []
        }
    }

    var leakCount: Int {
        leakInsights.filter { $0.rating == .leak }.count
    }

    var overallLeakRating: OverallRating {
        LeakFinder.overallRating(from: leakInsights)
    }

    /// Best and worst tilt correlation insight (if enough data)
    var mentalInsight: (calmRate: Double, tiltedRate: Double)? {
        let tiltPoints = mentalCorrelation.filter { $0.metricType == .tilt }
        guard let calm = tiltPoints.first(where: { $0.level == 1 }),
              let tilted = tiltPoints.first(where: { $0.level >= 4 }),
              calm.sessionCount >= 2, tilted.sessionCount >= 2 else { return nil }
        return (calmRate: calm.averageHourlyRate, tiltedRate: tilted.averageHourlyRate)
    }
}
