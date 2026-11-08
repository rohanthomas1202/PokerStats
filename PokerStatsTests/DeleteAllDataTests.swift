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
    private let owner = LocalDataOwner(defaults: ThrowawayDefaults("DeleteAllDataTests"))
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

    /// Results run at once instead of after the alert dismisses, and
    /// VoiceOver announcements are recorded in `announcements`.
    private func viewModel(announcements: Announcements = Announcements()) -> SettingsViewModel {
        let vm = SettingsViewModel()
        vm.localDataOwner = owner
        vm.autoRestoreFlag = freshFlag()
        vm.afterConfirmationDismisses = { $0() }
        vm.announce = { announcements.list.append($0) }
        return vm
    }

    private static func failingWiper(_ context: ModelContext) -> LocalDataWiper {
        var wiper = LocalDataWiper(modelContext: context)
        wiper.save = { _ in throw InjectedSaveFailure() }
        return wiper
    }

    @Test func sessionsWithHands_deletesEverything_andClearsTheOwner() throws {
        try seed()
        #expect(try counts() == [2, 3, 1])
        #expect(owner.ownerId != nil)
        let vm = viewModel()
        vm.loadSettings(from: context)
        vm.showDeleteAllSecondConfirmation = true

        vm.deleteAllData(from: context)

        // No Settings row here because the view's onChange -> saveSettings
        // doesn't run in a unit test. In the app, a fresh default row is
        // saved right after the wipe (#270). Both are expected.
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
        // The title says "Couldn't Delete Data", so the message doesn't repeat it (#266).
        #expect(vm.deleteAllDataFailure == "Nothing on this iPhone was changed. Try again.")
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

    /// #269: like account deletion, Delete All Data ends the Live Activity,
    /// so the Lock Screen doesn't keep showing a deleted session.
    @Test func successfulWipe_endsLiveActivities() throws {
        try seed()
        let vm = viewModel()
        var endCalls = 0
        vm.endLiveActivities = { endCalls += 1 }

        vm.deleteAllData(from: context)

        #expect(try counts() == [0, 0, 0])
        #expect(endCalls == 1)
    }

    /// Nothing was deleted, so the running session's Live Activity stays.
    @Test func failedWipe_keepsLiveActivities() throws {
        try seed()
        let vm = viewModel()
        var endCalls = 0
        vm.endLiveActivities = { endCalls += 1 }
        vm.makeWiper = { context in
            var wiper = LocalDataWiper(modelContext: context)
            wiper.save = { _ in throw InjectedSaveFailure() }
            return wiper
        }

        vm.deleteAllData(from: context)

        #expect(try counts() == [2, 3, 1])
        #expect(endCalls == 0)
    }

    /// #266: a successful wipe is announced for VoiceOver, like Sign Out.
    @Test func successfulWipe_announcesAllDataDeleted() throws {
        try seed()
        let announcements = Announcements()
        let vm = viewModel(announcements: announcements)

        vm.deleteAllData(from: context)

        #expect(try counts() == [0, 0, 0])
        #expect(announcements.list == ["All data deleted"])
    }

    @Test func failedWipe_announcesNothing() throws {
        try seed()
        let announcements = Announcements()
        let vm = viewModel(announcements: announcements)
        vm.makeWiper = Self.failingWiper

        vm.deleteAllData(from: context)

        #expect(announcements.list.isEmpty)
        #expect(vm.deleteAllDataFailure != nil)
    }

    /// #270: the failure alert waits until the "Are you absolutely sure?"
    /// alert has dismissed, so SwiftUI doesn't drop it.
    @Test func failedWipe_showsTheErrorAfterTheConfirmationDismisses() throws {
        try seed()
        let vm = viewModel()
        var pending: [@MainActor @Sendable () -> Void] = []
        vm.afterConfirmationDismisses = { pending.append($0) }
        vm.makeWiper = Self.failingWiper
        vm.showDeleteAllSecondConfirmation = true

        vm.deleteAllData(from: context)

        #expect(!vm.showDeleteAllSecondConfirmation)
        #expect(vm.deleteAllDataFailure == nil)
        #expect(pending.count == 1)

        pending.forEach { $0() }

        #expect(vm.deleteAllDataFailure == UserFacingError.unknownMessage(for: .deleteAllData))
    }

    /// The default delay presents the error on its own, a moment later.
    @Test func failedWipe_defaultDelay_showsTheError() async throws {
        try seed()
        let vm = SettingsViewModel()
        vm.localDataOwner = owner
        vm.autoRestoreFlag = freshFlag()
        vm.announce = { _ in }
        vm.makeWiper = Self.failingWiper

        vm.deleteAllData(from: context)
        #expect(vm.deleteAllDataFailure == nil)

        let deadline = ContinuousClock.now + .seconds(5)
        while vm.deleteAllDataFailure == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(vm.deleteAllDataFailure == UserFacingError.unknownMessage(for: .deleteAllData))
    }

    /// A late error from an earlier try doesn't show after a retry succeeded.
    @Test func lateErrorFromAnEarlierTry_isIgnored() throws {
        try seed()
        let announcements = Announcements()
        let vm = viewModel(announcements: announcements)
        var pending: [@MainActor @Sendable () -> Void] = []
        vm.afterConfirmationDismisses = { pending.append($0) }
        vm.makeWiper = Self.failingWiper
        vm.deleteAllData(from: context)

        vm.makeWiper = { LocalDataWiper(modelContext: $0) }
        vm.deleteAllData(from: context)
        pending.forEach { $0() }

        #expect(try counts() == [0, 0, 0])
        #expect(vm.deleteAllDataFailure == nil)
        #expect(announcements.list == ["All data deleted"])
    }
}

/// VoiceOver announcements a test view model posted.
@MainActor
private final class Announcements {
    var list: [String] = []
}
