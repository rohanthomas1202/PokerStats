import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class SessionListViewModel {
    var searchText: String = ""

    func filteredSessions(_ sessions: [Session]) -> [Session] {
        if searchText.isEmpty {
            return sessions
        }
        let query = searchText.lowercased()
        return sessions.filter { session in
            session.location.lowercased().contains(query) ||
            session.stakes.lowercased().contains(query) ||
            session.gameType.displayName.lowercased().contains(query)
        }
    }

    func groupedByMonth(_ sessions: [Session]) -> [(String, [Session])] {
        let grouped = Dictionary(grouping: sessions) { session in
            DateFormatting.formatMonthYear(session.startTime)
        }
        return grouped
            .sorted { lhs, rhs in
                // Sort by the first session's date in each group (most recent first)
                guard let lDate = lhs.value.first?.startTime,
                      let rDate = rhs.value.first?.startTime else { return false }
                return lDate > rDate
            }
    }

    func aggregateStats(_ sessions: [Session]) -> (sessions: Int, profit: Double, hours: Double) {
        let completed = sessions.filter { $0.status == .completed }
        let profit = completed.reduce(0.0) { $0 + $1.netProfit }
        let hours = completed.reduce(0.0) { $0 + $1.durationHours }
        return (completed.count, profit, hours)
    }
}
