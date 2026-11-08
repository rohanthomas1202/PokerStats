import Foundation
import SwiftData
import Testing
@testable import PokerStats

private struct InjectedSaveFailure: Error {}

/// #60: after the account is deleted, a failed local wipe must tell the user
/// and let them retry, not leave their data on the iPhone silently.
@Suite("Local Wipe After Account Deletion Tests")
@MainActor
struct LocalWipeAfterAccountDeletionTests {
    private let owner = LocalDataOwner(defaults: UserDefaults(suiteName: "LocalWipeAfterAccountDeletionTests.\(UUID().uuidString)")!)
    private let container: ModelContainer

    init() throws {
        flag = freshFlag()
        pending = PendingLocalWipe(defaults: ThrowawayDefaults("LocalWipeAfterAccountDeletionTests"))
        container = try TestHelpers.createContainer()
        let context = container.mainContext
        let session = Session(location: "A", status: .completed, buyIn: 100)
        context.insert(session)
        let hand = TestHelpers.foldHand(number: 1)
        hand.session = session
        context.insert(hand)
        context.insert(Settings(defaultStakes: "2/5", defaultBuyIn: 500))
        try context.save()
        owner.adopt(UUID())
    }

    private var context: ModelContext { container.mainContext }

    /// Session, hand, and settings counts, read from a fresh context.
    private func counts() throws -> [Int] {
        let fresh = ModelContext(container)
        return [
            try fresh.fetchCount(FetchDescriptor<Session>()),
            try fresh.fetchCount(FetchDescriptor<Hand>()),
            try fresh.fetchCount(FetchDescriptor<Settings>()),
        ]
    }

    private let flag: AutoRestoreFlag
    private let pending: PendingLocalWipe
    /// Results held until "the alert has dismissed".
    private let held = HeldResults()
    private let announced = Announcements()

    private func viewModel(failing: Bool) -> SettingsViewModel {
        let vm = SettingsViewModel()
        vm.localDataOwner = owner
        vm.autoRestoreFlag = flag
        vm.pendingLocalWipe = pending
        let held = held
        vm.afterConfirmationDismisses = { held.results.append($0) }
        let announced = announced
        vm.announce = { announced.events.append($0) }
        vm.endLiveActivities = {}
        if failing {
            vm.makeWiper = { context in
                var wiper = LocalDataWiper(modelContext: context)
                wiper.save = { _ in throw InjectedSaveFailure() }
                return wiper
            }
        }
        return vm
    }

    @Test func successfulWipe_showsNoAlert() throws {
        let vm = viewModel(failing: false)

        vm.wipeAfterAccountDeletion(from: context)

        #expect(try counts() == [0, 0, 0])
        #expect(owner.ownerId == nil)
        #expect(!vm.localWipeFailed)
    }

    @Test func failedWipe_showsTheAlert_andKeepsTheOwner() throws {
        let ownerId = owner.ownerId
        let vm = viewModel(failing: true)

        vm.wipeAfterAccountDeletion(from: context)

        #expect(vm.localWipeFailed)
        #expect(try counts() == [1, 1, 1])
        #expect(owner.ownerId == ownerId)
    }

    @Test func retryAfterFailure_deletesEverything_andDismissesTheAlert() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)
        #expect(vm.localWipeFailed)

        vm.makeWiper = { LocalDataWiper(modelContext: $0) }
        vm.wipeAfterAccountDeletion(from: context)

        #expect(try counts() == [0, 0, 0])
        #expect(owner.ownerId == nil)
        #expect(!vm.localWipeFailed)
    }

    // MARK: - #273

    @Test func failedWipe_keepsTheSavedSettings() throws {
        let vm = viewModel(failing: true)
        vm.loadSettings(from: context)

        vm.wipeAfterAccountDeletion(from: context)

        #expect(vm.defaultBuyIn == "500")
        #expect(vm.defaultStakes == "2/5")
        let saved = try ModelContext(container).fetch(FetchDescriptor<Settings>())
        #expect(saved.first?.defaultBuyIn == 500)
        #expect(saved.first?.defaultStakes == "2/5")
    }

    @Test func failedWipe_stillClearsTheAutoRestoreFlag() throws {
        flag.set()
        let vm = viewModel(failing: true)

        vm.wipeAfterAccountDeletion(from: context)

        #expect(!flag.isSet)
    }

    @Test func notNow_leavesTheData_andSettingsAsksAgain() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)

        // Not Now: SwiftUI sets the binding to false.
        vm.localWipeFailed = false
        #expect(try counts() == [1, 1, 1])

        // Settings appears again, or after a relaunch with a new view model.
        let relaunched = viewModel(failing: true)
        #expect(!relaunched.localWipeFailed)
        relaunched.showPendingLocalWipe(isSignedIn: false)
        #expect(relaunched.localWipeFailed)
    }

    @Test func successfulWipe_clearsThePendingPrompt() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)
        #expect(pending.isRecorded)

        vm.makeWiper = { LocalDataWiper(modelContext: $0) }
        vm.wipeAfterAccountDeletion(from: context)

        #expect(!pending.isRecorded)
        let fresh = viewModel(failing: false)
        fresh.showPendingLocalWipe(isSignedIn: false)
        #expect(!fresh.localWipeFailed)
    }

    @Test func deleteAllData_afterFailedWipe_clearsThePrompt() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)
        vm.localWipeFailed = false

        vm.makeWiper = { LocalDataWiper(modelContext: $0) }
        vm.deleteAllData(from: context)

        #expect(try counts() == [0, 0, 0])
        #expect(!pending.isRecorded)
        let relaunched = viewModel(failing: false)
        relaunched.showPendingLocalWipe(isSignedIn: false)
        #expect(!relaunched.localWipeFailed)
    }

    @Test func signInAfterFailedWipe_showsNoAlert_andKeepsTheNewAccountsData() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)
        vm.localWipeFailed = false

        // Another account signs in; it may or may not take the data.
        let relaunched = viewModel(failing: false)
        relaunched.showPendingLocalWipe(isSignedIn: true)

        #expect(!relaunched.localWipeFailed)
        #expect(!pending.isRecorded)
        #expect(try counts() == [1, 1, 1])
        relaunched.showPendingLocalWipe(isSignedIn: false)
        #expect(!relaunched.localWipeFailed)
    }

    @Test func ownerChangeAfterFailedWipe_showsNoAlert() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)
        vm.localWipeFailed = false

        // Another account signed in and adopted the data, then signed out.
        owner.adopt(UUID())
        let relaunched = viewModel(failing: false)
        relaunched.showPendingLocalWipe(isSignedIn: false)

        #expect(!relaunched.localWipeFailed)
        #expect(try counts() == [1, 1, 1])
    }

    // MARK: - #272

    @Test func secondRetryFailure_showsTheAlertAfterItDismisses() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)

        // Delete Local Data: SwiftUI dismisses the alert, then the retry runs.
        vm.localWipeFailed = false
        vm.retryLocalWipe(from: context)
        // SwiftUI may reset the binding while the alert dismisses.
        vm.localWipeFailed = false
        #expect(held.results.count == 1)

        held.results.removeFirst()()
        #expect(vm.localWipeFailed)
        #expect(try counts() == [1, 1, 1])
        #expect(announced.events.isEmpty)
    }

    @Test func retrySuccess_announcesIt() throws {
        let vm = viewModel(failing: true)
        vm.wipeAfterAccountDeletion(from: context)
        vm.localWipeFailed = false

        vm.makeWiper = { LocalDataWiper(modelContext: $0) }
        vm.retryLocalWipe(from: context)
        #expect(announced.events.isEmpty)
        held.results.removeFirst()()

        #expect(announced.events == [SettingsViewModel.localWipeRetrySucceededAnnouncement])
        #expect(!vm.localWipeFailed)
        #expect(try counts() == [0, 0, 0])
    }

    @Test func notNowCopy_pointsToDeleteAllData() {
        #expect(SettingsViewModel.localWipeFailedMessage.hasSuffix("You can also use Delete All Data in Settings."))
    }
}

private final class HeldResults: @unchecked Sendable {
    var results: [@MainActor @Sendable () -> Void] = []
}

private final class Announcements: @unchecked Sendable {
    var events: [String] = []
}
