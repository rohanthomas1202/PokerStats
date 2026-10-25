import Foundation
import Testing
@testable import PokerStats

private struct NetworkDown: Error {}

@MainActor
private final class Counter {
    var value = 0
}

/// Lets a test hold the fake deletion "in flight" and finish it on demand.
@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var started = false

    func wait() async throws {
        started = true
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(throwing error: Error? = nil) {
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
        continuation = nil
    }
}

/// In Settings, `onDeleted` wipes local data, so it must run only after the
/// server confirms the deletion.
@Suite("Auth View Model Delete Tests")
@MainActor
struct AuthViewModelDeleteTests {

    private func viewModel(_ perform: @escaping @MainActor () async throws -> Void) -> AuthViewModel {
        AuthViewModel(authService: AuthService(), performDeleteAccount: perform)
    }

    @Test func inProgress_showsOverlay_andHasNotWipedYet() async {
        let gate = Gate()
        let wiped = Counter()
        let vm = viewModel { try await gate.wait() }

        let task = vm.deleteAccount { wiped.value += 1 }
        #expect(vm.isDeletingAccount)
        while !gate.started { await Task.yield() }
        #expect(vm.isDeletingAccount)
        #expect(wiped.value == 0)

        gate.finish()
        await task.value
        #expect(!vm.isDeletingAccount)
        #expect(wiped.value == 1)
    }

    @Test func success_wipesLocalDataOnlyAfterServerOK() async {
        let wiped = Counter()
        let serverDone = Counter()
        let vm = viewModel { serverDone.value += 1 }
        await vm.deleteAccount {
            #expect(serverDone.value == 1) // server finished first
            wiped.value += 1
        }.value
        #expect(wiped.value == 1)
        #expect(vm.deleteAccountFailure == nil)
        #expect(!vm.isDeletingAccount)
    }

    @Test func failure_keepsLocalData_andShowsRetryableError() async {
        let wiped = Counter()
        let vm = viewModel { throw NetworkDown() }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(wiped.value == 0)
        #expect(vm.deleteAccountFailure == .retryable)
        #expect(vm.deleteAccountFailure?.title == "Couldn't Delete Account")
        #expect(vm.deleteAccountFailure?.message == "Your account wasn't deleted. Check your connection and try again.")
        #expect(vm.errorMessage == nil) // sign-in sheet's message is untouched
        #expect(!vm.isDeletingAccount)
    }

    @Test func appleRevokedButCleanupFailed_showsSignInAgainMessage_andKeepsLocalData() async {
        let wiped = Counter()
        let vm = viewModel { throw AccountDeletionError.cleanupFailedAfterAppleRevoke }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(wiped.value == 0)
        #expect(vm.deleteAccountFailure?.kind == .appleDisconnected)
        #expect(vm.deleteAccountFailure?.title == "Couldn't Finish Deleting Account")
        #expect(vm.deleteAccountFailure?.message == "Your Apple ID was disconnected, but some account data wasn't deleted. Sign in with Apple again, then try again.")
    }

    @Test func cancelledReauth_keepsLocalData_andShowsNoError() async {
        let wiped = Counter()
        let vm = viewModel { throw AccountDeletionError.reauthenticationCancelled }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(wiped.value == 0)
        #expect(vm.deleteAccountFailure == nil)
        #expect(!vm.isDeletingAccount)
    }

    @Test func retry_afterFailure_succeeds_andWipesWithOriginalHandler() async {
        let wiped = Counter()
        let attempts = Counter()
        let vm = viewModel {
            attempts.value += 1
            if attempts.value == 1 { throw NetworkDown() }
        }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(vm.deleteAccountFailure == .retryable)
        #expect(wiped.value == 0)

        await vm.retryDeleteAccount().value
        #expect(attempts.value == 2)
        #expect(wiped.value == 1)
        #expect(vm.deleteAccountFailure == nil)
    }

    // MARK: - Failure codes (#105)

    private func outcome(after error: AccountDeletionError) async -> (AuthViewModel.DeleteAccountFailure?, Int) {
        let wiped = Counter()
        let vm = viewModel { throw error }
        await vm.deleteAccount { wiped.value += 1 }.value
        #expect(!vm.isDeletingAccount)
        return (vm.deleteAccountFailure, wiped.value)
    }

    @Test func appleAccountMismatch_showsUseMatchingAppleID_noTryAgain() async {
        let (failure, wiped) = await outcome(after: .appleAccountMismatch)
        #expect(wiped == 0)
        #expect(failure == .appleAccountMismatch)
        #expect(failure?.kind == .notRetryable)
        #expect(failure?.message == "The Apple ID on this device doesn't match your account. Your account wasn't deleted. To delete it, use a device signed in with the Apple ID you used for PokerStats.")
    }

    @Test func needsSupport_showsContactSupport_noTryAgain() async {
        let (failure, wiped) = await outcome(after: .needsSupport)
        #expect(wiped == 0)
        #expect(failure == .needsSupport)
        #expect(failure?.kind == .notRetryable)
        #expect(failure?.message == "Your account couldn't be deleted. Contact support at [CONTACT_EMAIL].")
    }

    @Test func temporarilyUnavailable_showsTryLater_okOnly() async {
        let (failure, wiped) = await outcome(after: .temporarilyUnavailable)
        #expect(wiped == 0)
        #expect(failure == .temporarilyUnavailable)
        #expect(failure?.kind == .notRetryable)
        #expect(failure?.message == "Account deletion is temporarily unavailable. Your account wasn't deleted. Try again later.")
    }

    @Test func temporarilyUnavailable_isNotRetriedAutomatically() async {
        let attempts = Counter()
        let vm = viewModel {
            attempts.value += 1
            throw AccountDeletionError.temporarilyUnavailable
        }
        await vm.deleteAccount().value
        #expect(attempts.value == 1)
    }

    /// End to end through AuthService: a typed error isn't flattened to the generic one.
    @Test func authService_passesTypedErrorsThrough() async {
        let auth = AuthService()
        let vm = AuthViewModel(authService: auth, performDeleteAccount: {
            try await auth.deleteAccount(serverDelete: {
                throw AccountDeleter.mapped(SupabaseError.httpError(
                    statusCode: 422,
                    message: #"{"error":"x","code":"apple_account_mismatch","step":"s","retryable":false}"#
                ))
            })
        })
        await vm.deleteAccount().value
        #expect(vm.deleteAccountFailure == .appleAccountMismatch)
        #expect(auth.error == nil)
    }
}
