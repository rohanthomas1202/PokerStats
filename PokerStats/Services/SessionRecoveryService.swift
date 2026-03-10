import Foundation
import SwiftData

/// Handles recovery of active sessions after app termination.
/// On launch, checks for any session with status == .active and resumes it.
enum SessionRecoveryService {

    /// Returns the active session if one exists, nil otherwise.
    @MainActor
    static func recoverActiveSession(from context: ModelContext) -> Session? {
        let active = SessionStatus.active.rawValue
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.statusRaw == active },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    /// Check if a session has been active for an unusually long time (>12 hours).
    static func isSessionStale(_ session: Session) -> Bool {
        session.duration > 12 * 3600
    }
}
