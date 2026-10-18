import Foundation
import SwiftData
import os

/// Restores the latest cloud backup after sign-in, but only into an empty
/// store and only once per device (see `AutoRestoreFlag`).
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
        /// Auto-restore already ran on this device, or the user deleted local data.
        case skippedAlreadyRan
    }

    let modelContext: ModelContext
    let listBackups: @MainActor () async throws -> [BackupMetadata]
    let downloadBackup: @MainActor (BackupMetadata) async throws -> BackupPayload
    let flag: AutoRestoreFlag

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "AutoRestore")

    /// Sets the flag once it has a definite outcome. An error leaves it unset,
    /// so the next launch tries again.
    func run() async throws -> Outcome {
        guard !flag.isSet else { return .skippedAlreadyRan }
        let outcome = try await restoreIfEmpty()
        flag.set()
        return outcome
    }

    private func restoreIfEmpty() async throws -> Outcome {
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
