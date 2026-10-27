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
    }

    private var actions: Actions?

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "BackupViewModel")

    // MARK: - Setup

    func configure(authService: AuthService, modelContext: ModelContext) {
        let backupService = BackupService(authService: authService, modelContext: modelContext)
        configure(Actions(
            isSignedIn: { authService.isAuthenticated },
            listBackups: { try await backupService.listBackups() },
            createBackup: { try await backupService.createAndUploadBackup() },
            downloadBackup: { try await backupService.downloadBackup(metadata: $0) },
            restoreBackup: { try backupService.restoreBackup($0) }
        ))
    }

    func configure(_ actions: Actions) {
        self.actions = actions
    }

    // MARK: - Load Backups

    func loadBackups() async {
        guard let actions, actions.isSignedIn() else {
            backups = []
            return
        }

        isLoadingBackups = true
        clearError()

        do {
            backups = try await actions.listBackups()
        } catch {
            show(error, action: .loadBackups, retry: .loadBackups)
        }

        isLoadingBackups = false
    }

    // MARK: - Create Backup

    func createBackup() async {
        guard let actions else { return }

        isBackingUp = true
        clearError()
        successMessage = nil

        do {
            let metadata = try await actions.createBackup()
            successMessage = "Backed up \(metadata.sessionCount) sessions, \(metadata.handCount) hands (\(metadata.formattedSize))"
            await loadBackups()
        } catch {
            show(error, action: .backup, retry: .backup)
        }

        isBackingUp = false
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

        do {
            let payload = try await actions.downloadBackup(backup)
            try actions.restoreBackup(payload)
            successMessage = "Restored \(payload.sessions.count) sessions from \(backup.formattedDate)"
        } catch {
            show(error, action: .restore, retry: .restore(backup))
        }

        isRestoring = false
        self.selectedBackup = nil
    }

    func backupThenRestore() async {
        guard let backup = selectedBackup else { return }
        await createBackup()
        guard errorMessage == nil else {
            // Try Again runs both steps again, not just the backup.
            if retryableAction != nil { retryableAction = .backupThenRestore(backup) }
            selectedBackup = nil
            return
        }
        await restore(backup)
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

    var lastBackupDate: String? {
        backups.first?.formattedDate
    }

    var canBackup: Bool {
        actions?.isSignedIn() == true && !isBackingUp && !isRestoring
    }
}
