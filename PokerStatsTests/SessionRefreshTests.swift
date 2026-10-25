import Auth
import Foundation
import Testing
@testable import PokerStats

private let refreshTokenNotFound = #"{"code":"refresh_token_not_found","message":"Invalid Refresh Token: Refresh Token Not Found"}"#

/// Answers every request with `reply`, except sign-out, which succeeds.
private func client(
    _ storage: InMemoryAuthStorage,
    reply: FakeReply,
    server: FakeServer = FakeServer(),
    log: AuthLog? = nil
) -> SupabaseClient {
    testClient(storage, server: server, log: log) { request, _ in
        if request.path.hasSuffix("/auth/v1/logout") { return .status(204, "") }
        return reply
    }
}

private func signedInStorage(expired: Bool = true) -> InMemoryAuthStorage {
    let storage = InMemoryAuthStorage()
    storage.seed(testSession(expired: expired))
    return storage
}

/// Starts following auth events and waits for the initial session event,
/// which the SDK sends once the listener is registered. Call it instead of
/// `restoreSession()` for a stored session that hasn't expired.
@MainActor
private func observe(_ auth: AuthService) async {
    auth.observeAuthChanges()
    await waitUntil("initial session") { auth.isAuthenticated }
}

/// Auth events one client's stream has delivered, in order.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [AuthChangeEvent] = []

    var events: [AuthChangeEvent] { lock.withLock { seen } }
    func append(_ event: AuthChangeEvent) { lock.withLock { seen.append(event) } }
}

@Suite("Session Refresh Tests")
@MainActor
struct SessionRefreshTests {

    // MARK: - Refresh at launch

    /// An expired stored session is refreshed when the app starts following
    /// auth events. Only a rejected refresh token or a missing session signs
    /// out; offline, timeouts, 5xx and other 4xx/401 bodies (gateway or API
    /// key errors) keep the session (#47, #58).
    @Test(arguments: [
        RefreshCase("offline", .urlError(.notConnectedToInternet), definitive: false, attempts: 2),
        RefreshCase("timeout", .urlError(.timedOut), definitive: false, attempts: 2),
        RefreshCase("500", .status(500, "Internal Server Error"), definitive: false, attempts: 2),
        RefreshCase("503", .status(503, "<html>upstream</html>"), definitive: false, attempts: 2),
        RefreshCase("400 other", .status(400, #"{"code":"validation_failed","message":"bad"}"#), definitive: false),
        RefreshCase("401 gateway", .status(401, #"{"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}"#), definitive: false),
        RefreshCase("401 invalid JWT", .status(401, #"{"msg":"Invalid JWT"}"#), definitive: false),
        RefreshCase("401 no body", .status(401, ""), definitive: false),
        // Without an error code the SDK can't tell this is about the refresh
        // token, so it keeps the session at launch; Supabase Auth sends the
        // code. The next request signs out (accountRejectedDuringRequest).
        RefreshCase("400 invalid_grant without code", .status(400, #"{"error":"invalid_grant","error_description":"Invalid Refresh Token"}"#), definitive: false),
        RefreshCase("400 refresh_token_not_found", .status(400, refreshTokenNotFound), definitive: true),
        RefreshCase("400 refresh_token_already_used", .status(400, #"{"code":"refresh_token_already_used","message":"Invalid Refresh Token: Already Used"}"#), definitive: true),
        RefreshCase("401 refresh_token_not_found", .status(401, #"{"code":"refresh_token_not_found","message":"Invalid Refresh Token"}"#), definitive: true),
        RefreshCase("403 session_not_found", .status(403, #"{"code":"session_not_found","message":"Session from session_id claim in JWT does not exist"}"#), definitive: true),
    ])
    func refreshFailure(_ testCase: RefreshCase) async {
        let storage = signedInStorage()
        let server = FakeServer()
        let log = AuthLog()
        let auth = AuthService(client: client(storage, reply: testCase.reply, server: server, log: log))
        #expect(auth.restoreSession()) // expired, needs refresh
        #expect(auth.isAuthenticated)

        auth.observeAuthChanges()
        await waitUntil("\(testCase.name): refresh finished") { log.count(AuthLog.refreshEnded) == 1 }

        if testCase.definitive {
            await waitUntil("\(testCase.name): UI signed out") { !auth.isAuthenticated }
            #expect(storage.storedSession == nil, "\(testCase.name): session removed")
            #expect(auth.userId == nil)
            #expect(auth.userEmail == nil)
        } else {
            #expect(storage.storedSession?.refreshToken == "old-refresh", "\(testCase.name): session kept")
            #expect(auth.isAuthenticated, "\(testCase.name): still signed in")
            #expect(auth.userId == TestUser.id)
            #expect(auth.userEmail == "old@example.com")
        }
        #expect(server.refreshCount == testCase.attempts)
    }

    @Test func expiredSessionAtLaunch_isRefreshed_andStaysSignedIn() async {
        let storage = signedInStorage()
        let server = FakeServer()
        let auth = AuthService(client: client(storage, reply: .status(200, sessionResponseBody()), server: server))
        #expect(auth.restoreSession())

        auth.observeAuthChanges()
        await waitUntil("refreshed email shown") { auth.userEmail == "new@example.com" }

        let request = server.requests.first
        #expect(server.requests.count == 1)
        #expect(request?.isRefresh == true)
        #expect(request?.json?["refresh_token"] as? String == "old-refresh")
        #expect(storage.storedSession?.accessToken == "new-access")
        #expect(storage.storedSession?.refreshToken == "new-refresh")
        #expect(auth.isAuthenticated)
        #expect(auth.appleUserId == TestUser.appleUserId)
    }

    @Test func success_savesNewSession_andStaysSignedIn() async throws {
        let storage = signedInStorage(expired: false)
        let server = FakeServer()
        let sut = client(storage, reply: .status(200, sessionResponseBody()), server: server)
        let auth = AuthService(client: sut)
        await observe(auth)

        let session = try await sut.auth.refreshSession()

        #expect(session.refreshToken == "new-refresh")
        #expect(server.requests.count == 1)
        #expect(server.requests.first?.isRefresh == true)
        #expect(storage.storedSession?.accessToken == "new-access")
        #expect(storage.storedSession?.refreshToken == "new-refresh")
        await waitUntil("new email shown") { auth.userEmail == "new@example.com" }
        #expect(auth.isAuthenticated)
        #expect(auth.appleUserId == TestUser.appleUserId)
    }

    @Test func noStoredSession_restoresSignedOut_andSendsNothing() async {
        let server = FakeServer()
        let sut = client(InMemoryAuthStorage(), reply: .status(200, sessionResponseBody()), server: server)
        let auth = AuthService(client: sut)
        #expect(!auth.restoreSession())
        #expect(!auth.isAuthenticated)

        do {
            _ = try await SupabaseClient.accessToken(sut.auth)
            Issue.record("expected a throw")
        } catch {
            guard case SupabaseError.sessionExpired = error else {
                Issue.record("expected sessionExpired, got \(error)")
                return
            }
        }
        #expect(server.requests.isEmpty)
        #expect(!auth.isAuthenticated)
    }

    @Test func freshSession_restoresWithoutRefresh_andSendsStoredToken() async throws {
        // Expiry comes from the session's expires_at, not a decoded JWT (#57).
        let storage = InMemoryAuthStorage()
        storage.seed(testSession(accessToken: "fresh-access", expired: false))
        let server = FakeServer()
        let sut = testClient(storage, server: server) { _, _ in .status(200, "[]") }
        let auth = AuthService(client: sut)
        #expect(!auth.restoreSession())
        #expect(auth.isAuthenticated)

        _ = try await sut.storage.from("backups").list(path: TestUser.id.uuidString)

        #expect(server.refreshCount == 0)
        #expect(server.requests.count == 1)
        #expect(server.requests.first?.headers["Authorization"] == "Bearer fresh-access")
        #expect(server.requests.first?.headers["apikey"] == "anon-key")
    }

    // MARK: - Refresh during a normal request (e.g. a backup)

    @Test func transientRefreshDuringRequest_keepsSession_andShowsPlainCopy() async {
        let storage = signedInStorage()
        let server = FakeServer()
        let sut = client(storage, reply: .status(500, #"{"message":"db down at 10.0.0.3"}"#), server: server)
        let auth = AuthService(client: sut)
        auth.restoreSession()

        do {
            _ = try await sut.storage.from("backups").list(path: TestUser.id.uuidString)
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
        let onlyRefreshes = server.requests.allSatisfy { $0.isRefresh }
        #expect(onlyRefreshes, "the storage request is not sent")
        #expect(storage.storedSession?.refreshToken == "old-refresh")
        #expect(auth.isAuthenticated)
    }

    @Test func definitiveRefreshDuringRequest_clearsSession_andFlipsUI() async {
        let storage = signedInStorage(expired: false)
        let sut = client(storage, reply: .status(400, refreshTokenNotFound))
        let auth = AuthService(client: sut)
        await observe(auth)

        // The access token expires while the app is running.
        storage.seed(testSession(expired: true))
        do {
            _ = try await sut.storage.from("backups").list(path: TestUser.id.uuidString)
            Issue.record("expected a throw")
        } catch {
            guard case SupabaseError.sessionExpired = error else {
                Issue.record("expected sessionExpired, got \(error)")
                return
            }
        }
        #expect(storage.storedSession == nil)
        await waitUntil("UI signed out") { !auth.isAuthenticated }
    }

    @Test func otherClientsInvalidation_doesNotSignThisServiceOut() async throws {
        let mine = signedInStorage(expired: false)
        let mineClient = client(mine, reply: .status(200, sessionResponseBody()))
        let auth = AuthService(client: mineClient)
        await observe(auth)
        let events = EventLog()
        let probe = Task {
            for await (event, _) in mineClient.auth.authStateChanges { events.append(event) }
        }
        defer { probe.cancel() }
        await waitUntil("probe listening") { events.events.contains(.initialSession) }

        let other = client(signedInStorage(), reply: .status(400, refreshTokenNotFound))
        _ = try? await other.auth.refreshSession()
        #expect(other.auth.currentSession == nil, "the other client signed out")
        #expect(mine.storedSession?.refreshToken == "old-refresh")

        // Events arrive in order: once this client's own refresh shows up, a
        // sign-out sent before it would already be in the log.
        _ = try await mineClient.auth.refreshSession()
        await waitUntil("own refresh seen") { events.events.contains(.tokenRefreshed) }
        #expect(!events.events.contains(.signedOut))
        await waitUntil("own refresh shown") { auth.userEmail == "new@example.com" }
        #expect(auth.isAuthenticated)
    }

    /// The SDK keeps the session for a banned or deleted user and for an
    /// `invalid_grant` without a code; a request signs out locally instead
    /// of showing "Couldn't reach the server" while still signed in (#133).
    @Test(arguments: [
        ("403 user_banned", #"{"code":"user_banned","message":"User is banned"}"#, 403),
        ("404 user_not_found", #"{"code":"user_not_found","message":"User not found"}"#, 404),
        ("400 invalid_grant without code", #"{"error":"invalid_grant","error_description":"Invalid Refresh Token"}"#, 400),
    ])
    func accountRejectedDuringRequest_signsOut(name: String, body: String, status: Int) async {
        let storage = signedInStorage(expired: false)
        let server = FakeServer()
        let sut = client(storage, reply: .status(status, body), server: server)
        let auth = AuthService(client: sut)
        await observe(auth)

        // The access token expires while the app is running.
        storage.seed(testSession(expired: true))
        do {
            _ = try await sut.storage.from("backups").list(path: TestUser.id.uuidString)
            Issue.record("\(name): expected a throw")
        } catch {
            guard case SupabaseError.sessionExpired = error else {
                Issue.record("\(name): expected sessionExpired, got \(error)")
                return
            }
        }
        #expect(storage.storedSession == nil, "\(name): session removed")
        #expect(server.refreshCount == 1)
        #expect(!server.requests.contains { $0.path.contains("/storage/") }, "\(name): the storage request is not sent")
        await waitUntil("\(name): UI signed out") { !auth.isAuthenticated }
        #expect(auth.userId == nil)
    }

    @Test func otherCodesDuringRequest_keepSession() async {
        let storage = signedInStorage()
        let sut = client(storage, reply: .status(400, #"{"code":"validation_failed","message":"bad"}"#))
        let auth = AuthService(client: sut)
        auth.restoreSession()

        do {
            _ = try await SupabaseClient.accessToken(sut.auth)
            Issue.record("expected a throw")
        } catch {
            guard case SupabaseError.refreshUnavailable = error else {
                Issue.record("expected refreshUnavailable, got \(error)")
                return
            }
        }
        #expect(storage.storedSession?.refreshToken == "old-refresh")
        #expect(auth.isAuthenticated)
    }

    // MARK: - Single-flight refresh

    @Test func concurrentRefreshes_shareOneRequest_andStaySignedIn() async throws {
        let storage = signedInStorage()
        let server = FakeServer()
        let gate = TransportGate()
        let log = AuthLog()
        let sut = testClient(storage, server: server, log: log) { _, index in
            if index == 0 { await gate.wait() }
            return .status(200, sessionResponseBody())
        }
        let auth = AuthService(client: sut)
        auth.restoreSession()

        let first = Task { try await SupabaseClient.accessToken(sut.auth) }
        await waitUntil("first refresh sent") { server.refreshCount == 1 }
        let second = Task { try await SupabaseClient.accessToken(sut.auth) }
        await waitUntil("second caller joined the flight") { log.count(AuthLog.joinedRefresh) == 1 }
        gate.open()

        let tokens = try await [first.value, second.value]

        #expect(server.requests.count == 1, "one token request for two callers")
        #expect(tokens == ["new-access", "new-access"])
        #expect(storage.storedSession?.refreshToken == "new-refresh")
        #expect(auth.isAuthenticated)
        #expect(auth.userId == TestUser.id)
    }

    @Test func failedSharedRefresh_reachesEveryWaiter_thenNextCallRetries() async throws {
        let storage = signedInStorage()
        let server = FakeServer()
        let gate = TransportGate()
        let log = AuthLog()
        // The SDK retries a 503 once inside the same flight: requests 0 and 1.
        let sut = testClient(storage, server: server, log: log) { _, index in
            if index == 0 { await gate.wait() }
            return index < 2 ? .status(503, "upstream") : .status(200, sessionResponseBody())
        }
        let auth = AuthService(client: sut)
        auth.restoreSession()

        let first = Task { try await SupabaseClient.accessToken(sut.auth) }
        await waitUntil("first refresh sent") { server.refreshCount == 1 }
        let second = Task { try await SupabaseClient.accessToken(sut.auth) }
        await waitUntil("second caller joined the flight") { log.count(AuthLog.joinedRefresh) == 1 }
        gate.open()

        for caller in [first, second] {
            do {
                _ = try await caller.value
                Issue.record("expected a throw")
            } catch {
                guard case SupabaseError.refreshUnavailable = error else {
                    Issue.record("expected refreshUnavailable, got \(error)")
                    continue
                }
            }
        }
        #expect(server.requests.count == 2, "one flight (with its retry) for two callers")
        #expect(storage.storedSession?.refreshToken == "old-refresh", "transient failure keeps the session")
        #expect(auth.isAuthenticated)

        // The failed flight is not reused: the next call sends a new request.
        let token = try await SupabaseClient.accessToken(sut.auth)
        #expect(server.requests.count == 3)
        #expect(token == "new-access")
        #expect(storage.storedSession?.refreshToken == "new-refresh")
        #expect(auth.isAuthenticated)
    }

    // MARK: - Sign-out or sign-in while a refresh is in flight (#58)

    @Test func signOutDuringRefresh_discardsTheRefreshedSession() async {
        let storage = signedInStorage()
        let server = FakeServer()
        let gate = TransportGate()
        let log = AuthLog()
        let sut = testClient(storage, server: server, log: log) { request, _ in
            if request.path.hasSuffix("/auth/v1/logout") { return .status(204, "") }
            await gate.wait()
            return .status(200, sessionResponseBody())
        }
        let auth = AuthService(client: sut)
        auth.restoreSession()
        auth.observeAuthChanges() // starts the launch refresh
        await waitUntil("refresh sent") { server.refreshCount == 1 }

        await auth.signOut()
        #expect(!auth.isAuthenticated)
        gate.open()
        await waitUntil("refresh finished") { log.count(AuthLog.refreshEnded) == 1 }

        #expect(storage.storedSession == nil, "the refreshed session is not stored")
        #expect(!auth.isAuthenticated)
        #expect(auth.userEmail == nil)
    }

    @Test func signOutDuringRequestRefresh_failsWithSessionChanged() async {
        let storage = signedInStorage()
        let server = FakeServer()
        let gate = TransportGate()
        let sut = testClient(storage, server: server) { request, _ in
            if request.path.hasSuffix("/auth/v1/logout") { return .status(204, "") }
            await gate.wait()
            return .status(200, sessionResponseBody())
        }
        let auth = AuthService(client: sut)
        auth.restoreSession()

        let request = Task { try await SupabaseClient.accessToken(sut.auth) }
        await waitUntil("refresh sent") { server.refreshCount == 1 }
        await auth.signOut()
        gate.open()

        do {
            _ = try await request.value
            Issue.record("expected a throw")
        } catch {
            guard case SupabaseError.sessionChanged = error else {
                Issue.record("expected sessionChanged, got \(error)")
                return
            }
            #expect(error.localizedDescription == "You signed out or switched accounts before this finished.")
        }
        #expect(storage.storedSession == nil)
        #expect(!auth.isAuthenticated)
    }

    @Test func signInDuringFailingRefresh_keepsTheNewSession() async throws {
        let storage = signedInStorage()
        let server = FakeServer()
        let gate = TransportGate()
        let log = AuthLog()
        let sut = testClient(storage, server: server, log: log) { request, _ in
            if request.isRefresh {
                await gate.wait()
                return .status(400, refreshTokenNotFound)
            }
            return .status(200, sessionResponseBody(refreshToken: "b-refresh", email: "b@example.com"))
        }
        let auth = AuthService(client: sut)
        auth.restoreSession()
        auth.observeAuthChanges() // starts the launch refresh for the old session
        await waitUntil("refresh sent") { server.refreshCount == 1 }

        try await auth.signInWithApple(identityToken: Data("id.token".utf8), rawNonce: "raw-nonce")
        gate.open()
        await waitUntil("refresh finished") { log.count(AuthLog.refreshEnded) == 1 }

        #expect(storage.storedSession?.refreshToken == "b-refresh", "the old refresh's failure keeps the new session")
        #expect(auth.isAuthenticated)
        #expect(auth.userEmail == "b@example.com")
    }
}

struct RefreshCase: Sendable, CustomTestStringConvertible {
    let name: String
    let reply: FakeReply
    let definitive: Bool
    /// Requests the refresh makes: the SDK retries timeouts, offline and 5xx once.
    let attempts: Int

    init(_ name: String, _ reply: FakeReply, definitive: Bool, attempts: Int = 1) {
        self.name = name
        self.reply = reply
        self.definitive = definitive
        self.attempts = attempts
    }

    var testDescription: String { name }
}
