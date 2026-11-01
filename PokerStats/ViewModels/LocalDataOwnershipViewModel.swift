import Foundation
import SwiftData
import WidgetKit
import os

/// Asks what to do when an account signs in and the stats on this device
/// belong to a different account (#69). Until the user chooses, nothing is
/// backed up; `BackupService` and `AuthService.scheduleBackup` enforce that
/// through `LocalDataOwner`.
@Observable
@MainActor
final class LocalDataOwnershipViewModel {
    var isShowingChoice = false
    var isShowingDeleteConfirmation = false

    /// Tests use an isolated store.
    @ObservationIgnored var owner = LocalDataOwner.standard
    /// The signed-in account; nil while signed out.
    private(set) var userId: UUID?
    /// Bumped on each change to `owner`, which isn't observable itself,
    /// including changes made elsewhere: Delete All Data, a manual restore,
    /// a backup (#264).
    private(set) var ownerRevision = 0
    /// Bumped when "Delete from This iPhone" wiped the store, so Settings
    /// shows the default buy-in, stakes and game again (#264).
    private(set) var localDataDeletions = 0
    /// The signed-in account still has to choose.
    @ObservationIgnored private var isChoicePending = false
    /// True while the sign-in sheet is up; the choice shows once it closes,
    /// since an alert can't present while a sheet is dismissing.
    @ObservationIgnored private var isPromptDeferred = false

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "LocalDataOwnership")

    static let choiceTitle = "Stats From Another Account"
    /// Names the signed-in account, so a person on a shared iPhone knows
    /// which account "This Account" is (#262), and says that backing up
    /// counts toward its kept backups (#264).
    static func choiceMessage(signedInAs email: String?) -> String {
        let saved = if let email, !email.isEmpty {
            "The stats on this iPhone were saved with a different account than \(email)."
        } else {
            "The stats on this iPhone were saved with a different account."
        }
        return "\(saved) Backing them up to this account replaces its older backups over time, since only the \(BackupService.keptBackupCount) newest are kept. Nothing is backed up until you choose."
    }
    static let backUpButton = "Back Up to This Account"
    static let keepLocalButton = "Keep on This iPhone Only"
    static let deleteButton = "Delete from This iPhone"
    static let deleteTitle = "Delete Stats from This iPhone?"
    static let deleteMessage = "This permanently deletes the sessions, hands and settings on this iPhone. Cloud backups aren't changed."
    static let blockedMessage = UserFacingError.dataFromAnotherAccountMessage
    static let chooseButton = "Choose What to Do"

    init() {
        // Not removed: the block holds self weakly, and the app's instance
        // lives as long as the app, as AuthService's observer does.
        NotificationCenter.default.addObserver(
            forName: LocalDataOwner.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let defaults = notification.object as AnyObject? else { return }
            let changed = ObjectIdentifier(defaults)
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.ownerDidChange(in: changed) }
            } else {
                Task { @MainActor in self?.ownerDidChange(in: changed) }
            }
        }
    }

    /// Only this view model's store counts; tests each use their own.
    private func ownerDidChange(in defaults: ObjectIdentifier) {
        guard defaults == ObjectIdentifier(owner.defaults) else { return }
        ownerRevision += 1
    }

    /// Presents the next alert once the current one has finished dismissing.
    /// SwiftUI can drop an alert requested while another is still
    /// dismissing (#262, as in #270). Tests run it at once.
    @ObservationIgnored var afterAlertDismisses: @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void = { present in
        Task { @MainActor in
            try? await Task.sleep(for: SettingsViewModel.alertDismissalDelay)
            present()
        }
    }
    /// Bumped on each sign-in, sign-out and alert change, so a late
    /// presentation from an earlier state is dropped.
    @ObservationIgnored private var presentation = 0

    /// True when backups are off for the signed-in account. Read from the
    /// stored owner, so a manual restore (which adopts the data) counts too.
    var backupsBlocked: Bool {
        _ = ownerRevision
        guard let userId else { return false }
        return !owner.allowsUpload(for: userId)
    }

    /// VoiceOver hint on the dimmed Back Up Now, so the reason is heard
    /// with the button rather than after it (#262). Empty when not blocked.
    var backUpNowHint: String {
        backupsBlocked ? Self.blockedMessage : ""
    }

    /// Call when an account signs in, or is found signed in at launch.
    func signedIn(_ userId: UUID, modelContext: ModelContext) {
        self.userId = userId
        presentation += 1
        // An unreadable store counts as not empty, so it is never adopted silently.
        let isEmpty = (try? LocalDataRestorer(modelContext: modelContext).isStoreEmpty()) ?? false
        let status = owner.resolve(signedIn: userId, storeIsEmpty: isEmpty)
        // resolve may not change the owner; userId changed either way.
        ownerRevision += 1
        isChoicePending = status == .needsChoice
        isShowingChoice = isChoicePending && !isPromptDeferred
        isShowingDeleteConfirmation = false
    }

    /// The sign-in sequence (#326): the owner check, then the sign-in backup.
    /// In this order, data the check adopted (no owner before) is backed up,
    /// and another account's data never is (#311).
    func signedIn(_ userId: UUID, modelContext: ModelContext, authService: AuthService) {
        signedIn(userId, modelContext: modelContext)
        authService.backUpUnsentChangesAtSignIn(modelContext: modelContext)
    }

    func signedOut() {
        userId = nil
        presentation += 1
        isChoicePending = false
        isShowingChoice = false
        isShowingDeleteConfirmation = false
    }

    /// The sign-in sheet opened: hold the choice until it closes.
    func deferPrompt() {
        isPromptDeferred = true
    }

    /// The sign-in sheet closed: show the choice if a sign-in needs one.
    func resumePrompt() {
        isPromptDeferred = false
        if isChoicePending, !isShowingDeleteConfirmation {
            isShowingChoice = true
        }
    }

    /// "Choose What to Do" in Cloud Backup: asks again.
    func showChoice() {
        guard backupsBlocked else { return }
        isShowingChoice = true
    }

    /// "Back Up to This Account": the signed-in account takes the data, then
    /// `backUp` uploads it.
    func backUpToThisAccount(backUp: () -> Void) {
        guard let userId else { return }
        owner.adopt(userId)
        isChoicePending = false
        isShowingChoice = false
        backUp()
    }

    /// "Keep on This iPhone Only": the data stays, nothing uploads for this account.
    func keepOnThisDeviceOnly() {
        guard let userId else { return }
        owner.keepLocalOnly(for: userId)
        isChoicePending = false
        isShowingChoice = false
    }

    /// "Delete from This iPhone": asks to confirm once the choice has closed.
    func requestDelete() {
        isShowingChoice = false
        presentAfterDismissal { $0.isShowingDeleteConfirmation = true }
    }

    /// Cancel on the delete confirmation: back to the choice.
    func cancelDelete() {
        isShowingDeleteConfirmation = false
        presentAfterDismissal { $0.isShowingChoice = true }
    }

    /// Runs `present` after the closing alert is gone, unless the account
    /// changed, the data no longer needs a choice, or another alert change
    /// came first.
    private func presentAfterDismissal(_ present: @escaping @MainActor @Sendable (LocalDataOwnershipViewModel) -> Void) {
        presentation += 1
        let current = presentation
        afterAlertDismisses {
            guard self.presentation == current, self.backupsBlocked else { return }
            present(self)
        }
    }

    /// Deletes every local model, then the signed-in account owns the empty
    /// store. On failure nothing is deleted and the choice comes back.
    func confirmDelete(modelContext: ModelContext) {
        isShowingDeleteConfirmation = false
        guard let userId else { return }
        do {
            try LocalDataWiper(modelContext: modelContext).wipe()
        } catch {
            Self.logger.error("Deleting another account's local data failed: \(error.localizedDescription, privacy: .private)")
            presentAfterDismissal { $0.isShowingChoice = true }
            return
        }
        owner.adopt(userId)
        isChoicePending = false
        localDataDeletions += 1
        LocalDataWiper.endLiveActivities()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
