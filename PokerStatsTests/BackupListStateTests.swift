import Foundation
import Testing
@testable import PokerStats

/// The backup list's loading, empty and failed states (#38).
@Suite("Backup List State Tests", .timeLimit(.minutes(1)))
@MainActor
struct BackupListStateTests {

    @MainActor
    private final class FakeBackupList {
        var results: [Result<[BackupMetadata], any Error>]
        var calls = 0
        var gate: CheckedContinuation<Void, Never>?
        var holdNext = false
        init(_ results: [Result<[BackupMetadata], any Error>]) { self.results = results }

        func list() async throws -> [BackupMetadata] {
            calls += 1
            if holdNext {
                holdNext = false
                await withCheckedContinuation { gate = $0 }
            }
            return try results.removeFirst().get()
        }
    }

    private let backup = BackupMetadata(
        id: UUID(), userId: UUID(), storagePath: "p", fileSizeBytes: 1,
        schemaVersion: 1, sessionCount: 2, handCount: 0, createdAt: .now
    )

    private func viewModel(_ fake: FakeBackupList, signedIn: Bool = true) -> BackupViewModel {
        let vm = BackupViewModel()
        vm.configure(BackupViewModel.Actions(
            isSignedIn: { signedIn },
            listBackups: { try await fake.list() },
            createBackup: { throw CancellationError() },
            downloadBackup: { _ in throw CancellationError() },
            restoreBackup: { _ in }
        ))
        return vm
    }

    @Test func startsLoading_notEmpty() {
        let vm = viewModel(FakeBackupList([]))
        #expect(vm.listState == .loading)
        #expect(!vm.isLoadingBackups)
        #expect(vm.listState != .empty)
    }

    @Test func loadingToLoaded() async {
        let fake = FakeBackupList([.success([backup])])
        fake.holdNext = true
        let vm = viewModel(fake)

        let task = Task { await vm.loadBackups() }
        while fake.gate == nil { await Task.yield() }
        #expect(vm.listState == .loading)
        #expect(vm.isLoadingBackups)

        fake.gate?.resume()
        await task.value
        #expect(vm.listState == .loaded([backup]))
        #expect(!vm.isLoadingBackups)
    }

    @Test func loadingToEmpty() async {
        let vm = viewModel(FakeBackupList([.success([])]))
        await vm.loadBackups()
        #expect(vm.listState == .empty)
        #expect(vm.errorMessage == nil)
    }

    @Test func loadingToFailed_retryLoads() async {
        let fake = FakeBackupList([.failure(URLError(.notConnectedToInternet)), .success([backup])])
        let vm = viewModel(fake)

        await vm.loadBackups()
        #expect(vm.listState == .failed(UserFacingError.offlineMessage))
        #expect(vm.listState != .empty)
        #expect(vm.showsLoadFailureInList)
        #expect(vm.canRetry)

        await vm.retry()
        #expect(fake.calls == 2)
        #expect(vm.listState == .loaded([backup]))
        #expect(!vm.showsLoadFailureInList)
        #expect(vm.errorMessage == nil)
    }

    @Test func failedWithUnknownError_showsFriendlyCopy() async {
        struct Raw: Error {}
        let vm = viewModel(FakeBackupList([.failure(Raw())]))
        await vm.loadBackups()
        #expect(vm.listState == .failed(UserFacingError.unknownMessage(for: .loadBackups)))
    }

    @Test func refresh_reloadsTheList() async {
        let fake = FakeBackupList([.success([]), .success([backup])])
        let vm = viewModel(fake)

        await vm.loadBackups()
        #expect(vm.listState == .empty)

        await vm.refresh()
        #expect(fake.calls == 2)
        #expect(vm.listState == .loaded([backup]))
    }

    @Test func signedOut_isEmpty_withoutCallingTheService() async {
        let fake = FakeBackupList([])
        let vm = viewModel(fake, signedIn: false)
        await vm.loadBackups()
        #expect(vm.listState == .empty)
        #expect(fake.calls == 0)
    }
}
