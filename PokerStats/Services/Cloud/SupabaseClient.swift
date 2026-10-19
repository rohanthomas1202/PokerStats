import Auth
import Foundation
import Functions
import PostgREST
import Storage

enum SupabaseError: LocalizedError, Sendable {
    case httpError(statusCode: Int, message: String)
    /// No session, or the server rejected the refresh token. The SDK has
    /// already removed the stored session.
    case sessionExpired
    /// A token refresh failed for a non-auth reason (offline, timeout, 5xx).
    /// The session is kept; the next request tries again.
    case refreshUnavailable

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message): "HTTP \(code): \(message)"
        case .sessionExpired: "Session expired. Please sign in again."
        case .refreshUnavailable: "Couldn't reach the server. Check your connection and try again."
        }
    }
}

/// The app's Supabase clients from supabase-swift, sharing one Auth session.
///
/// Auth (`auth`) owns the session: it stores it with `sessionStorage`,
/// refreshes it single-flight, drops a refresh that finishes after the
/// session changed, and removes the session only for the refresh-token and
/// session error codes. Storage, PostgREST and Functions requests get the
/// current access token from `auth.session` (refreshing first if needed).
final class SupabaseClient: Sendable {
    static let shared = SupabaseClient()

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let auth: AuthClient
    let storage: SupabaseStorageClient
    let database: PostgrestClient
    let functions: FunctionsClient

    /// Key the session is stored under in `sessionStorage`.
    static let sessionStorageKey = "com.rohanthomas.PokerStats.session"

    /// Tests pass an in-memory session storage and a fake transport.
    init(
        url: URL = URL(string: Secrets.supabaseURL)!,
        anonKey: String = Secrets.supabaseAnonKey,
        sessionStorage: any AuthLocalStorage = KeychainSessionStorage(),
        autoRefreshToken: Bool = true,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        let headers = ["apikey": anonKey]
        let auth = AuthClient(configuration: AuthClient.Configuration(
            url: url.appendingPathComponent("auth/v1"),
            headers: headers,
            storageKey: Self.sessionStorageKey,
            localStorage: sessionStorage,
            fetch: transport,
            autoRefreshToken: autoRefreshToken,
            emitLocalSessionAsInitialSession: true
        ))
        let authorized: Transport = { request in
            var request = request
            request.setValue("Bearer \(try await Self.accessToken(auth))", forHTTPHeaderField: "Authorization")
            return try await transport(request)
        }

        self.auth = auth
        storage = SupabaseStorageClient(configuration: StorageClientConfiguration(
            url: url.appendingPathComponent("storage/v1"),
            headers: headers,
            session: StorageHTTPSession(
                fetch: authorized,
                upload: { request, data in
                    var request = request
                    request.httpBody = data
                    return try await authorized(request)
                }
            ),
            logger: nil
        ))
        database = PostgrestClient(
            url: url.appendingPathComponent("rest/v1"),
            headers: headers,
            logger: nil,
            fetch: authorized,
            encoder: Self.databaseEncoder,
            decoder: Self.databaseDecoder
        )
        functions = FunctionsClient(
            url: url.appendingPathComponent("functions/v1"),
            headers: headers,
            fetch: authorized
        )
    }

    /// The current access token, refreshed first if it has expired. Maps the
    /// refresh outcome to the app's errors: a missing or rejected session is
    /// `.sessionExpired`; anything else (offline, timeout, 5xx, a 401 that
    /// isn't about the refresh token) keeps the session and is `.refreshUnavailable`.
    static func accessToken(_ auth: AuthClient) async throws -> String {
        do {
            return try await auth.session.accessToken
        } catch AuthError.sessionMissing {
            throw SupabaseError.sessionExpired
        } catch {
            throw SupabaseError.refreshUnavailable
        }
    }

    // MARK: - Edge Functions

    /// POSTs `body` as snake_case JSON. A non-2xx response throws
    /// `SupabaseError.httpError` with the response body, which
    /// `AccountDeleter` reads.
    func callEdgeFunction(_ name: String, body: some Encodable & Sendable) async throws {
        do {
            try await functions.invoke(name, options: FunctionInvokeOptions(body: body, encoder: Self.functionsEncoder))
        } catch FunctionsError.httpError(let code, let data) {
            throw SupabaseError.httpError(statusCode: code, message: String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: - Coding

    private static let functionsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// The PostgREST date formats, with snake_case keys for the app's models.
    private static let databaseEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = PostgrestClient.Configuration.jsonEncoder.dateEncodingStrategy
        return encoder
    }()

    private static let databaseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = PostgrestClient.Configuration.jsonDecoder.dateDecodingStrategy
        return decoder
    }()
}
