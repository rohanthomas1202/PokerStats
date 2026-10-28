import Foundation
import SwiftData
import os

@Observable
@MainActor
final class BackupViewModel {
    // MARK: - State

    var backups: [BackupMetadata] = []
    var isBackingUp = false
    var isRestoring = false
    var isLoadingBackups = false
    var errorMessage: String?
    var successMessage: String?

    // Restore flow
    var selectedBackup: BackupMetadata?
    var isShowingRestoreConfirmation = false
    var isShowingBackupBeforeRestore = false

    /// What Try Again re-runs; nil when there's nothing to retry.
    private(set) var retryableAction: RetryableAction?

    /// A manual backup or restore that account deletion stopped (#268).
    /// Stored outside this view model (on `AuthService` in the app), so a
    /// Cloud Backup screen opened after the deletion still sees it.
    var stoppedAction: StoppedAction? { actions?.stoppedWork() }

    typealias StoppedAction = StoppedCloudWork

    /// The backup list didn't reload after Back Up First, Then Restore, and
    /// the restore failed too; a restore that then succeeds reloads it.
    private var needsReloadAfterRestore = false

    static let backupStoppedMessage = "Backup stopped. Tap Back Up Now to try again."
    static let restoreStoppedMessage = "Restore stopped. Choose a backup to try again."

    enum RetryableAction {
        case loadBackups
        case backup
        case restore(BackupMetadata)
        case backupThenRestore(BackupMetadata)
    }

    /// The cloud calls; tests replace them.
    struct Actions {
        var isSignedIn: @MainActor () -> Bool
        var listBackups: @MainActor () async throws -> [BackupMetadata]
        var createBackup: @MainActor () async throws -> BackupMetadata
        var downloadBackup: @MainActor (BackupMetadata) async throws -> BackupPayload
        var restoreBackup: @MainActor (BackupPayload) throws -> Void
        var isCloudWorkSuspended: @MainActor () -> Bool = { false }
        var stoppedWork: @MainActor () -> StoppedAction? = { nil }
        var setStoppedWork: @MainActor (StoppedAction?) -> Void = { _ in }
    }

    private var actions: Actions?

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "BackupViewModel")

    // MARK: - Setup

    func configure(authService: AuthService, modelContext: ModelContext) {
        let backupService = BackupService(authService: authService, modelContext: modelContext)
        configure(Actions(
            isSignedIn: { authService.isAuthenticated },
            listBackups: { try await backupService.listBackups() },
            // Through AuthService, so account deletion stops them and waits (#61).
            createBackup: { try await authService.performCloudWork { try await backupService.createAndUploadBackup() } },
            downloadBackup: { backup in
                try await authService.performCloudWork { try await backupService.downloadBackup(metadata: backup) }
            },
            restoreBackup: { try backupService.restoreBackup($0) },
            isCloudWorkSuspended: { authService.isCloudWorkSuspended },
            stoppedWork: { authService.stoppedCloudWork },
            setStoppedWork: { authService.setStoppedCloudWork($0) }
        ))
    }

    func configure(_ actions: Actions) {
        self.actions = actions
    }

    // MARK: - Load Backups

    func loadBackups() async {
        guard let actions, actions.isSignedIn() else {
            backups = []
            actions?.setStoppedWork(nil)
            return
        }

        isLoadingBackups = true
        clearError()

        do {
            backups = try await actions.listBackups()
            needsReloadAfterRestore = false
        } catch {
            show(error, action: .loadBackups, retry: .loadBackups)
        }

        isLoadingBackups = false
    }

    // MARK: - Create Backup

    func createBackup() async {
        await runBackup()
    }

    /// Returns true when the backup finished.
    @discardableResult
    private func runBackup() async -> Bool {
        guard let actions else { return false }

        isBackingUp = true
        clearError()
        successMessage = nil
        needsReloadAfterRestore = false
        actions.setStoppedWork(nil)
        defer { isBackingUp = false }

        do {
            let metadata = try await actions.createBackup()
            successMessage = "Backed up \(metadata.sessionCount) sessions, \(metadata.handCount) hands (\(metadata.formattedSize))"
            await loadBackups()
            return true
        } catch is CancellationError {
            // Stopped by account deletion (#61). `stoppedNote` says so only
            // if the deletion doesn't complete (#268).
            actions.setStoppedWork(.backup)
            return false
        } catch {
            show(error, action: .backup, retry: .backup)
            return false
        }
    }

    // MARK: - Restore

    func initiateRestore(backup: BackupMetadata) {
        selectedBackup = backup
        isShowingRestoreConfirmation = true
    }

    func confirmRestore() async {
        guard let selectedBackup else { return }
        await restore(selectedBackup)
    }

    private func restore(_ backup: BackupMetadata) async {
        guard let actions else { return }

        isRestoring = true
        clearError()
        successMessage = nil
        actions.setStoppedWork(nil)

        do {
            let payload = try await actions.downloadBackup(backup)
            try actions.restoreBackup(payload)
            successMessage = "Restored \(payload.sessions.count) sessions from \(backup.formattedDate)"
        } catch is CancellationError {
            // Stopped by account deletion (#61): nothing was written. `stoppedNote`
            // says so only if the deletion doesn't complete (#268).
            actions.setStoppedWork(.restore)
        } catch {
            show(error, action: .restore, retry: .restore(backup))
        }

        isRestoring = false
        self.selectedBackup = nil
    }

    func backupThenRestore() async {
        guard let backup = selectedBackup else { return }
        guard await runBackup() else {
            // Try Again runs both steps again, not just the backup.
            if retryableAction != nil { retryableAction = .backupThenRestore(backup) }
            // The restore the user asked for didn't happen either.
            if stoppedAction != nil { actions?.setStoppedWork(.restore) }
            selectedBackup = nil
            return
        }
        // The backup finished, so the restore goes ahead even if reloading
        // the list failed. That error stays up, and its Try Again reloads the
        // list instead of uploading again (#275, #260).
        let reloadError = errorMessage
        let reloadRetry = retryableAction
        await restore(backup)
        guard let reloadError else { return }
        if errorMessage == nil, stoppedAction == nil {
            errorMessage = reloadError
            retryableAction = reloadRetry
        } else if errorMessage != nil {
            // The restore's error is up instead; its Try Again reloads the list too.
            needsReloadAfterRestore = true
        }
    }

    // MARK: - Retry

    var canRetry: Bool {
        retryableAction != nil && !isBackingUp && !isRestoring && !isLoadingBackups
    }

    /// Try Again: re-runs the action that failed.
    func retry() async {
        guard canRetry, let action = retryableAction else { return }
        switch action {
        case .loadBackups:
            await loadBackups()
        case .backup:
            await createBackup()
        case .restore(let backup):
            await restore(backup)
            if needsReloadAfterRestore, errorMessage == nil, stoppedAction == nil {
                await loadBackups()
            }
        case .backupThenRestore(let backup):
            selectedBackup = backup
            await backupThenRestore()
        }
    }

    // MARK: - Errors

    private func clearError() {
        errorMessage = nil
        retryableAction = nil
    }

    /// Plain copy for the user; the raw error goes to the log only.
    private func show(_ error: Error, action: UserFacingError.Action, retry: RetryableAction) {
        UserFacingError.log(error, action: action, to: Self.logger)
        let userFacing = UserFacingError(error)
        errorMessage = userFacing.message(for: action, isSignedIn: actions?.isSignedIn() ?? false)
        retryableAction = userFacing.isRetryable ? retry : nil
    }

    // MARK: - Computed

    /// A neutral note for a backup or restore that account deletion stopped.
    /// Hidden while the deletion runs and after it signs the user out; shown
    /// when the deletion failed or was cancelled (#268).
    var stoppedNote: String? {
        guard let stoppedAction, let actions, actions.isSignedIn(), !actions.isCloudWorkSuspended() else {
            return nil
        }
        switch stoppedAction {
        case .backup: return Self.backupStoppedMessage
        case .restore: return Self.restoreStoppedMessage
        }
    }

    var lastBackupDate: String? {
        backups.first?.formattedDate
    }

    var canBackup: Bool {
        actions?.isSignedIn() == true && !isBackingUp && !isRestoring
    }
}
