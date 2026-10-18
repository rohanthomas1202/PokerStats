import AuthenticationServices
import Foundation
import Testing
@testable import PokerStats

private struct SignInFailed: LocalizedError {
    var errorDescription: String? { "Supabase said no" }
}

@MainActor
private final class SignInRecorder {
    var credentials: [AuthViewModel.AppleSignInCredential] = []
}

@Suite("Sign In Nonce Tests")
@MainActor
struct SignInNonceTests {

    // MARK: - Nonce generation and hashing

    @Test func rawNonce_defaultLength_isThirtyTwo() {
        #expect(SignInNonce().raw.count == 32)
        #expect(SignInNonce(length: 64).raw.count == 64)
    }

    @Test func rawNonce_usesOnlyTheCharset() {
        let allowed = Set(SignInNonce.charset)
        for _ in 0..<200 {
            #expect(SignInNonce().raw.allSatisfy(allowed.contains))
        }
        #expect(SignInNonce.charset.count == 65)
    }

    @Test func rawNonce_isUniqueAcrossAttempts() {
        let nonces = Set((0..<1000).map { _ in SignInNonce().raw })
        #expect(nonces.count == 1000)
    }

    @Test func sha256Hex_matchesKnownVectors() {
        #expect(SignInNonce.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SignInNonce.sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func hashed_isLowercaseHexSHA256OfRaw() {
        let nonce = SignInNonce()
        #expect(nonce.hashed == SignInNonce.sha256Hex(nonce.raw))
        #expect(nonce.hashed.count == 64)
        #expect(nonce.hashed.allSatisfy { "0123456789abcdef".contains($0) })
    }

    // MARK: - Request Supabase receives

    @Test func supabaseClient_idTokenRequest_carriesRawNonce() throws {
        let request = try SupabaseClient().makeSignInWithIdTokenRequest(
            provider: .apple,
            idToken: "id.token.jwt",
            nonce: "raw-nonce"
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path().hasSuffix("/auth/v1/token") == true)
        #expect(request.url?.query() == "grant_type=id_token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["provider": "apple", "id_token": "id.token.jwt", "nonce": "raw-nonce"])
    }

    // MARK: - View model: Apple gets the hash, Supabase the raw value

    private func viewModel(
        _ recorder: SignInRecorder,
        perform: @escaping @MainActor () async throws -> Void = {}
    ) -> AuthViewModel {
        AuthViewModel(
            authService: AuthService(),
            performDeleteAccount: {},
            performAppleSignIn: { credential in
                recorder.credentials.append(credential)
                try await perform()
            }
        )
    }

    private func complete(_ vm: AuthViewModel) -> Task<Void, Never>? {
        vm.completeAppleSignIn(
            identityToken: Data("id-token".utf8),
            authorizationCode: Data("code".utf8),
            fullName: nil,
            appleUserId: "001234.abc"
        )
    }

    @Test func configureAppleRequest_setsScopesAndHashedNonce() async throws {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        vm.configureAppleRequest(request)
        #expect(request.requestedScopes == [.email, .fullName])
        let hashed = try #require(request.nonce)
        #expect(hashed.count == 64)

        await complete(vm)?.value
        let sent = try #require(recorder.credentials.first)
        #expect(sent.rawNonce != hashed)
        #expect(SignInNonce.sha256Hex(sent.rawNonce) == hashed)
    }

    @Test func supabaseGetsRawNonceMatchingHashSentToApple() async throws {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        vm.isShowingSignIn = true
        let hashed = vm.startAppleSignInAttempt()

        await complete(vm)?.value
        #expect(recorder.credentials.count == 1)
        let sent = try #require(recorder.credentials.first)
        #expect(SignInNonce.sha256Hex(sent.rawNonce) == hashed)
        #expect(sent.identityToken == Data("id-token".utf8))
        #expect(sent.appleUserId == "001234.abc")
        #expect(!vm.isShowingSignIn)
        #expect(!vm.isProcessing)
        #expect(vm.errorMessage == nil)
    }

    @Test func eachAttemptGetsAFreshNonce_andTheLatestOneIsUsed() async throws {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        let first = vm.startAppleSignInAttempt()
        let second = vm.startAppleSignInAttempt()
        #expect(first != second)

        await complete(vm)?.value
        let sent = try #require(recorder.credentials.first)
        #expect(SignInNonce.sha256Hex(sent.rawNonce) == second)
    }

    @Test func nonceIsSingleUse() async {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        _ = vm.startAppleSignInAttempt()
        await complete(vm)?.value
        #expect(recorder.credentials.count == 1)

        #expect(complete(vm) == nil)
        #expect(recorder.credentials.count == 1)
        #expect(vm.errorMessage == "Sign-in didn't finish. Please try again.")
    }

    @Test func completionWithoutAttempt_doesNotCallSupabase() {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        #expect(complete(vm) == nil)
        #expect(recorder.credentials.isEmpty)
        #expect(!vm.isProcessing)
        #expect(vm.errorMessage == "Sign-in didn't finish. Please try again.")
    }

    @Test func appleFailure_discardsNonce() {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        _ = vm.startAppleSignInAttempt()
        vm.handleAppleSignIn(result: .failure(ASAuthorizationError(.canceled)))
        #expect(vm.errorMessage == nil) // cancel is not an error
        #expect(complete(vm) == nil)
        #expect(recorder.credentials.isEmpty)
    }

    @Test func supabaseFailure_showsError_andNonceIsNotReused() async {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder) { throw SignInFailed() }
        vm.isShowingSignIn = true
        _ = vm.startAppleSignInAttempt()
        await complete(vm)?.value
        #expect(vm.errorMessage == "Couldn't sign in with Apple. Please try again.")
        #expect(vm.isShowingSignIn)
        #expect(!vm.isProcessing)
        #expect(complete(vm) == nil)
        #expect(recorder.credentials.count == 1)
    }

    @Test func supabaseHTTPError_showsFixedCopy_notServerText() async {
        let recorder = SignInRecorder()
        let serverText = #"{"code":400,"error_code":"bad_jwt","msg":"Nonces mismatch"}"#
        let vm = viewModel(recorder) {
            throw SupabaseError.httpError(statusCode: 400, message: serverText)
        }
        _ = vm.startAppleSignInAttempt()
        await complete(vm)?.value
        let shown = vm.errorMessage ?? ""
        #expect(shown == "Couldn't sign in with Apple. Please try again.")
        #expect(!shown.contains("HTTP"))
        #expect(!shown.contains("Nonces mismatch"))
    }

    @Test func appleNonCancelFailure_showsFixedCopy_andDiscardsNonce() {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        _ = vm.startAppleSignInAttempt()
        vm.handleAppleSignIn(result: .failure(ASAuthorizationError(.failed)))
        #expect(vm.errorMessage == "Couldn't sign in with Apple. Please try again.")
        #expect(complete(vm) == nil)
        #expect(recorder.credentials.isEmpty)
    }

    @Test func newAttempt_clearsPreviousError() {
        let recorder = SignInRecorder()
        let vm = viewModel(recorder)
        #expect(complete(vm) == nil)
        #expect(vm.errorMessage != nil)
        _ = vm.startAppleSignInAttempt()
        #expect(vm.errorMessage == nil)
    }
}
