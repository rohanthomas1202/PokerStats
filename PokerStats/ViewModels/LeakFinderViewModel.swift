import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class LeakFinderViewModel {
    var insights: [LeakInsight] = []
    var selectedProfile: ReferenceProfile = .sixMaxCash
    var totalHands: Int = 0

    var leakCount: Int {
        insights.filter { $0.rating == .leak }.count
    }

    var borderlineCount: Int {
        insights.filter { $0.rating == .borderline }.count
    }

    var overallRating: OverallRating {
        LeakFinder.overallRating(from: insights)
    }

    var hasEnoughData: Bool {
        totalHands >= LeakFinder.minimumHands
    }

    func loadData(from context: ModelContext) {
        let handsDescriptor = FetchDescriptor<Hand>()
        let allHands = (try? context.fetch(handsDescriptor)) ?? []

        let sessionsDescriptor = FetchDescriptor<Session>()
        let allSessions = (try? context.fetch(sessionsDescriptor)) ?? []

        let stats = StatCalculator.computeAll(hands: allHands, sessions: allSessions)
        totalHands = stats.totalHands

        if totalHands >= LeakFinder.minimumHands {
            insights = LeakFinder.analyze(stats: stats, profile: selectedProfile)
        } else {
            insights = []
        }
    }

    /// Analyze a single session's stats.
    static func sessionInsights(session: Session, profile: ReferenceProfile) -> [LeakInsight] {
        let stats = StatCalculator.computeSessionStats(session: session)
        guard stats.totalHands >= 10 else { return [] }
        return LeakFinder.analyze(stats: stats, profile: profile)
    }
}
