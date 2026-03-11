import Foundation
import SwiftData

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

    private var backupService: BackupService?
    private var authService: AuthService?

    // MARK: - Setup

    func configure(authService: AuthService, modelContext: ModelContext) {
        self.authService = authService
        self.backupService = BackupService(authService: authService, modelContext: modelContext)
    }

    // MARK: - Load Backups

    func loadBackups() async {
        guard authService?.isAuthenticated == true else {
            backups = []
            return
        }

        isLoadingBackups = true
        errorMessage = nil

        do {
            backups = try await backupService?.listBackups() ?? []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingBackups = false
    }

    // MARK: - Create Backup

    func createBackup() async {
        guard let backupService else { return }

        isBackingUp = true
        errorMessage = nil
        successMessage = nil

        do {
            let metadata = try await backupService.createAndUploadBackup()
            successMessage = "Backed up \(metadata.sessionCount) sessions, \(metadata.handCount) hands (\(metadata.formattedSize))"
            await loadBackups()
        } catch {
            errorMessage = error.localizedDescription
        }

        isBackingUp = false
    }

    // MARK: - Restore

    func initiateRestore(backup: BackupMetadata) {
        selectedBackup = backup
        isShowingRestoreConfirmation = true
    }

    func confirmRestore() async {
        guard let backupService, let selectedBackup else { return }

        isRestoring = true
        errorMessage = nil
        successMessage = nil

        do {
            let payload = try await backupService.downloadBackup(metadata: selectedBackup)
            try backupService.restoreBackup(payload)
            successMessage = "Restored \(payload.sessions.count) sessions from \(selectedBackup.formattedDate)"
        } catch {
            errorMessage = error.localizedDescription
        }

        isRestoring = false
        self.selectedBackup = nil
    }

    func backupThenRestore() async {
        await createBackup()
        guard errorMessage == nil else { return }
        await confirmRestore()
    }

    // MARK: - Computed

    var lastBackupDate: String? {
        backups.first?.formattedDate
    }

    var canBackup: Bool {
        authService?.isAuthenticated == true && !isBackingUp && !isRestoring
    }
}
