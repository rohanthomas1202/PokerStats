import Foundation
import SwiftData
import os

/// Restores the latest cloud backup after sign-in, but only into an empty store.
///
/// The download is the slow part, and the user can start a session while it
/// runs. Emptiness is checked before the download (to skip the network work)
/// and again right before applying the backup, on the same context and actor
/// as the restore, so data created mid-download is never deleted.
@MainActor
struct AutoRestore {
    enum Outcome: Equatable {
        case restored(sessionCount: Int)
        case noBackups
        /// Local data existed before the download started.
        case skippedLocalDataExists
        /// Local data appeared while the backup was downloading.
        case skippedDataAppearedDuringDownload
    }

    let modelContext: ModelContext
    let listBackups: @MainActor () async throws -> [BackupMetadata]
    let downloadBackup: @MainActor (BackupMetadata) async throws -> BackupPayload

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AutoRestore")

    func run() async throws -> Outcome {
        let restorer = LocalDataRestorer(modelContext: modelContext)
        guard try restorer.isStoreEmpty() else { return .skippedLocalDataExists }

        guard let latest = try await listBackups().first else { return .noBackups }
        let payload = try await downloadBackup(latest)

        guard try restorer.restoreIfStoreEmpty(payload) else {
            Self.logger.notice("Auto-restore skipped: local data appeared during the backup download")
            return .skippedDataAppearedDuringDownload
        }
        return .restored(sessionCount: payload.sessions.count)
    }
}
