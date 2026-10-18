import Foundation
import Testing
@testable import PokerStats

private struct FunctionFailed: Error {}

@MainActor
private final class Recorder {
    var reauthCalls = 0
    var requests: [DeleteAccountRequest] = []
}

@Suite("Account Deleter Tests")
@MainActor
struct AccountDeleterTests {

    /// `appleUserId` stands in for the Keychain read, so no Keychain is touched.
    private func deleter(
        appleUserId: String?,
        recorder: Recorder,
        reauth: @escaping @MainActor () async throws -> String = { "fresh-code" },
        function: @escaping @MainActor (DeleteAccountRequest) async throws -> Void = { _ in }
    ) -> AccountDeleter {
        AccountDeleter(
            appleUserId: { appleUserId },
            appleAuthorizationCode: {
                recorder.reauthCalls += 1
                return try await reauth()
            },
            callDeleteFunction: { request in
                recorder.requests.append(request)
                try await function(request)
            }
        )
    }

    @Test func appleUser_reauthenticates_andSendsFreshCode() async throws {
        let recorder = Recorder()
        try await deleter(appleUserId: "001234.abc", recorder: recorder).run()
        #expect(recorder.reauthCalls == 1)
        #expect(recorder.requests == [DeleteAccountRequest(authorizationCode: "fresh-code")])
    }

    @Test func appleUser_cancelledReauth_doesNotCallFunction() async {
        let recorder = Recorder()
        let sut = deleter(
            appleUserId: "001234.abc",
            recorder: recorder,
            reauth: { throw AccountDeletionError.reauthenticationCancelled }
        )
        await #expect(throws: AccountDeletionError.reauthenticationCancelled) { try await sut.run() }
        #expect(recorder.requests.isEmpty)
    }

    @Test func nonAppleUser_skipsReauth_andSendsNoCode() async throws {
        let recorder = Recorder()
        try await deleter(appleUserId: nil, recorder: recorder).run()
        #expect(recorder.reauthCalls == 0)
        #expect(recorder.requests == [DeleteAccountRequest(authorizationCode: nil)])
    }

    @Test func functionFailure_propagates() async {
        let recorder = Recorder()
        let sut = deleter(
            appleUserId: "001234.abc",
            recorder: recorder,
            function: { _ in throw FunctionFailed() }
        )
        await #expect(throws: FunctionFailed.self) { try await sut.run() }
        #expect(recorder.requests.count == 1)
    }

    // MARK: - Server says the account is Apple-linked

    private let reauthRequired = SupabaseError.httpError(
        statusCode: 400,
        message: #"{"error":"Apple re-authentication required","code":"apple_reauth_required","step":"revoke apple token","retryable":true}"#
    )

    @Test func noKeychainAppleId_serverAsksForCode_reauthenticatesAndRetriesOnce() async throws {
        let recorder = Recorder()
        let error = reauthRequired
        let sut = deleter(
            appleUserId: nil,
            recorder: recorder,
            function: { request in
                if request.authorizationCode == nil { throw error }
            }
        )
        try await sut.run()
        #expect(recorder.reauthCalls == 1)
        #expect(recorder.requests == [
            DeleteAccountRequest(authorizationCode: nil),
            DeleteAccountRequest(authorizationCode: "fresh-code"),
        ])
    }

    @Test func serverAsksForCodeAgainAfterRetry_errorPropagates() async {
        let recorder = Recorder()
        let error = reauthRequired
        let sut = deleter(appleUserId: nil, recorder: recorder, function: { _ in throw error })
        await #expect(throws: SupabaseError.self) { try await sut.run() }
        #expect(recorder.reauthCalls == 1)
        #expect(recorder.requests.count == 2)
    }

    @Test func serverAsksForCode_userCancels_noRetry() async {
        let recorder = Recorder()
        let error = reauthRequired
        let sut = deleter(
            appleUserId: nil,
            recorder: recorder,
            reauth: { throw AccountDeletionError.reauthenticationCancelled },
            function: { _ in throw error }
        )
        await #expect(throws: AccountDeletionError.reauthenticationCancelled) { try await sut.run() }
        #expect(recorder.requests.count == 1)
    }

    @Test func otherServerErrors_doNotTriggerReauth() async {
        let recorder = Recorder()
        let sut = deleter(
            appleUserId: nil,
            recorder: recorder,
            function: { _ in
                throw SupabaseError.httpError(statusCode: 500, message: #"{"error":"Account deletion failed","step":"revoke apple token","retryable":true}"#)
            }
        )
        await #expect(throws: SupabaseError.self) { try await sut.run() }
        #expect(recorder.reauthCalls == 0)
        #expect(recorder.requests.count == 1)
    }

    @Test func isAppleReauthRequired_matchesOnlyThat400() {
        #expect(AccountDeleter.isAppleReauthRequired(reauthRequired))
        #expect(!AccountDeleter.isAppleReauthRequired(SupabaseError.httpError(statusCode: 401, message: "apple_reauth_required")))
        #expect(!AccountDeleter.isAppleReauthRequired(SupabaseError.httpError(statusCode: 400, message: "bad request")))
        #expect(!AccountDeleter.isAppleReauthRequired(FunctionFailed()))
    }

    // MARK: - The request SupabaseClient actually sends

    @Test func supabaseClient_deleteAccountRequest_body() throws {
        let request = try SupabaseClient().makeEdgeFunctionRequest(
            "delete-account",
            accessToken: "jwt",
            body: DeleteAccountRequest(authorizationCode: "c")
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path().hasSuffix("/functions/v1/delete-account") == true)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["authorization_code": "c"])
    }

    @Test func supabaseClient_deleteAccountRequest_withoutCode_sendsEmptyObject() throws {
        let request = try SupabaseClient().makeEdgeFunctionRequest(
            "delete-account",
            accessToken: "jwt",
            body: DeleteAccountRequest(authorizationCode: nil)
        )
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json.isEmpty)
    }
}
