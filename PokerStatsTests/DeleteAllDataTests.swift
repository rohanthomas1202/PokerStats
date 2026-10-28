import Foundation
import SwiftData
import Testing
@testable import PokerStats

private struct InjectedSaveFailure: Error {}

/// #263: Delete All Data with hands must delete everything, or tell the user
/// it didn't. It must never fail silently.
@Suite("Delete All Data Tests")
@MainActor
struct DeleteAllDataTests {
    private let owner = LocalDataOwner(defaults: UserDefaults(suiteName: "DeleteAllDataTests.\(UUID().uuidString)")!)
    private let container: ModelContainer

    init() throws {
        container = try TestHelpers.createContainer()
    }

    private var context: ModelContext { container.mainContext }

    /// Two sessions with three hands, saved settings, and an owner record.
    private func seed() throws {
        let a = Session(location: "A", status: .completed, buyIn: 100)
        let b = Session(location: "B", status: .completed, buyIn: 200)
        context.insert(a)
        context.insert(b)
        for (number, session) in [(1, a), (2, a), (1, b)] {
            let hand = TestHelpers.foldHand(number: number)
            hand.session = session
            context.insert(hand)
        }
        context.insert(Settings(defaultStakes: "2/5", defaultBuyIn: 500))
        try context.save()
        owner.adopt(UUID())
    }

    /// Session, hand, and settings counts, read from a fresh context.
    private func counts() throws -> [Int] {
        let fresh = ModelContext(container)
        return [
            try fresh.fetchCount(FetchDescriptor<Session>()),
            try fresh.fetchCount(FetchDescriptor<Hand>()),
            try fresh.fetchCount(FetchDescriptor<Settings>()),
        ]
    }

    private func viewModel() -> SettingsViewModel {
        let vm = SettingsViewModel()
        vm.localDataOwner = owner
        vm.autoRestoreFlag = freshFlag()
        return vm
    }

    @Test func sessionsWithHands_deletesEverything_andClearsTheOwner() throws {
        try seed()
        #expect(try counts() == [2, 3, 1])
        #expect(owner.ownerId != nil)
        let vm = viewModel()
        vm.loadSettings(from: context)
        vm.showDeleteAllSecondConfirmation = true

        vm.deleteAllData(from: context)

        #expect(try counts() == [0, 0, 0])
        #expect(owner.ownerId == nil)
        #expect(owner.localOnlyUserId == nil)
        #expect(vm.autoRestoreFlag.isSet)
        #expect(vm.deleteAllDataFailure == nil)
        #expect(!vm.showDeleteAllSecondConfirmation)
        #expect(vm.defaultBuyIn == "200")
        #expect(vm.defaultStakes == "1/2")
    }

    @Test func failedWipe_keepsEverything_andShowsAnError() throws {
        try seed()
        let ownerId = owner.ownerId
        let vm = viewModel()
        vm.makeWiper = { context in
            var wiper = LocalDataWiper(modelContext: context)
            wiper.save = { _ in throw InjectedSaveFailure() }
            return wiper
        }
        vm.showDeleteAllSecondConfirmation = true

        vm.deleteAllData(from: context)

        #expect(try counts() == [2, 3, 1])
        #expect(owner.ownerId == ownerId)
        #expect(vm.deleteAllDataFailure == UserFacingError.unknownMessage(for: .deleteAllData))
        #expect(vm.deleteAllDataFailure?.contains("InjectedSaveFailure") == false)
        #expect(!vm.showDeleteAllSecondConfirmation)
    }

    @Test func retryAfterFailure_succeeds_andClearsTheError() throws {
        try seed()
        let vm = viewModel()
        vm.makeWiper = { context in
            var wiper = LocalDataWiper(modelContext: context)
            wiper.save = { _ in throw InjectedSaveFailure() }
            return wiper
        }
        vm.deleteAllData(from: context)
        #expect(vm.deleteAllDataFailure != nil)

        vm.makeWiper = { LocalDataWiper(modelContext: $0) }
        vm.deleteAllData(from: context)

        #expect(try counts() == [0, 0, 0])
        #expect(owner.ownerId == nil)
        #expect(vm.deleteAllDataFailure == nil)
    }
}
