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

    private func viewModel(failing: Bool) -> SettingsViewModel {
        let vm = SettingsViewModel()
        vm.localDataOwner = owner
        vm.autoRestoreFlag = freshFlag()
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
}
