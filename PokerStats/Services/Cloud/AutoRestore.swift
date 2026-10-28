import Foundation
import SwiftData
import os

/// Restores the latest cloud backup after sign-in, but only into an empty
/// store and only once per device (see `AutoRestoreFlag`).
///
/// The flag is checked at the start and again right before applying, so a
/// wipe during the download is never undone.
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
        let clearCount = flag.clearCount
        let outcome = try await restoreIfEmpty(clearCount: clearCount)
        // Account deletion during the run cleared the flag for the next
        // sign-in; setting it again here would skip that restore (#68).
        guard flag.clearCount == clearCount else { return outcome }
        // Set for `.noBackups` too, permanently. Trade-off: signing in on a new
        // device before the old device's first backup has uploaded means no
        // auto-restore there later; manual restore in Settings > Cloud Backup
        // still works (#68).
        flag.set()
        return outcome
    }

    /// `clearCount` is the flag's count when the run started.
    private func restoreIfEmpty(clearCount: Int) async throws -> Outcome {
        let restorer = LocalDataRestorer(modelContext: modelContext)
        guard try restorer.isStoreEmpty() else { return .skippedLocalDataExists }

        guard let latest = try await listBackups().first else { return .noBackups }
        let payload = try await downloadBackup(latest)
        // Re-check after the download, with no suspension point before the
        // write: Delete All Data sets the flag, and account deletion clears it,
        // while the download runs. Either way the wipe wins (#68).
        guard !flag.isSet, flag.clearCount == clearCount else { return .skippedAlreadyRan }

        guard try restorer.restoreIfStoreEmpty(payload) else {
            Self.logger.notice("Auto-restore skipped: local data appeared during the backup download")
            return .skippedDataAppearedDuringDownload
        }
        return .restored(sessionCount: payload.sessions.count)
    }
}
