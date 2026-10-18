import Foundation
import SwiftData

/// Replaces all local SwiftData content with a backup payload.
///
/// The payload is validated before anything is touched, the delete and the
/// insert go out in a single save, and any error rolls the context back so
/// the store is left as it was before the restore started.
@MainActor
struct LocalDataRestorer {
    let modelContext: ModelContext

    /// Performs the one save that commits the restore. Tests replace it to
    /// inject a failure; production uses `ModelContext.save()`.
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func restore(_ payload: BackupPayload) throws {
        try Self.validate(payload)

        // Commit any unrelated pending edits first, so a rollback below only
        // discards the restore's own changes.
        if modelContext.hasChanges {
            try modelContext.save()
        }

        do {
            try deleteAllLocalData()
            insert(payload)
            try save(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Checks the payload before any local mutation.
    static func validate(_ payload: BackupPayload) throws {
        if payload.schemaVersion > BackupPayload.currentSchemaVersion {
            throw BackupError.schemaVersionTooNew(payload.schemaVersion)
        }
        let sessionIDs = payload.sessions.map(\.id)
        if Set(sessionIDs).count != sessionIDs.count {
            throw BackupError.restoreFailed("backup contains duplicate session IDs")
        }
        let handIDs = payload.sessions.flatMap { $0.hands.map(\.id) }
        if Set(handIDs).count != handIDs.count {
            throw BackupError.restoreFailed("backup contains duplicate hand IDs")
        }
    }

    // Marks every local object for deletion. Nothing is saved here.
    private func deleteAllLocalData() throws {
        for hand in try modelContext.fetch(FetchDescriptor<Hand>()) {
            modelContext.delete(hand)
        }
        for session in try modelContext.fetch(FetchDescriptor<Session>()) {
            modelContext.delete(session)
        }
        for settings in try modelContext.fetch(FetchDescriptor<Settings>()) {
            modelContext.delete(settings)
        }
    }

    private func insert(_ payload: BackupPayload) {
        for sessionDTO in payload.sessions {
            let session = Session.fromDTO(sessionDTO)
            modelContext.insert(session)

            for handDTO in sessionDTO.hands {
                let hand = Hand.fromDTO(handDTO)
                hand.session = session
                modelContext.insert(hand)
            }
        }

        if let settingsDTO = payload.settings {
            modelContext.insert(Settings.fromDTO(settingsDTO))
        }
    }
}
