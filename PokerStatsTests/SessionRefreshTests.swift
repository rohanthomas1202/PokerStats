import Foundation
import Testing
@testable import PokerStats

/// In-memory stand-in for the Keychain.
private final class FakeTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [KeychainHelper.Key: String]

    init(_ values: [KeychainHelper.Key: String] = [:]) { self.values = values }

    var snapshot: [KeychainHelper.Key: String] { lock.withLock { values } }
    func read(_ key: KeychainHelper.Key) -> String? { lock.withLock { values[key] } }
    func save(_ value: String, for key: KeychainHelper.Key) throws { lock.withLock { values[key] = value } }
    func deleteAll() { lock.withLock { values.removeAll() } }
}

/// What the fake server does with the refresh request.
enum RefreshReply: Sendable {
    case status(Int, String)
    case urlError(URLError.Code)
}

/// Counts requests so tests can see the refresh actually ran.
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String] = []
    func append(_ url: String) { lock.withLock { urls.append(url) } }
    var all: [String] { lock.withLock { urls } }
}

private let userId = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

private func jwt(exp: TimeInterval) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["exp": exp])
    let base64 = payload.base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJIUzI1NiJ9.\(base64).sig"
}

private let expiredAccess = jwt(exp: 1_000)
private let freshAccess = jwt(exp: Date().timeIntervalSince1970 + 3600)

private let successBody = """
{"access_token":"\(freshAccess)","refresh_token":"new-refresh","expires_in":3600,"expires_at":null,
 "user":{"id":"\(userId.uuidString)","email":"new@example.com","identities":null}}
"""

private func signedInStore() -> FakeTokenStore {
    FakeTokenStore([
        .accessToken: expiredAccess,
        .refreshToken: "old-refresh",
        .userId: userId.uuidString,
        .userEmail: "old@example.com",
        .appleUserId: "001234.abc",
    ])
}

private func client(_ store: FakeTokenStore, reply: RefreshReply, log: RequestLog = RequestLog()) -> SupabaseClient {
    SupabaseClient(tokenStore: store) { request in
        let url = request.url!
        log.append(url.absoluteString)
        switch reply {
        case .urlError(let code):
            throw URLError(code)
        case .status(let code, let body):
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }
}

@Suite("Session Refresh Tests")
@MainActor
struct SessionRefreshTests {

    // MARK: - Classification

    @Test(arguments: [
        RefreshCase("offline", .urlError(.notConnectedToInternet), definitive: false),
        RefreshCase("timeout", .urlError(.timedOut), definitive: false),
        RefreshCase("500", .status(500, "Internal Server Error"), definitive: false),
        RefreshCase("503", .status(503, "<html>upstream</html>"), definitive: false),
        RefreshCase("400 other", .status(400, #"{"error_code":"validation_failed","msg":"bad"}"#), definitive: false),
        RefreshCase("401", .status(401, #"{"msg":"Invalid JWT"}"#), definitive: true),
        RefreshCase("400 invalid_grant", .status(400, #"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Refresh Token Not Found"}"#), definitive: true),
        RefreshCase("400 refresh_token_not_found", .status(400, #"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"#), definitive: true),
        RefreshCase("400 refresh_token_already_used", .status(400, #"{"code":400,"error_code":"refresh_token_already_used","msg":"Already Used"}"#), definitive: true),
    ])
    func refreshFailure(_ testCase: RefreshCase) async {
        let store = signedInStore()
        let before = store.snapshot
        let auth = AuthService(client: client(store, reply: testCase.reply))
        #expect(auth.restoreSession()) // expired, needs refresh
        #expect(auth.isAuthenticated)

        await auth.silentRefresh()

        if testCase.definitive {
            #expect(store.snapshot.isEmpty, "\(testCase.name): tokens cleared")
            #expect(!auth.isAuthenticated, "\(testCase.name): UI signed out")
            #expect(auth.userId == nil)
            #expect(auth.userEmail == nil)
        } else {
            #expect(store.snapshot == before, "\(testCase.name): tokens untouched")
            #expect(auth.isAuthenticated, "\(testCase.name): still signed in")
            #expect(auth.userId == userId)
            #expect(auth.userEmail == "old@example.com")
        }
    }

    @Test func success_savesNewTokens_andStaysSignedIn() async {
        let store = signedInStore()
        let log = RequestLog()
        let auth = AuthService(client: client(store, reply: .status(200, successBody), log: log))
        auth.restoreSession()

        await auth.silentRefresh()

        #expect(log.all.count == 1)
        #expect(log.all.first?.contains("/auth/v1/token?grant_type=refresh_token") == true)
        #expect(store.read(.accessToken) == freshAccess)
        #expect(store.read(.refreshToken) == "new-refresh")
        #expect(store.read(.userEmail) == "new@example.com")
        #expect(store.read(.appleUserId) == "001234.abc")
        #expect(auth.isAuthenticated)
        #expect(auth.userEmail == "new@example.com")
    }

    @Test func noRefreshToken_signsOutInOnePlace() async {
        let emptied = FakeTokenStore(signedInStore().snapshot.filter { $0.key != .refreshToken })
        let log = RequestLog()
        let auth = AuthService(client: client(emptied, reply: .status(200, successBody), log: log))
        auth.restoreSession()

        await auth.silentRefresh()

        #expect(log.all.isEmpty)
        #expect(emptied.snapshot.isEmpty)
        #expect(!auth.isAuthenticated)
    }

    // MARK: - Refresh during a normal request (e.g. a backup)

    @Test func transientRefreshDuringRequest_keepsSession_andShowsPlainCopy() async {
        let store = signedInStore()
        let before = store.snapshot
        let sut = client(store, reply: .status(500, #"{"message":"db down at 10.0.0.3"}"#))
        let auth = AuthService(client: sut)
        auth.restoreSession()

        do {
            _ = try await sut.listFiles(bucket: "backups", prefix: userId.uuidString)
            Issue.record("expected a throw")
        } catch {
            guard case SupabaseError.refreshUnavailable = error else {
                Issue.record("expected refreshUnavailable, got \(error)")
                return
            }
            let copy = error.localizedDescription
            #expect(copy == "Couldn't reach the server. Check your connection and try again.")
            #expect(!copy.contains("HTTP"))
            #expect(!copy.contains("10.0.0.3"))
        }
        #expect(store.snapshot == before)
        #expect(auth.isAuthenticated)
    }

    @Test func definitiveRefreshDuringRequest_clearsTokens_andFlipsUI() async {
        let store = signedInStore()
        let sut = client(store, reply: .status(400, #"{"error":"invalid_grant"}"#))
        let auth = AuthService(client: sut)
        auth.restoreSession()
        #expect(auth.isAuthenticated)

        do {
            _ = try await sut.listFiles(bucket: "backups", prefix: userId.uuidString)
            Issue.record("expected a throw")
        } catch {
            guard case SupabaseError.sessionExpired = error else {
                Issue.record("expected sessionExpired, got \(error)")
                return
            }
        }
        #expect(store.snapshot.isEmpty)
        #expect(!auth.isAuthenticated)
    }

    @Test func otherClientsInvalidation_doesNotSignThisServiceOut() async {
        let mine = signedInStore()
        let auth = AuthService(client: client(mine, reply: .status(200, successBody)))
        auth.restoreSession()

        let other = client(signedInStore(), reply: .status(401, "{}"))
        _ = try? await other.refreshStoredSession()

        #expect(auth.isAuthenticated)
        #expect(mine.read(.refreshToken) == "old-refresh")
    }

    @Test func freshAccessToken_restoresWithoutRefresh() {
        let store = signedInStore()
        try? store.save(freshAccess, for: .accessToken)
        let auth = AuthService(client: client(store, reply: .status(500, "")))
        #expect(!auth.restoreSession())
        #expect(auth.isAuthenticated)
    }

    @Test func noStoredTokens_restoresSignedOut() {
        let auth = AuthService(client: client(FakeTokenStore(), reply: .status(500, "")))
        #expect(!auth.restoreSession())
        #expect(!auth.isAuthenticated)
    }

    // MARK: - Classifier directly

    @Test func classifier_onlyAcceptsAuthErrors() {
        #expect(SessionRefresher.isDefinitiveAuthFailure(SupabaseError.httpError(statusCode: 401, message: "")))
        #expect(SessionRefresher.isDefinitiveAuthFailure(SupabaseError.httpError(statusCode: 400, message: #"{"error":"invalid_grant"}"#)))
        #expect(!SessionRefresher.isDefinitiveAuthFailure(SupabaseError.httpError(statusCode: 400, message: "invalid_grant but not JSON")))
        #expect(!SessionRefresher.isDefinitiveAuthFailure(SupabaseError.httpError(statusCode: 502, message: #"{"error":"invalid_grant"}"#)))
        #expect(!SessionRefresher.isDefinitiveAuthFailure(SupabaseError.networkError("offline")))
        #expect(!SessionRefresher.isDefinitiveAuthFailure(URLError(.timedOut)))
    }
}

struct RefreshCase: Sendable, CustomTestStringConvertible {
    let name: String
    let reply: RefreshReply
    let definitive: Bool

    init(_ name: String, _ reply: RefreshReply, definitive: Bool) {
        self.name = name
        self.reply = reply
        self.definitive = definitive
    }

    var testDescription: String { name }
}
