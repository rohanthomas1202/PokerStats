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
        message: #"{"error":"Apple re-authentication required","code":"apple_reauth_required","step":"apple reauth","retryable":false}"#
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

    private func functionsClient(
        _ server: FakeServer,
        reply: FakeReply = .status(200, #"{"ok":true}"#)
    ) -> SupabaseClient {
        let storage = InMemoryAuthStorage()
        storage.seed(testSession(accessToken: "jwt", expired: false))
        return testClient(storage, server: server) { _, _ in reply }
    }

    @Test func supabaseClient_deleteAccountRequest_body() async throws {
        let server = FakeServer()
        try await functionsClient(server).callEdgeFunction(
            "delete-account",
            body: DeleteAccountRequest(authorizationCode: "c")
        )
        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == "POST")
        #expect(request.path.hasSuffix("/functions/v1/delete-account"))
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Authorization"] == "Bearer jwt")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["authorization_code": "c"])
    }

    @Test func supabaseClient_deleteAccountRequest_withoutCode_sendsEmptyObject() async throws {
        let server = FakeServer()
        try await functionsClient(server).callEdgeFunction(
            "delete-account",
            body: DeleteAccountRequest(authorizationCode: nil)
        )
        let body = try #require(server.requests.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json.isEmpty)
    }

    @Test func supabaseClient_edgeFunctionError_keepsStatusAndBody() async {
        let server = FakeServer()
        let errorBody = #"{"error":"apple_reauth_required"}"#
        do {
            try await functionsClient(server, reply: .status(409, errorBody)).callEdgeFunction(
                "delete-account",
                body: DeleteAccountRequest(authorizationCode: nil)
            )
            Issue.record("expected a throw")
        } catch {
            guard case SupabaseError.httpError(let status, let message) = error else {
                Issue.record("expected httpError, got \(error)")
                return
            }
            #expect(status == 409)
            #expect(message == errorBody)
        }
    }

    // MARK: - Apple revoked, then cleanup failed

    @Test func cleanupFailureAfterRevoke_mapsToAppleDisconnectedError() async {
        let recorder = Recorder()
        let sut = deleter(
            appleUserId: "001234.abc",
            recorder: recorder,
            function: { _ in
                throw SupabaseError.httpError(
                    statusCode: 500,
                    message: #"{"error":"Account deletion failed","step":"delete backup_metadata","retryable":true,"apple_revoked":true}"#
                )
            }
        )
        await #expect(throws: AccountDeletionError.cleanupFailedAfterAppleRevoke) { try await sut.run() }
    }

    @Test func revokeFailure_isNotAppleDisconnected() async {
        let recorder = Recorder()
        let sut = deleter(
            appleUserId: "001234.abc",
            recorder: recorder,
            function: { _ in
                throw SupabaseError.httpError(
                    statusCode: 500,
                    message: #"{"error":"Account deletion failed","step":"revoke apple token","retryable":true}"#
                )
            }
        )
        await #expect(throws: SupabaseError.self) { try await sut.run() }
    }

    // MARK: - Failure codes (#42, PR #96)

    private func failure(_ status: Int, _ code: String, retryable: Bool) -> SupabaseError {
        .httpError(
            statusCode: status,
            message: #"{"error":"x","code":"\#(code)","step":"s","retryable":\#(retryable)}"#
        )
    }

    /// Runs a deleter whose every call fails with `error`, and returns what `run()` threw.
    private func thrown(by error: Error, appleUserId: String? = "001234.abc") async -> (Error?, Recorder) {
        let recorder = Recorder()
        let sut = deleter(appleUserId: appleUserId, recorder: recorder, function: { _ in throw error })
        do {
            try await sut.run()
            return (nil, recorder)
        } catch {
            return (error, recorder)
        }
    }

    @Test func appleAccountMismatch_mapsToMismatch() async {
        let (error, recorder) = await thrown(by: failure(422, "apple_account_mismatch", retryable: false))
        #expect(error as? AccountDeletionError == .appleAccountMismatch)
        #expect(recorder.requests.count == 1)
    }

    @Test func appleIdentityMissing_mapsToNeedsSupport_evenWithoutCode() async {
        let (error, recorder) = await thrown(by: failure(422, "apple_identity_missing", retryable: false), appleUserId: nil)
        #expect(error as? AccountDeletionError == .needsSupport)
        #expect(recorder.reauthCalls == 0)
        #expect(recorder.requests == [DeleteAccountRequest(authorizationCode: nil)])
    }

    @Test func appleTokenInvalid_mapsToNeedsSupport() async {
        let (error, _) = await thrown(by: failure(422, "apple_token_invalid", retryable: false))
        #expect(error as? AccountDeletionError == .needsSupport)
    }

    @Test func serverNotConfigured_mapsToTemporarilyUnavailable_withoutAutoRetry() async {
        let (error, recorder) = await thrown(by: failure(503, "server_not_configured", retryable: true), appleUserId: nil)
        #expect(error as? AccountDeletionError == .temporarilyUnavailable)
        #expect(recorder.reauthCalls == 0)
        #expect(recorder.requests.count == 1)
    }

    @Test func deleteFailed_staysGenericRetryable() async {
        let (error, _) = await thrown(by: failure(500, "delete_failed", retryable: true))
        #expect(error is SupabaseError)
    }

    @Test func reauthRequiredAfterCodeSent_staysGenericRetryable() async {
        let (error, recorder) = await thrown(by: reauthRequired)
        #expect(error is SupabaseError)
        #expect(recorder.reauthCalls == 1)
        #expect(recorder.requests.count == 1)
    }

    @Test func unknownCode_fallsBackToRetryable() async {
        let (notRetryable, _) = await thrown(by: failure(409, "something_new", retryable: false))
        #expect(notRetryable as? AccountDeletionError == .needsSupport)
        let (retryable, _) = await thrown(by: failure(409, "something_new", retryable: true))
        #expect(retryable is SupabaseError)
    }

    @Test func unparseableOrMissingRetryable_isGenericRetryable() async {
        let (html, _) = await thrown(by: SupabaseError.httpError(statusCode: 502, message: "<html>Bad Gateway</html>"))
        #expect(html is SupabaseError)
        let (noFields, _) = await thrown(by: SupabaseError.httpError(statusCode: 500, message: #"{"error":"x"}"#))
        #expect(noFields is SupabaseError)
        let (network, _) = await thrown(by: FunctionFailed())
        #expect(network is FunctionFailed)
    }

    @Test func appleRevoked_winsOverCode() async {
        let error = SupabaseError.httpError(
            statusCode: 500,
            message: #"{"error":"x","code":"delete_failed","step":"delete profiles","retryable":true,"apple_revoked":true}"#
        )
        let (thrownError, _) = await thrown(by: error, appleUserId: nil)
        #expect(thrownError as? AccountDeletionError == .cleanupFailedAfterAppleRevoke)
    }

    @Test func appleRevoked_keptWhenOtherFieldsHaveUnexpectedTypes() async {
        let error = SupabaseError.httpError(
            statusCode: 500,
            message: #"{"error":"x","code":42,"step":["s"],"retryable":"true","apple_revoked":true}"#
        )
        let (thrownError, _) = await thrown(by: error, appleUserId: nil)
        #expect(thrownError as? AccountDeletionError == .cleanupFailedAfterAppleRevoke)
    }

    @Test func failureBody_badlyTypedField_isNil_othersKept() throws {
        let body = try #require(DeleteAccountFailureBody.from(SupabaseError.httpError(
            statusCode: 422,
            message: #"{"code":"apple_account_mismatch","retryable":"no","apple_revoked":"yes"}"#
        ))?.body)
        #expect(body.code == "apple_account_mismatch")
        #expect(body.retryable == nil)
        #expect(body.appleRevoked == nil)
    }
}
