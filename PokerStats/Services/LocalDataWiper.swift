import Foundation
import SwiftData
import ActivityKit

/// Removes every local SwiftData model (hands, sessions, settings) in one
/// save. Used by Delete All Data, after the server confirms account
/// deletion, and by "Delete from This iPhone". On error the context is
/// rolled back, so nothing is half-deleted.
@MainActor
struct LocalDataWiper {
    let modelContext: ModelContext

    /// Performs the one save. Tests replace it to inject a failure.
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func wipe() throws {
        do {
            for hand in try modelContext.fetch(FetchDescriptor<Hand>()) {
                modelContext.delete(hand)
            }
            for session in try modelContext.fetch(FetchDescriptor<Session>()) {
                modelContext.delete(session)
            }
            for settings in try modelContext.fetch(FetchDescriptor<Settings>()) {
                modelContext.delete(settings)
            }
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Ends every running Live Activity right away. Callers run it after a
    /// wipe so the Lock Screen doesn't show a deleted session (#269).
    static func endLiveActivities() {
        Task {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
