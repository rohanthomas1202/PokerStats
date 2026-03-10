import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class DashboardViewModel {
    var lifetimeStats: ComputedStats = .empty
    var recentSessions: [Session] = []
    var activeSession: Session?

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
    }
}
