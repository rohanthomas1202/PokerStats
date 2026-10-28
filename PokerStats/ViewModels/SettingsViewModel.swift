import Foundation
import SwiftData
import Observation
import WidgetKit
import ActivityKit
import os

@Observable
@MainActor
final class SettingsViewModel {
    var defaultBuyIn: String = "200"
    var defaultStakes: String = "1/2"
    var defaultGameType: GameType = .cash
    var showDeleteAllConfirmation = false
    var showDeleteAllSecondConfirmation = false
    /// Shown when Delete All Data failed; nil otherwise (#263).
    var deleteAllDataFailure: String?

    static let deleteAllDataFailedTitle = "Couldn't Delete Data"

    /// Tests use an isolated store.
    @ObservationIgnored var autoRestoreFlag = AutoRestoreFlag.standard
    /// Tests use an isolated store.
    @ObservationIgnored var localDataOwner = LocalDataOwner.standard
    /// Tests inject a failing save.
    @ObservationIgnored var makeWiper: @MainActor (ModelContext) -> LocalDataWiper = { LocalDataWiper(modelContext: $0) }

    func loadSettings(from context: ModelContext) {
        let descriptor = FetchDescriptor<Settings>()
        if let settings = try? context.fetch(descriptor).first {
            defaultBuyIn = String(Int(settings.defaultBuyIn))
            defaultStakes = settings.defaultStakes
            defaultGameType = settings.defaultGameType
        }
    }

    func saveSettings(to context: ModelContext) {
        let descriptor = FetchDescriptor<Settings>()
        let settings: Settings
        if let existing = try? context.fetch(descriptor).first {
            settings = existing
        } else {
            settings = Settings()
            context.insert(settings)
        }

        settings.defaultBuyIn = Double(defaultBuyIn) ?? 200
        settings.defaultStakes = defaultStakes
        settings.defaultGameType = defaultGameType
        try? context.save()
    }

    func deleteAllData(from context: ModelContext) {
        // Set first: a deliberate wipe must never be undone by auto-restore,
        // even if the app is killed mid-delete.
        autoRestoreFlag.set()
        showDeleteAllSecondConfirmation = false
        do {
            // Deletes hands before sessions in one save; a batch delete fails
            // when sessions have hands (#263). On error nothing is deleted.
            try makeWiper(context).wipe()
        } catch {
            UserFacingError.log(error, action: .deleteAllData, to: Self.logger)
            deleteAllDataFailure = UserFacingError(error).message(for: .deleteAllData)
            return
        }
        deleteAllDataFailure = nil
        // No stats left, so they belong to no account (#69).
        localDataOwner.clear()
        resetToDefaults()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// After the server confirmed account deletion: remove every local model
    /// (settings too), end any Live Activity, and refresh widgets. Also clears
    /// the auto-restore flag: the account and its backups are gone, so the
    /// next sign-in is treated like a fresh install. Once the wipe succeeds
    /// the empty store has no owner (#69).
    func wipeAfterAccountDeletion(from context: ModelContext) {
        autoRestoreFlag.clear()
        do {
            try LocalDataWiper(modelContext: context).wipe()
            localDataOwner.clear()
        } catch {
            Self.logger.error("Local wipe after account deletion failed: \(error.localizedDescription, privacy: .private)")
        }
        resetToDefaults()
        Task {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The wiper also deletes the saved Settings, so show the defaults.
    private func resetToDefaults() {
        let defaults = Settings()
        defaultBuyIn = String(Int(defaults.defaultBuyIn))
        defaultStakes = defaults.defaultStakes
        defaultGameType = defaults.defaultGameType
    }

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "SettingsViewModel")
}
