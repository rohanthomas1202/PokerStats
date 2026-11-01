import Foundation
import SwiftData
import SwiftUI
import Observation
import WidgetKit
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
    /// Read by VoiceOver after a successful Delete All Data, like Sign Out's feedback (#266).
    static let deleteAllDataAnnouncement = "All data deleted"

    /// The account was deleted but the local wipe threw; the alert offers a
    /// retry so the next person on this iPhone doesn't see the data (#60).
    var localWipeFailed = false

    static let localWipeFailedTitle = "Data Still on This iPhone"
    static let localWipeFailedMessage = "Your account was deleted, but the data on this iPhone couldn't be removed. Delete it now so no one else using this iPhone can see it."

    /// Tests use an isolated store.
    @ObservationIgnored var autoRestoreFlag = AutoRestoreFlag.standard
    /// Tests use an isolated store.
    @ObservationIgnored var localDataOwner = LocalDataOwner.standard
    /// Tests inject a failing save.
    @ObservationIgnored var makeWiper: @MainActor (ModelContext) -> LocalDataWiper = { LocalDataWiper(modelContext: $0) }
    /// Tests record the call instead of ending real Live Activities.
    @ObservationIgnored var endLiveActivities: @MainActor () -> Void = { LocalDataWiper.endLiveActivities() }
    /// Tests record the announcement instead of posting it.
    @ObservationIgnored var announce: @MainActor (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    /// Runs the result of Delete All Data once the "Are you absolutely sure?"
    /// alert has finished dismissing. SwiftUI can drop an alert requested
    /// while another is still dismissing (#270). Tests run it at once.
    @ObservationIgnored var afterConfirmationDismisses: @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void = { result in
        Task { @MainActor in
            try? await Task.sleep(for: SettingsViewModel.alertDismissalDelay)
            result()
        }
    }
    /// Longer than the system alert's dismiss animation.
    nonisolated static let alertDismissalDelay: Duration = .milliseconds(600)
    /// Bumped on each Delete All Data, so a late result from an earlier try is ignored.
    @ObservationIgnored private var deleteAllDataAttempt = 0

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
        deleteAllDataAttempt += 1
        let attempt = deleteAllDataAttempt
        do {
            // Deletes hands before sessions in one save; a batch delete fails
            // when sessions have hands (#263). On error nothing is deleted.
            try makeWiper(context).wipe()
        } catch {
            UserFacingError.log(error, action: .deleteAllData, to: Self.logger)
            // A local SwiftData failure has no network category, so use the
            // Delete All Data copy directly (#270).
            let message = UserFacingError.unknownMessage(for: .deleteAllData)
            afterConfirmationDismisses {
                guard self.deleteAllDataAttempt == attempt else { return }
                self.deleteAllDataFailure = message
            }
            return
        }
        deleteAllDataFailure = nil
        // No stats left, so they belong to no account (#69).
        localDataOwner.clear()
        // In the running app, any default this changes fires SettingsView's
        // onChange handlers, which call saveSettings and insert a fresh
        // default Settings row right after the wipe. Unit tests don't run the view, so they see no
        // Settings row ([0, 0, 0]). Both are expected (#270).
        resetToDefaults()
        // The active session is gone, so its Live Activity must go too (#269).
        endLiveActivities()
        WidgetCenter.shared.reloadAllTimelines()
        afterConfirmationDismisses {
            guard self.deleteAllDataAttempt == attempt else { return }
            self.announce(Self.deleteAllDataAnnouncement)
        }
    }

    /// After the server confirmed account deletion: remove every local model
    /// (settings too), end any Live Activity, and refresh widgets. Also clears
    /// the auto-restore flag: the account and its backups are gone, so the
    /// next sign-in is treated like a fresh install. Once the wipe succeeds
    /// the empty store has no owner (#69). If it fails, `localWipeFailed`
    /// shows an alert whose retry calls this again (#60).
    func wipeAfterAccountDeletion(from context: ModelContext) {
        autoRestoreFlag.clear()
        do {
            try makeWiper(context).wipe()
            localDataOwner.clear()
            localWipeFailed = false
        } catch {
            Self.logger.error("Local wipe after account deletion failed: \(error.localizedDescription, privacy: .private)")
            localWipeFailed = true
        }
        resetToDefaults()
        endLiveActivities()
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
