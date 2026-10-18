import Foundation
import Testing
@testable import PokerStats

private struct DeletionFailed: Error, LocalizedError {
    var errorDescription: String? { "Your account wasn't deleted." }
}

@MainActor
private final class Counter {
    var value = 0
}

/// `onDeleted` wipes local data in Settings, so it must run only on success.
@Suite("Auth View Model Delete Tests")
@MainActor
struct AuthViewModelDeleteTests {

    private func viewModel(_ perform: @escaping @MainActor () async throws -> Void) -> AuthViewModel {
        AuthViewModel(authService: AuthService(), performDeleteAccount: perform)
    }

    @Test func success_runsOnDeleted() async {
        let wiped = Counter()
        let vm = viewModel { }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(wiped.value == 1)
        #expect(vm.deleteAccountErrorMessage == nil)
        #expect(!vm.isProcessing)
    }

    @Test func cancelledReauth_skipsOnDeleted_andShowsNoError() async {
        let wiped = Counter()
        let vm = viewModel { throw AccountDeletionError.reauthenticationCancelled }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(wiped.value == 0)
        #expect(vm.deleteAccountErrorMessage == nil)
        #expect(!vm.isProcessing)
    }

    @Test func failure_skipsOnDeleted_andSetsErrorForAlert() async {
        let wiped = Counter()
        let vm = viewModel { throw DeletionFailed() }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(wiped.value == 0)
        #expect(vm.deleteAccountErrorMessage == "Your account wasn't deleted.")
        #expect(vm.errorMessage == nil) // sign-in sheet's message is untouched
        #expect(!vm.isProcessing)
    }

    @Test func deletionFailedCopy_isUserFacing() {
        let message = AuthServiceError.deletionFailed("HTTP 500: {\"step\":\"x\"}").errorDescription ?? ""
        #expect(message.hasPrefix("Your account wasn't deleted."))
        #expect(!message.contains("HTTP"))
    }
}
