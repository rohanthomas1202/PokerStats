import Foundation
import SwiftData

/// Removes every local SwiftData model (hands, sessions, settings) in one
/// save. Used after the server confirms account deletion. On error the
/// context is rolled back, so nothing is half-deleted.
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
}
