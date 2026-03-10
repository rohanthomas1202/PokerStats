import Foundation
import SwiftData
import Observation

enum TimeFilter: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case sixMonths = "6mo"

    var id: String { rawValue }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .allTime: return nil
        case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: .now)
        case .ninetyDays: return calendar.date(byAdding: .day, value: -90, to: .now)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)
        }
    }
}

@Observable
@MainActor
final class TrendsViewModel {
    var selectedTimeFilter: TimeFilter = .allTime
    var bankrollData: [TrendCalculator.BankrollDataPoint] = []
    var rollingStats: [TrendCalculator.RollingStatPoint] = []
    var dayOfWeekData: [TrendCalculator.DayOfWeekProfit] = []
    var plDistribution: [TrendCalculator.PLBucket] = []
    var sessionCount: Int = 0

    func loadData(from context: ModelContext) {
        let allDescriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        let sessions = (try? context.fetch(allDescriptor)) ?? []

        let allHandsDescriptor = FetchDescriptor<Hand>()
        let allHands = (try? context.fetch(allHandsDescriptor)) ?? []

        // Apply time filter
        let filteredSessions: [Session]
        let filteredHands: [Hand]

        if let cutoff = selectedTimeFilter.cutoffDate {
            filteredSessions = sessions.filter { $0.startTime >= cutoff }
            filteredHands = allHands.filter { $0.timestamp >= cutoff }
        } else {
            filteredSessions = sessions
            filteredHands = allHands
        }

        let completedSessions = filteredSessions.filter { $0.status == .completed }
        sessionCount = completedSessions.count

        bankrollData = TrendCalculator.cumulativeBankroll(sessions: filteredSessions)
        rollingStats = TrendCalculator.rollingVPIPPFR(hands: filteredHands)
        dayOfWeekData = TrendCalculator.profitByDayOfWeek(sessions: filteredSessions)
        plDistribution = TrendCalculator.sessionPLDistribution(sessions: filteredSessions)
    }
}
