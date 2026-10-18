import Auth
import Foundation
import Testing
@testable import PokerStats

/// In-memory stand-in for the Keychain session storage.
final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }

    /// Stores `session` the way supabase-swift does (default `JSONEncoder`).
    func seed(_ session: Auth.Session) {
        try! store(key: SupabaseClient.sessionStorageKey, value: JSONEncoder().encode(session))
    }

    var storedSession: Auth.Session? {
        let data = try? retrieve(key: SupabaseClient.sessionStorageKey)
        return data.flatMap { try? JSONDecoder().decode(Auth.Session.self, from: $0) }
    }
}

enum TestUser {
    static let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    static let appleUserId = "001234.abc"
}

/// A session for `TestUser`. Expired by default, so the next request refreshes it.
func testSession(
    accessToken: String = "old-access",
    refreshToken: String = "old-refresh",
    email: String = "old@example.com",
    expired: Bool = true
) -> Auth.Session {
    let now = Date()
    let expiresAt = expired ? now.addingTimeInterval(-60) : now.addingTimeInterval(3600)
    let identity = UserIdentity(
        id: TestUser.appleUserId,
        identityId: UUID(),
        userId: TestUser.id,
        identityData: ["sub": .string(TestUser.appleUserId)],
        provider: "apple",
        createdAt: now,
        lastSignInAt: now,
        updatedAt: now
    )
    let user = User(
        id: TestUser.id,
        appMetadata: [:],
        userMetadata: [:],
        aud: "authenticated",
        email: email,
        createdAt: now,
        updatedAt: now,
        identities: [identity]
    )
    return Auth.Session(
        accessToken: accessToken,
        tokenType: "bearer",
        expiresIn: 3600,
        expiresAt: expiresAt.timeIntervalSince1970,
        refreshToken: refreshToken,
        user: user
    )
}

/// The JSON Supabase Auth returns for a new session.
func sessionResponseBody(
    accessToken: String = "new-access",
    refreshToken: String = "new-refresh",
    email: String = "new@example.com"
) -> String {
    let expiresAt = Int(Date().timeIntervalSince1970) + 3600
    return """
    {"access_token":"\(accessToken)","token_type":"bearer","expires_in":3600,"expires_at":\(expiresAt),
     "refresh_token":"\(refreshToken)",
     "user":{"id":"\(TestUser.id.uuidString)","aud":"authenticated","email":"\(email)",
             "app_metadata":{},"user_metadata":{},
             "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z",
             "identities":[{"id":"\(TestUser.appleUserId)","user_id":"\(TestUser.id.uuidString)",
                            "identity_data":{"sub":"\(TestUser.appleUserId)"},"provider":"apple"}]}}
    """
}

/// What the fake server sends back.
enum FakeReply: Sendable {
    case status(Int, String)
    case urlError(URLError.Code)
}

/// One request the fake server saw.
struct SeenRequest: Sendable {
    let method: String
    let path: String
    let query: String?
    let headers: [String: String]
    let body: Data?

    var isRefresh: Bool { path.hasSuffix("/auth/v1/token") && query == "grant_type=refresh_token" }

    var json: [String: Any]? {
        body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

/// Records every request and answers with `respond`, given the request and
/// its index among all requests.
final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [SeenRequest] = []

    var requests: [SeenRequest] { lock.withLock { seen } }
    var refreshCount: Int { requests.filter(\.isRefresh).count }

    func record(_ request: URLRequest) -> (SeenRequest, Int) {
        let url = request.url!
        let entry = SeenRequest(
            method: request.httpMethod ?? "GET",
            path: url.path(),
            query: url.query(),
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        )
        return lock.withLock {
            seen.append(entry)
            return (entry, seen.count - 1)
        }
    }
}

/// A client for `storage` whose requests go to `respond`. Auto refresh is off;
/// tests trigger refreshes themselves.
func testClient(
    _ storage: InMemoryAuthStorage,
    server: FakeServer = FakeServer(),
    respond: @escaping @Sendable (SeenRequest, Int) async throws -> FakeReply
) -> SupabaseClient {
    SupabaseClient(
        url: URL(string: "https://example.supabase.co")!,
        anonKey: "anon-key",
        sessionStorage: storage,
        autoRefreshToken: false
    ) { request in
        let (seen, index) = server.record(request)
        switch try await respond(seen, index) {
        case .urlError(let code):
            throw URLError(code)
        case .status(let code, let body):
            // Supabase Auth answers the API version the SDK asks for; with it,
            // the error code is the string in `code`.
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: code,
                httpVersion: nil,
                headerFields: ["X-Supabase-Api-Version": "2024-01-01"]
            )!
            return (Data(body.utf8), response)
        }
    }
}

/// Holds the fake transport until the test opens it.
final class TransportGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if isOpen { return true }
                waiting.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let toResume = lock.withLock {
            isOpen = true
            defer { waiting.removeAll() }
            return waiting
        }
        toResume.forEach { $0.resume() }
    }
}

/// Polls until `condition` holds (or records a timeout after ~10 s).
@MainActor
func waitUntil(_ what: String, _ condition: () async -> Bool) async {
    for _ in 0..<1000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for \(what)")
}

/// Gives queued auth events time to arrive before checking nothing changed.
func settle() async {
    try? await Task.sleep(for: .milliseconds(200))
}
