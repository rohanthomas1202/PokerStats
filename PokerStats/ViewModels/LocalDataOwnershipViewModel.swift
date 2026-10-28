import Foundation
import SwiftData
import WidgetKit
import ActivityKit
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
    /// Bumped on each change to `owner`, which isn't observable itself.
    private var ownerRevision = 0
    /// The signed-in account still has to choose.
    @ObservationIgnored private var isChoicePending = false
    /// True while the sign-in sheet is up; the choice shows once it closes,
    /// since an alert can't present while a sheet is dismissing.
    @ObservationIgnored private var isPromptDeferred = false

    private static let logger = Logger(subsystem: "com.rohanthomas.PokerStats", category: "LocalDataOwnership")

    static let choiceTitle = "Stats From Another Account"
    static let choiceMessage = "The stats on this iPhone were saved with a different account. Choose what to do with them. Nothing is backed up until you choose."
    static let backUpButton = "Back Up to This Account"
    static let keepLocalButton = "Keep on This iPhone Only"
    static let deleteButton = "Delete from This iPhone"
    static let deleteTitle = "Delete Stats from This iPhone?"
    static let deleteMessage = "This permanently deletes the sessions and hands on this iPhone. Cloud backups aren't changed."
    static let blockedMessage = UserFacingError.dataFromAnotherAccountMessage
    static let chooseButton = "Choose What to Do"

    /// True when backups are off for the signed-in account. Read from the
    /// stored owner, so a manual restore (which adopts the data) counts too.
    var backupsBlocked: Bool {
        _ = ownerRevision
        guard let userId else { return false }
        return !owner.allowsUpload(for: userId)
    }

    /// Call when an account signs in, or is found signed in at launch.
    func signedIn(_ userId: UUID, modelContext: ModelContext) {
        self.userId = userId
        // An unreadable store counts as not empty, so it is never adopted silently.
        let isEmpty = (try? LocalDataRestorer(modelContext: modelContext).isStoreEmpty()) ?? false
        let status = owner.resolve(signedIn: userId, storeIsEmpty: isEmpty)
        ownerRevision += 1
        isChoicePending = status == .needsChoice
        isShowingChoice = isChoicePending && !isPromptDeferred
        isShowingDeleteConfirmation = false
    }

    func signedOut() {
        userId = nil
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
        ownerRevision += 1
        isChoicePending = false
        isShowingChoice = false
        backUp()
    }

    /// "Keep on This iPhone Only": the data stays, nothing uploads for this account.
    func keepOnThisDeviceOnly() {
        guard let userId else { return }
        owner.keepLocalOnly(for: userId)
        ownerRevision += 1
        isChoicePending = false
        isShowingChoice = false
    }

    /// "Delete from This iPhone": asks to confirm.
    func requestDelete() {
        isShowingChoice = false
        isShowingDeleteConfirmation = true
    }

    /// Cancel on the delete confirmation: back to the choice.
    func cancelDelete() {
        isShowingDeleteConfirmation = false
        isShowingChoice = backupsBlocked
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
            isShowingChoice = backupsBlocked
            return
        }
        owner.adopt(userId)
        ownerRevision += 1
        isChoicePending = false
        Task {
            for activity in Activity<SessionActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
