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

    @Test func requestBody_usesSnakeCaseKey() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(DeleteAccountRequest(authorizationCode: "c"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json == ["authorization_code": "c"])
    }
}
