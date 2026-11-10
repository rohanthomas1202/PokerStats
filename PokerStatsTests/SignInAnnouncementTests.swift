import AuthenticationServices
import Foundation
import Testing
@testable import PokerStats

/// What VoiceOver was told, and whether sign-in was in progress at the time.
@MainActor
private final class Spoken {
    var list: [String] = []
    var processingWhenSpoken: [Bool] = []
}

private let appleAuthorization = AppleAuthorization(
    identityToken: Data("id-token".utf8),
    authorizationCode: Data("code".utf8),
    appleUserId: "001234.abc"
)

/// VoiceOver hears "Signing in" once per sign-in attempt (#228).
@Suite("Sign In Announcement Tests")
@MainActor
struct SignInAnnouncementTests {

    private func viewModel(
        _ spoken: Spoken,
        signIn: @escaping @MainActor () async throws -> Void = {},
        authorize: @escaping @MainActor () async throws -> AppleAuthorization = { appleAuthorization }
    ) -> AuthViewModel {
        let vm = AuthViewModel(
            authService: TestHelpers.authService(),
            performDeleteAccount: {},
            performAppleSignIn: { _ in try await signIn() },
            performAppleAuthorization: { _ in try await authorize() }
        )
        vm.announce = { [weak vm] message in
            spoken.list.append(message)
            spoken.processingWhenSpoken.append(vm?.isProcessing ?? false)
        }
        return vm
    }

    private func complete(_ vm: AuthViewModel) -> Task<Void, Never>? {
        vm.completeAppleSignIn(
            identityToken: Data("id-token".utf8),
            authorizationCode: Data("code".utf8),
            appleUserId: "001234.abc"
        )
    }

    @Test func signInStart_announcesSigningInOnce_whileProcessing() async {
        let spoken = Spoken()
        let vm = viewModel(spoken)
        _ = vm.startAppleSignInAttempt()
        #expect(spoken.list.isEmpty) // not while Apple's sheet is up

        let task = complete(vm)
        #expect(spoken.list == ["Signing in"])
        #expect(spoken.processingWhenSpoken == [true])
        await task?.value
        #expect(spoken.list == ["Signing in"])
    }

    @Test func announcementText_matchesTheVisibleLabel() {
        #expect(AuthViewModel.signingInAnnouncement == "Signing in")
    }

    @Test func failedSignIn_announcedOnlyAtStart() async {
        let spoken = Spoken()
        let vm = viewModel(spoken, signIn: { throw URLError(.notConnectedToInternet) })
        _ = vm.startAppleSignInAttempt()
        await complete(vm)?.value
        #expect(vm.errorMessage != nil)
        #expect(spoken.list == ["Signing in"])
    }

    @Test func eachAttemptAnnouncesOnce() async {
        let spoken = Spoken()
        let vm = viewModel(spoken, signIn: { throw URLError(.timedOut) })
        _ = vm.startAppleSignInAttempt()
        await complete(vm)?.value
        _ = vm.startAppleSignInAttempt()
        await complete(vm)?.value
        #expect(spoken.list == ["Signing in", "Signing in"])
    }

    @Test func secondCompletionForTheSameAttempt_doesNotAnnounceAgain() async {
        let spoken = Spoken()
        let vm = viewModel(spoken)
        _ = vm.startAppleSignInAttempt()
        await complete(vm)?.value
        #expect(complete(vm) == nil)
        #expect(spoken.list == ["Signing in"])
    }

    @Test func completionWithoutAttempt_doesNotAnnounce() {
        let spoken = Spoken()
        let vm = viewModel(spoken)
        #expect(complete(vm) == nil)
        #expect(spoken.list.isEmpty)
    }

    @Test func appleCancelOrFailure_doesNotAnnounce() {
        let spoken = Spoken()
        let vm = viewModel(spoken)
        _ = vm.startAppleSignInAttempt()
        vm.handleAppleSignIn(result: .failure(ASAuthorizationError(.canceled)))
        _ = vm.startAppleSignInAttempt()
        vm.handleAppleSignIn(result: .failure(ASAuthorizationError(.failed)))
        #expect(spoken.list.isEmpty)
    }

    @Test func tryAgain_announcesOnce() async {
        let spoken = Spoken()
        let vm = viewModel(spoken)
        await vm.retrySignIn().value
        #expect(spoken.list == ["Signing in"])
        #expect(spoken.processingWhenSpoken == [true])
        #expect(!vm.isProcessing)
    }

    @Test func tryAgain_cancelledAtApple_doesNotAnnounce() async {
        let spoken = Spoken()
        let vm = viewModel(spoken, authorize: { throw ASAuthorizationError(.canceled) })
        await vm.retrySignIn().value
        #expect(spoken.list.isEmpty)
    }
}
